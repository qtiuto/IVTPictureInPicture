//
//  IVTMovFile.cpp
//
//  Created by Osl on 2020/1/31.
//  Copyright © 2020 Gavin. All rights reserved.
//

#include "IVTMovFile.h"
#include "IVTMovFormat.h"
#include <AVFoundation/AVFoundation.h>
#include <assert.h>
#include <cstddef>
#include <libgen.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <array>
#include <mutex>
#include <numeric>
#include <mach/mach_time.h>
#include <mach/vm_map.h>
#include <mach/mach.h>

#define CheckStatusAndReturn(exp) \
    ({                             \
        if (auto st = exp) {      \
            return st;            \
        };                        \
    })

#ifndef DEBUG
#define assert(e)
#endif


static BOOL isReadableAddress(void * address) {
    if (address == MAP_FAILED) {
        return false;
    }
    // Read the memory
    vm_size_t size = 0;
    char buf[sizeof(uintptr_t)];
    kern_return_t error = vm_read_overwrite(mach_task_self(), (vm_address_t)address, sizeof(uintptr_t), (vm_address_t)buf, &size);
    return error == KERN_SUCCESS;
}

static inline int64_t dateConvert(time_t time) {
    static time_t since;
    if (!since) {
        struct tm since_tm = { .tm_year = 4, .tm_mday = 1 };
        since              = timegm(&since_tm);
    }
    return (int64_t)(time - since);
}

namespace IVT {


struct stsc {
    uint firstChunk = 0;
    uint sampleSize = 0;
    static constexpr int sampleDescription = 1;

    operator SampleToChunkAtom::SampleToChunkEntry() {
        return { firstChunk, sampleSize, sampleDescription };
    }
};

struct FD {
    int fd = 0;
    FD() {}
    FD(int fd): fd(fd) {
    }
    FD(const FD &) = delete;
    FD(FD && o): fd(o.fd){
        o.fd = 0;
    };
    FD &operator=(const FD &) = delete;
    FD &operator=(FD &&o) {
        int fd = o.fd;
        o.fd = this->fd;
        this->fd = fd;
        return *this;
    }
    operator int() const {
        return fd;
    }
    ~FD() {
        if (fd) {
            close(fd);
        }
    }
};

struct MovSeg {
    CMTime start    = kCMTimeZero;
    CMTime writeEnd = kCMTimeZero;
    std::vector<uint> sampleSizes;  // stsz Sample Size Atoms
    std::vector<uint> chunkOffsets; // stco Chunk Offset Atoms
    std::vector<stsc> chunkSampleSizes;   // stsc Sample-to-Chunk Atoms
    std::vector<uint> keyFrames;    // stss sync sample atoms

    std::string path;
    FD fd;
    FD fd_r;
    uint fileSize = 0;
    
    std::vector<char> caches;
    int lastCacheOffset = 0;
    bool cacheToMemory;

    int lastSample = 0;
    int lastSampleOffset = 0;

    MovSeg() {}
    MovSeg(const MovSeg &) = delete;
    MovSeg(MovSeg &&)      = default;

    MovSeg &operator=(MovSeg &&) = default;

    int keyFrameForSample(int sample) { //key frame is chunk start
        int base = 0;
        for (auto begin = chunkSampleSizes.begin(); begin != chunkSampleSizes.end(); begin++) {
            auto endChunk = (begin + 1) == chunkSampleSizes.end() ? chunkOffsets.size() + 1 : (begin + 1)->firstChunk;
            auto end      = base + begin->sampleSize * (endChunk - begin->firstChunk);
            if (sample < end) {
                return sample - (sample - base) % begin->sampleSize;
            }
            base = (int)end;
        }
        assert(false);
        return -1;
    }
    
    bool validateChunks() {
        size_t baseSample = 0;
        size_t  totalSampleSize = 0;
        for (auto begin = chunkSampleSizes.begin(); begin != chunkSampleSizes.end(); begin++) {
            auto sampleSize = begin->sampleSize;
            auto endChunk = (begin + 1) == chunkSampleSizes.end() ? chunkOffsets.size() + 1 : (begin + 1)->firstChunk;
            for (auto i = begin->firstChunk; i < endChunk; i++) {
                int chunkOffset = chunkOffsets[i - 1];
                assert(chunkOffset == totalSampleSize);
                auto size = std::accumulate(sampleSizes.begin() + baseSample, sampleSizes.begin() + baseSample + sampleSize, 0);
                totalSampleSize += size;
                baseSample += sampleSize;
            }
        }
        assert(fileSize == totalSampleSize);
        assert(baseSample == sampleSizes.size());
        return true;
    }
    
    void eraseFrameNotLessThan(int frame) {
        int offset = offsetForSample(frame);
        fileSize = offset;
        long deletedSampleCount = sampleSizes.size() - frame;
        for (auto i = chunkOffsets.size(); i--; ) {
            auto chunk = i + 1;
            auto&& back = chunkSampleSizes.back();
            assert(chunk >= back.firstChunk);
            
            deletedSampleCount -= back.sampleSize;
            if (deletedSampleCount >= 0) {
                chunkOffsets.pop_back();
                if (chunk == back.firstChunk) {
                    chunkSampleSizes.pop_back();
                }
            } else {
                chunkSampleSizes.push_back({.firstChunk = (uint)chunk,.sampleSize = (uint) -deletedSampleCount});
            }
            
            if (deletedSampleCount <= 0) {
                break;
            }
        }
        
        sampleSizes.erase(sampleSizes.begin() + frame, sampleSizes.end());
        assert(validateChunks());
        for (auto i = keyFrames.size(); i--; ) {
            if (keyFrames[i] -1 >= frame) {
                keyFrames.erase(keyFrames.begin() + i);
            } else {
                break;
            }
        }
        
    }
    int offsetForSample(int sample) {
        if (abs(lastSample - sample) < 10) {
            bool neg = lastSample > sample;
            int sum = 0, i = neg ? sample : lastSample , end = neg ? lastSample : sample;
            while (i != end) {
                sum += sampleSizes[i++];
            }
            lastSample = sample;
            lastSampleOffset = neg ? lastSampleOffset - sum : lastSampleOffset + sum;
            return lastSampleOffset;
        } else {
            int base = 0;
            for (auto begin = chunkSampleSizes.begin(); begin != chunkSampleSizes.end(); begin++) {
                auto endChunk = (begin + 1) != chunkSampleSizes.end() ? (begin + 1)->firstChunk : chunkOffsets.size() + 1;
                auto end      = base + begin->sampleSize * (endChunk - begin->firstChunk);
                if (sample < end) {
                    int chunk        = begin->firstChunk + (sample - base) / begin->sampleSize;
                    int offset       = (sample - base) % begin->sampleSize;
                    int sampleOffset = chunkOffsets[chunk - 1];
                    for (; offset; --offset) {
                        sampleOffset += sampleSizes[sample - offset];
                    }
                    lastSample       = sample;
                    lastSampleOffset = sampleOffset;
                    return sampleOffset;
                }
                base = (int)end;
            }
        }
        return -1;
    }
    
    long append(const char* ptr, size_t length) {
        auto fileSize = this->fileSize;
        auto ret = write(ptr, length, fileSize);
        if (ret == -1) {
            return -1;
        }
        this->fileSize = uint(fileSize + length);
        return length;
    }
    
    long write(const char* ptr, size_t length, off_t offset) {
        if (cacheToMemory) {
            return writeToCache(ptr, length, offset);
        }
        int fd = this->fd;
        long w = 0, total = length;
        while (length != 0 && (w = pwrite(fd, ptr, length, offset)) >= 0) {
            length -= w;
            ptr += w;
            offset += w;
        }
        return w == -1 ? -1 : total;
    }
    
    long writeToCache(const char* ptr, size_t length, off_t offset) {
        if (offset + length > caches.size()) {
            caches.resize(offset + length);
        }
        std::memcpy((&(*caches.begin())) + offset, ptr, length);
        return length;
    }
    
    void writeToFD(int fd) {
        if (cacheToMemory) {
            ::write(fd, &(*caches.begin()), caches.size());
            return;
        }
        char buff[8192];
        int sourceFD = open(path.data(), O_RDONLY);
        while (auto count = ::read(sourceFD, buff, 8192)) {
            ::write(fd, buff, count);
        }
        close(fd);
    }
    
    long readToMemory(void* ptr) {
        if (cacheToMemory) {
            return readFromCache(ptr, 0 , caches.size());
        }
        long size = 0;
        int fd = open(path.data(), O_RDONLY);
        while (auto count = ::read(fd, ptr, 8192 * 2)) {
            size += count;
            ptr = (char *)ptr + count;
        }
        close(fd);
        return size;
    }
    
    long read(void* ptr, size_t length, off_t offset) const {
        if (cacheToMemory) {
            return readFromCache(ptr, length, offset);
        }
        int fd = fd_r;
        char *buf = (char *)ptr;
        long r = 0, total = length;
        while (length != 0 && (r = pread(fd, buf, length, offset)) >= 0) {
            length -= r;
            buf += r;
            offset += r;
        }
        return r == -1 ? -1 : total;
    }
    
    long readFromCache(void *target, size_t offset, size_t size) const {
        if (offset > caches.size()) {
            return -1;
        }
        auto read = std::min(size, caches.size() - offset);
        std::memcpy(target, (&(*caches.begin())) + offset, read);
        return read;
    }
    
    bool check() const {
        if (cacheToMemory) {
            return fileSize == caches.size();
        }
        struct stat buffer;
        fstat(fd, &buffer);
        return buffer.st_size == fileSize;
    }
};

static void releaseVTCompressionSession(CFTypeRef ref) {
    VTCompressionSessionInvalidate((VTCompressionSessionRef)ref);
    CFRelease(ref);
}

static void releaseVTDecompressionSession(CFTypeRef ref) {
    VTDecompressionSessionInvalidate((VTDecompressionSessionRef)ref);
    CFRelease(ref);
}

class MovFile : public IMovFile, public std::enable_shared_from_this<MovFile> {
    friend class MovFileDelegate;
    typedef CFObject<VTDecompressionSessionRef, id, releaseVTDecompressionSession> Reader;
    typedef CFObject<VTCompressionSessionRef, id, releaseVTCompressionSession> Writer;
    struct ReaderFrameRef {
        CFObject<CVImageBufferRef> lastDecodedImage;
        OSStatus lastDecodeError = 0;
    };
    std::string outputDir;

    CFObject<CMVideoFormatDescriptionRef> videoFormat;
    CMTime lastInputFrameTime = kCMTimeInvalid;
    bool lazyWriter = false;
    
    int lastDecodeSample = -1;
    int lastDecodeKeyFrame = 0;
    std::atomic<OSStatus> lastEncodeError;

    uint32_t maxFrameSize = 0;
    EncodeQuality quality;
    std::vector<uint8_t> readerCache;

    std::vector<MovSeg*> segments;
    std::mutex segLock;
    std::mutex encodeLock;
    std::mutex decodeLock;

    Reader reader;
    Writer writer;
    VTCompressionOutputHandler writerCallback;

public:
    MovFile(const MovFile &) = delete;

    MovFile(int frameRate, int timeScale, int width, int height, EncodeQuality quality, const char *outputPath, int maxKeyFrameInterval)
    : IMovFile(frameRate, timeScale, width, height, outputPath, maxKeyFrameInterval), quality(quality) {
        outputDir = dirname((char *)outputPath); // safe in darwin or ios, but not in glibc
        struct stat sb;
        if (stat(outputDir.c_str(), &sb) != 0) {
            mkdir(outputDir.c_str(), 0777);
        } else if (!S_ISDIR(sb.st_mode)){
            unlink(outputDir.c_str());
            mkdir(outputDir.c_str(), 0777);
        }
        readerCache.reserve((width * height)>> 3);
        lastEncodeError = 0;
    }
    
    virtual ~MovFile() {
        for (auto &&seg : segments) {
            seg->fd = FD();
            remove(seg->path.data());
        }
    }

    OSStatus createWriter() {
        lazyWriter = false;
        Writer writer;
        CheckStatusAndReturn(VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, NULL, NULL, writer.out()));
        CheckStatusAndReturn(VTSessionSetProperty(writer, kVTCompressionPropertyKey_ProfileLevel, profileLevel()));
        CheckStatusAndReturn(VTSessionSetProperty(writer, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse));
        CFBooleanRef realTime = kCFBooleanFalse;
        if (@available(iOS 11, *)) {
            realTime = kCFBooleanTrue;
        }
        CheckStatusAndReturn(VTSessionSetProperty(writer, kVTCompressionPropertyKey_RealTime, realTime));
        if (quality != BaseQuality) {
            CheckStatusAndReturn(VTSessionSetProperty(writer, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFNumberRef)@(maxKeyFrameInterval)));
            //设置码率，均值，单位是byte
            CheckStatusAndReturn(VTSessionSetProperty(writer, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFNumberRef)@(bitRate())));
        }
        CheckStatusAndReturn(VTCompressionSessionPrepareToEncodeFrames(writer));
        
        
        auto strongThis = [wThis = std::weak_ptr<MovFile>(this->shared_from_this())] () {
            return wThis.lock();
        };

        writerCallback = ^(OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef  _Nullable sampleBuffer) {
            auto movFile = strongThis();
            if (!movFile) {
                return;
            }
            if (status || sampleBuffer == nullptr) {
                movFile->lastEncodeError = status ?: kVTInvalidSessionErr;
                return;
            }
            if (!(infoFlags & kVTEncodeInfo_FrameDropped)) {
                if (CMSampleBufferDataIsReady(sampleBuffer)) {
                    movFile->handleEncodedFrame(sampleBuffer);
                }
            }
        };
        
        this->writer = std::move(writer);
        lastInputFrameTime = kCMTimeInvalid;
        return 0;
    }
    
    CFStringRef profileLevel() {
        switch (quality) {
            case IMovFile::BaseQuality:
                return kVTProfileLevel_H264_Baseline_AutoLevel;
            case IMovFile::MainQuality:
                return kVTProfileLevel_H264_Main_AutoLevel;
            default:
                return kVTProfileLevel_H264_High_AutoLevel;
        }
    }
    
    int bitRate() {
        switch (quality) {
            case IMovFile::BaseQuality:
                return width * height * frameRate / 8;
            case IMovFile::MainQuality:
                return width * height * frameRate / 10;
            default:
                return width * height * frameRate / 12;
        }
    }

    OSStatus createReader() {
        std::lock_guard<std::mutex> sentry(decodeLock);
        if (this->reader) {
            return 0;
        }
        Reader reader;
        NSDictionary *destImageAttributes =@{
#if TARGET_OS_IPHONE
        (id)kCVPixelBufferOpenGLESCompatibilityKey: @(YES),
#endif
        (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
        CheckStatusAndReturn(VTDecompressionSessionCreate(nullptr, videoFormat, nullptr, (__bridge CFDictionaryRef)destImageAttributes, nullptr, reader.out()));
        this->reader = std::move(reader);
        return 0;
    }

    int pendingFrames() {
        CFObject<CFNumberRef> ret;
        if (writer) {
            int err = VTSessionCopyProperty(writer, kVTCompressionPropertyKey_NumberOfPendingFrames, nullptr, ret.out());
            if (err) {
                return 0;
            }
            int v;
            CFNumberGetValue(ret, kCFNumberIntType, &v);
            return v;
        }
        return 0;
    }
    
    void fixTime(CMTime& val) {
        auto srcRate = val.timescale;
        if (srcRate == 0) {
            return;
        }
        int frameRate = this->frameRate;
        if (srcRate < frameRate) {
            return;
        }
        val.value = val.value * frameRate / srcRate;
        val.timescale = frameRate;
    }

    MovSeg *findMovSeg(CMTime time) {
        for (auto seg : segments) {
            if (CMTimeCompare(time, seg->start) >= 0 && CMTimeCompare(time, seg->writeEnd) <= 0) {
                return seg;
            }
        }
        return nullptr;
    }

    MovSeg &ensureMovSeg(CMTime time, bool *needInsert) {
        
        for (auto&& seg : segments) {
            if (CMTimeCompare(time, seg->start) >= 0) {
                *needInsert = false;
                return *seg;
            }
        }
        
        
        MovSeg& ret = *new MovSeg();
        ret.start   = time;
        ret.path    = outputDir + "/mov_data_seg" + std::to_string(time.value * timeScale / time.timescale);
        ret.cacheToMemory = cacheFileToMemory;
        if (!cacheFileToMemory) {
            int fd   = open(ret.path.data(), O_CREAT | O_TRUNC | O_WRONLY, 0660);
            int fd_r = open(ret.path.data(), O_RDONLY);
            fcntl(fd_r, F_RDAHEAD, 1);
            fcntl(fd_r, F_NOCACHE, 0);
            ret.fd = fd;
            ret.fd_r = fd_r;
        }
        *needInsert = true;
        return ret;
    }
    
    int encodeSample(CMSampleBufferRef sample) override {
        if (CMSampleBufferGetDataBuffer(sample)) {
            return handleEncodedFrame(sample);
        } else {
            CFObject<CVPixelBufferRef> buffer = CMSampleBufferGetImageBuffer(sample);
            return encodeFrame(buffer, CMSampleBufferGetPresentationTimeStamp(sample));
        }
    }
    
    int encodeFrame(CVPixelBufferRef buffer, CMTime frameTime) override {
        VTEncodeInfoFlags flag = 0;
        if (lastEncodeError) {
            return lastEncodeError;
        }
        if(!writer) {
            createWriter();
        }
        fixTime(frameTime);
        CFObject<CFMutableDictionaryRef> options;
        CMTime _lastInputFrameTime = this->lastInputFrameTime;
        if (!CMTIME_IS_VALID(_lastInputFrameTime) || CMTimeCompare(frameTime, _lastInputFrameTime) < 0 || CMTimeCompare(CMTimeSubtract(frameTime, _lastInputFrameTime), CMTimeMake(2, frameRate)) >=0) {
            if (CMTIME_IS_VALID(lastEncodedFrameTime) && findMovSeg(frameTime)) {
                return 0;
            }
            options = [NSMutableDictionary new];
            CFDictionarySetValue(options, kVTEncodeFrameOptionKey_ForceKeyFrame, kCFBooleanTrue);
        }
        std::lock_guard<std::mutex> sentry(encodeLock);
        auto session = writer.get();
        OSStatus err = !session ? kVTInvalidSessionErr : VTCompressionSessionEncodeFrameWithOutputHandler(session, buffer, frameTime, kCMTimeInvalid, options, &flag, writerCallback);
        if (err) {
            writer = nullptr;
            writerCallback = nullptr;
        }
        lastInputFrameTime = frameTime;
        return err;
    }
    
    static bool validateSampleData(const char *dataPointer, size_t totalLength) {
        int i = 0;
        while(i < totalLength) {
            buint& size = *(buint*)(dataPointer + i);
            uint k = size;
            i += k + 4;
        }
        return i == totalLength;
    }

    int handleEncodedFrame(CMSampleBufferRef frame) {
        bool isKeyFrame = ![[(__bridge NSDictionary *)CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(frame, true), 0) objectForKey:(__bridge NSString *)kCMSampleAttachmentKey_NotSync] boolValue];

        if (!videoFormat) {
            videoFormat = CMSampleBufferGetFormatDescription(frame);
        }
        
        if (!reader && autoCreateReaderOnWriting) {
            createReader();
        }

        CMTime decodeTime           = CMSampleBufferGetDecodeTimeStamp(frame);
        CMTime presentTime          = CMSampleBufferGetPresentationTimeStamp(frame);
        assert(!CMTIME_IS_VALID(decodeTime) || (CMTimeCompare(decodeTime, presentTime) == 0 && "time differs is not supported"));
        bool needInsert;
        MovSeg &seg = ensureMovSeg(presentTime, &needInsert);
        std::unique_ptr<MovSeg> segCleaner;
        if (needInsert) {
            segCleaner = std::unique_ptr<MovSeg>(&seg);
        }
        if (!isKeyFrame && !seg.chunkSampleSizes.size()) {
            return kVTVideoEncoderNotAvailableNowErr;
        }
        CMTime segTime       = CMTimeSubtract(presentTime, seg.start);
        int sampleNum        = (int)(segTime.value * frameRate / segTime.timescale);
        
        size_t totalLength;
        char *dataPointer;
        CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(frame);
        OSStatus err = CMBlockBufferGetDataPointer(dataBuffer, 0, NULL, &totalLength, &dataPointer);
        if (seg.sampleSizes.size() && CMTimeCompare(presentTime, seg.start) >= 0 && CMTimeCompare(presentTime, seg.writeEnd) <= 0) {
            std::lock_guard<std::mutex> sentry(segLock);
            assert(isKeyFrame);
            seg.writeEnd = presentTime.value == 0 ? kCMTimeZero : CMTimeSubtract(presentTime, CMTimeMake(1, frameRate));
            seg.eraseFrameNotLessThan(sampleNum);
            lastEncodedFrameTime = seg.writeEnd;
        }
        assert(!CMTIME_IS_VALID(lastEncodedFrameTime) || CMTimeSubtract(presentTime, lastEncodedFrameTime).value != 0);
        int offset   = seg.fileSize;
        if (err == noErr) {
            assert(validateSampleData(dataPointer, totalLength));
            maxFrameSize = MAX(maxFrameSize, (uint32_t)totalLength);
            if (seg.append(dataPointer, totalLength) == -1) {
                return errno;
            }
            seg.writeEnd = presentTime;
        } else {
            return err;
        }
        lastEncodedFrameTime = presentTime;
        // assert(sampleNum == seg.sampleSizes.size());
        std::lock_guard<std::mutex> sentry(segLock);
        seg.sampleSizes.push_back((int)totalLength);
        if (isKeyFrame) {
            seg.keyFrames.push_back(sampleNum + 1);
            uint chunkNum = (uint)seg.chunkOffsets.size() + 1;
            seg.chunkOffsets.push_back(offset);
            if (seg.chunkSampleSizes.size() > 1) {
                int prevSampleSize = ((&seg.chunkSampleSizes.back()) - 1)->sampleSize;
                if (seg.chunkSampleSizes.back().sampleSize == prevSampleSize) {
                    seg.chunkSampleSizes.pop_back();
                }
            }
            seg.chunkSampleSizes.push_back({chunkNum, 0});
        }
        seg.chunkSampleSizes.back().sampleSize++;
        if (needInsert) {
            segments.insert(segments.begin(), segCleaner.release());
        }
        return 0;
    }

    void mergeSegments(MovSeg &finalSeg) {
        uint32_t fileSize   = 0;
        uint32_t chunkCount = 0;
        uint32_t sampleSize = 0;
        for (auto&& seg : segments) {
            assert(seg->check());
            assert(CMTimeCompare(finalSeg.writeEnd, seg->writeEnd) <= 0);
            finalSeg.writeEnd = seg->writeEnd;
            finalSeg.sampleSizes.insert(finalSeg.sampleSizes.end(), seg->sampleSizes.begin(), seg->sampleSizes.end());
            for (auto &&frame : seg->keyFrames) {
                finalSeg.keyFrames.push_back(frame + sampleSize);
            }
            for (auto &&offset : seg->chunkOffsets) {
                finalSeg.chunkOffsets.push_back(offset + fileSize);
            }
            auto &&begin = seg->chunkSampleSizes.begin();
            if (finalSeg.chunkSampleSizes.size() && begin->sampleSize == finalSeg.chunkSampleSizes.back().sampleSize) {
                ++begin;
            }
            for (; begin != seg->chunkSampleSizes.end(); ++begin) {
                finalSeg.chunkSampleSizes.push_back({ begin->firstChunk + chunkCount, begin->sampleSize });
            }
            fileSize += seg->fileSize;
            chunkCount += seg->chunkOffsets.size();
            sampleSize += seg->sampleSizes.size();
        }

        finalSeg.path     = outputPath;
        finalSeg.fd       = open(finalSeg.path.data(), O_CREAT | O_RDWR, 0660);
        finalSeg.fileSize = fileSize;
        assert(finalSeg.validateChunks());
    }
    

    void finishWriting(std::function<void(NSError *err)> completion) override {
        if (!lazyWriter || writer){
            if(auto err = VTCompressionSessionCompleteFrames(writer, kCMTimeInvalid) ?: (OSStatus)lastEncodeError) {
                completion([NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil]);
                return;
            }
        }
        if (segments.empty()) {
            completion([NSError errorWithDomain:NSOSStatusErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey:@"No media generated"}]);
            return;
        }
        if (finishConfig.way == BY_SYSTEM) {
            finishWritingWithAVAsset(completion);
            return;
        }
        MovSeg finalSeg = {};
        mergeSegments(finalSeg);
        
        uint copyLastCount = finishConfig.copyLastFrameCount;
        uint lastFrameSize = 0;
        int lastFrameOffset = 0;
        int lastKeyFrameOffset = 0;
        uint batchCopySize = 0;
        uint batchCopyCount = 0;
        uint compensateCopyCount = 0;
        int copyFrameInterval = maxKeyFrameInterval;
        if (copyLastCount > 0) {
            if (finalSeg.sampleSizes.empty()) {
                completion([NSError errorWithDomain:NSOSStatusErrorDomain code:-1 userInfo:@{@"copy frame error": @"no frame to copy"}]);
                return;
            }
            lastFrameSize = finalSeg.sampleSizes.back();
            auto lastKeyFrame = finalSeg.keyFrames.back() - 1;
            auto sampleCount = finalSeg.sampleSizes.size();
            auto populateStart = std::min(uint(lastKeyFrame + copyFrameInterval), uint(sampleCount + copyLastCount));
            bool isLastKey = sampleCount == lastKeyFrame + 1;
            
            finalSeg.sampleSizes.reserve(finalSeg.sampleSizes.size() + copyLastCount);
            auto leftCount = copyLastCount - (populateStart - sampleCount);
            auto compensate = leftCount % copyFrameInterval;
            leftCount -= compensate;
            populateStart += compensate;
            compensateCopyCount = uint(populateStart - sampleCount);
            batchCopyCount = uint(leftCount / copyFrameInterval);
            
            finalSeg.sampleSizes.insert(finalSeg.sampleSizes.end(), compensateCopyCount, lastFrameSize);
            long long copySize = lastFrameSize * compensateCopyCount;
            for (uint i = 0 ; i < batchCopyCount; i++) {
                finalSeg.sampleSizes.insert(finalSeg.sampleSizes.end(), finalSeg.sampleSizes.begin() + lastKeyFrame, finalSeg.sampleSizes.begin() + lastKeyFrame + copyFrameInterval);
                if (!isLastKey) {
                    finalSeg.keyFrames.push_back((uint)(populateStart + 1 + i * copyFrameInterval));
                }
            }
            batchCopySize = std::accumulate(finalSeg.sampleSizes.begin() + lastKeyFrame, finalSeg.sampleSizes.begin() + lastKeyFrame + copyFrameInterval, 0u);
            copySize += batchCopySize * batchCopyCount;
            if (isLastKey) {
                finalSeg.keyFrames.reserve(finalSeg.keyFrames.size() + copyLastCount);
                for (uint i = 0 ; i < copyLastCount; i++) {
                    finalSeg.keyFrames.push_back(lastKeyFrame + i + 2);
                }
            }
            
            finalSeg.chunkSampleSizes.back().sampleSize += copyLastCount;
            finalSeg.fileSize += copySize;
            finalSeg.writeEnd = CMTimeAdd(finalSeg.writeEnd, CMTimeMakeWithSeconds(copyLastCount / (double)frameRate, timeScale));
            lastFrameOffset = int(- copySize - lastFrameSize);
            lastKeyFrameOffset = lastFrameOffset - std::accumulate(finalSeg.sampleSizes.begin() + lastKeyFrame, finalSeg.sampleSizes.begin() + sampleCount - 1 , 0u);
        }
        
        reorderChunks(finalSeg);
        
        FileTypeAtom fileTypeAtom = {};
        MediaDataAtom mediaData   = {};
        CMTime cmduration = CMTimeAdd(finalSeg.writeEnd, CMTimeMake(1, frameRate));
        int64_t duration          = cmduration.value * timeScale / cmduration.timescale;
        time_t now                = time(NULL);
        uint64_t createTime       = dateConvert(now);
        MovieAtom movieAtom = MovieAtom(createTime, createTime, timeScale, frameRate, duration, width, height);
        assert(videoFormat);
        CFDictionaryRef pixelApsectRation = (CFDictionaryRef) CMFormatDescriptionGetExtension(videoFormat, kCMFormatDescriptionExtension_PixelAspectRatio);
        int hspacing = 0;
        int vspacing  = 0;
        if (pixelApsectRation) {
            CFNumberRef cfhSpacing= (CFNumberRef) CFDictionaryGetValue(pixelApsectRation, kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing);
            CFNumberRef cfvSpacing= (CFNumberRef) CFDictionaryGetValue(pixelApsectRation, kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing);
            CFNumberGetValue(cfhSpacing, kCFNumberSInt32Type, &hspacing);
            CFNumberGetValue(cfvSpacing, kCFNumberSInt32Type, &vspacing);
        }
        NSDictionary *extensionAtoms = (__bridge NSDictionary *) CMFormatDescriptionGetExtension(videoFormat, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms);
        assert(extensionAtoms);
        NSString *extensionAtomType = extensionAtoms.allKeys.firstObject;
        NSData *atomContent = [extensionAtoms objectForKey:extensionAtomType];
        assert(extensionAtomType);
        assert(atomContent);
        VideoExtensionAtom extAtom;
        extAtom.type = *(uint*) extensionAtomType.UTF8String;
        extAtom.dataLength = (uint32_t)atomContent.length;
        extAtom.atomData = atomContent.bytes;
        CFStringRef formatName = (CFStringRef) CMFormatDescriptionGetExtension(videoFormat, kCMFormatDescriptionExtension_FormatName);
        FourCharCode subType  = CMFormatDescriptionGetMediaSubType(videoFormat);
        CMMediaType mediaType = CMFormatDescriptionGetMediaType(videoFormat);
        assert(mediaType == kCMMediaType_Video);
        movieAtom.videoTrack.media.mediaInfo.sampleTable.description.
        data[0].fillIn(*(buint*)&subType,extAtom, CFStringGetCStringPtr(formatName, kCFStringEncodingASCII),hspacing, vspacing);
        movieAtom.videoTrack.media.mediaInfo.sampleTable.handleInfo(finalSeg.sampleSizes, finalSeg.chunkOffsets, finalSeg.chunkSampleSizes, finalSeg.keyFrames);
        movieAtom.calcSize();
        uint dataSize     = finalSeg.fileSize;
        mediaData.setSizeWithDataSize(dataSize, 0);
        uint headerSize   = fileTypeAtom.size + mediaData.headerSize() + movieAtom.size;
        uint dataOffset = headerSize;
        movieAtom.videoTrack.media.mediaInfo.sampleTable.chunkOffsetAtom.updateOffset(dataOffset);
        finalSeg.fileSize = dataSize + headerSize;
        ftruncate(finalSeg.fd, finalSeg.fileSize);
        auto mapSize            = finalSeg.fileSize;
        void *base              = mmap(NULL, mapSize, PROT_WRITE, MAP_FILE | MAP_SHARED, finalSeg.fd, 0);
        if (!isReadableAddress(base)) {
            if (base != MAP_FAILED) {
                munmap(base, mapSize);;
            }
            base = malloc(headerSize);
            if (base == nullptr) {
                completion([NSError errorWithDomain:NSOSStatusErrorDomain code:-1 userInfo:@{@"generate file error": @"no memory available"}]);
                return;
            }
            auto addr               = (uint8_t *)base;
            safewrite(fileTypeAtom);
            safewrite(movieAtom);
            addr = mediaData.writeTo(addr);
            write(finalSeg.fd, base, headerSize);
            free(base);
            for (auto&& seg : segments) {
                seg->writeToFD(finalSeg.fd);
            }
            if (copyLastCount > 0) {
                char *compensateBuff = (char *) malloc(batchCopySize);// 补偿帧最大缓冲
                if (compensateBuff == nullptr) {
                    completion([NSError errorWithDomain:NSOSStatusErrorDomain code:-1 userInfo:@{@"generate file error": @"no memory available"}]);
                    return;
                }
                pread(finalSeg.fd, compensateBuff, batchCopySize, mapSize + lastKeyFrameOffset);
                
                for (int i = 0; i < compensateCopyCount; i++) {
                    write(finalSeg.fd, compensateBuff + (lastFrameOffset - lastKeyFrameOffset), lastFrameSize);
                }
                
                for (int i = 0; i < batchCopyCount; i++) {
                    write(finalSeg.fd, compensateBuff, batchCopySize);
                }
                free(compensateBuff);
            }
            completion(nil);
            return;
        }
        auto addr               = (uint8_t *)base;
        safewrite(fileTypeAtom);
        safewrite(movieAtom);
        addr = mediaData.writeTo(addr);
        for (auto&& seg : segments) {
            addr += seg->readToMemory(addr);
        }
        if (copyLastCount > 0) {
            auto lastFrameAddr = (uint8_t *)base + mapSize + lastFrameOffset;
            auto lastKeyFrameAddr = (uint8_t *)base + mapSize + lastKeyFrameOffset;
            
            for (int i = 0; i < compensateCopyCount; i++) {
                assert(addr + lastFrameSize <= (uint8_t *)base + mapSize);
                memcpy(addr, lastFrameAddr, lastFrameSize);
                addr += lastFrameSize;
            }
            
            for (int i = 0; i < batchCopyCount; i++) {
                assert(addr + batchCopySize <= (uint8_t *)base + mapSize);
                memcpy(addr, lastKeyFrameAddr, batchCopySize);
                addr += batchCopySize;
            }
        }
        
        munmap(base, mapSize);
        completion(nil);
    }
    
    void reorderChunks(MovSeg& finalSeg) {
        const uint samplePerChunk = finishConfig.samplePerChunk;
        if (samplePerChunk == 0) {
            return;
        }
        auto finalChunkCount = finalSeg.sampleSizes.size() / samplePerChunk;
        auto leftCount = finalSeg.sampleSizes.size() % samplePerChunk;
        if (leftCount) {
            finalChunkCount++;
        }
        finalSeg.chunkSampleSizes.clear();
        finalSeg.chunkSampleSizes.push_back({1, 60});
        if (leftCount) {
            finalSeg.chunkSampleSizes.push_back({static_cast<uint>(finalChunkCount), static_cast<uint>(leftCount)});
        }
        finalSeg.chunkOffsets.clear();
        finalSeg.chunkOffsets.reserve(finalChunkCount);
        uint offset = 0;
        for (size_t i = 0, end = finalSeg.sampleSizes.size(); i < end; i++) {
            if (i % samplePerChunk == 0) {
                finalSeg.chunkOffsets.push_back(offset);
            }
            offset += finalSeg.sampleSizes[i];
        }
    }
    
    void finishWritingWithAVAsset(std::function<void(NSError *err)> completion) {
        @autoreleasepool {
            AVAssetWriter *writer = nil;
            @try {
                NSString *outputPath1 = [NSString stringWithUTF8String:outputPath.data()];
                NSURL *url = [NSURL fileURLWithPath:outputPath1];
                [NSFileManager.defaultManager removeItemAtPath:outputPath1 error:nil];
                writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeMPEG4 error:nil];
                AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:nil sourceFormatHint:videoFormat];
                writer.shouldOptimizeForNetworkUse = YES;
                [writer addInput:input];
                [writer startWriting];
                [writer startSessionAtSourceTime:kCMTimeZero];
                CFObject<CMSampleBufferRef> buf;
                int err = mergeSamples(buf.out());
                if (err) {
                     completion([NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil]);
                    return;
                }
                [input appendSampleBuffer:buf];
                [input markAsFinished];
                [writer finishWritingWithCompletionHandler:^{
                    completion(writer.error);
                }];
            } @catch (NSException *exception) {
                DLOG("%@",exception);
                completion([NSError errorWithDomain:AVFoundationErrorDomain code:AVErrorUnknown userInfo:nil]);
            }
        }
        
    }
    
    int mergeSamples(CMSampleBufferRef *outRef) {
        int keyFrameCount = 0, sampleCount = 0, fileSize = 0;
        for (auto seg : segments) {
            keyFrameCount += seg->keyFrames.size();
            fileSize += seg->fileSize;
            sampleCount += seg->sampleSizes.size();
        }
        int copyLastCount = finishConfig.copyLastFrameCount;
        int lastFrameSize = 0;
        bool isLastKeyFrame = false;
        if (copyLastCount > 0) {
            lastFrameSize = segments.back()->sampleSizes.back();
            fileSize += copyLastCount * lastFrameSize;
            sampleCount += copyLastCount;
            if (segments.back()->keyFrames.back() == segments.back()->sampleSizes.size()) {
                isLastKeyFrame = true;
            }
        }
        auto&& keyFrames = std::vector<uint>();
        keyFrames.reserve(keyFrameCount);
        auto&& sampleSizes = std::make_unique<size_t[]>(sampleCount);
        auto data = malloc(fileSize);
        if (!data) {
            return kVTAllocationFailedErr;
        }
        uint frameOffset = 0, dataOffset = 0;
        for (auto seg : segments) {
            for (auto key : seg->keyFrames) {
                keyFrames.push_back(key + frameOffset - 1);
            }
            std::copy_n(seg->sampleSizes.begin(), seg->sampleSizes.size(), sampleSizes.get() + frameOffset);
            auto size = seg->fileSize;
            auto readSize = seg->read(((char *)data) + dataOffset, size, 0);
            assert(readSize == size);
            frameOffset += seg->sampleSizes.size();
            dataOffset += size;
        }
        
        if (copyLastCount > 0) {
            void * src = ((char *)data) + dataOffset - lastFrameSize;
            for(int i = 0; i < copyLastCount ; ++i) {
                memcpy(((char *)data) + dataOffset, src, lastFrameSize);
                dataOffset += lastFrameSize;
                sampleSizes[sampleCount - copyLastCount + i] = lastFrameSize;
            }
            if (isLastKeyFrame) {
                auto lastKeyFrame = keyFrames.back();
                for(int i = 1; i <= copyLastCount ; ++i) {
                    keyFrames.push_back(lastKeyFrame + i);
                }
            }
        }
        
        CFObject<CMBlockBufferRef> blockBuffer;
        CheckStatusAndReturn(CMBlockBufferCreateWithMemoryBlock(NULL, data, fileSize, kCFAllocatorMalloc, NULL, 0, fileSize, 0, blockBuffer.out()));
        CMSampleTimingInfo timeInfoArray[1] = { {
            .duration = CMTimeMake(1, frameRate),
            .presentationTimeStamp = kCMTimeZero,
            .decodeTimeStamp = kCMTimeInvalid,
        } };
        //core media will crash without timeinfo;
        CheckStatusAndReturn(CMSampleBufferCreate(NULL, blockBuffer, true, NULL, NULL, videoFormat, sampleCount, 1, timeInfoArray, sampleCount, sampleSizes.get(), outRef));
        
        CFArrayRef attachmentArray = CMSampleBufferGetSampleAttachmentsArray(*outRef, true);
        
        for (auto frame : keyFrames) {
            assert(frame < sampleCount);
            CFMutableDictionaryRef dictionary = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachmentArray, frame);
            CFDictionarySetValue(dictionary, kCMSampleAttachmentKey_NotSync, kCFBooleanFalse);
        }
        for (uint i = sampleCount; i--; ) {
            CFMutableDictionaryRef dictionary = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachmentArray, i);
            if (!CFDictionaryContainsKey(dictionary, kCMSampleAttachmentKey_NotSync)) {
                CFDictionarySetValue(dictionary, kCMSampleAttachmentKey_NotSync, kCFBooleanTrue);
            }
        }
        
        return 0;
    }

    int decodeSample(CMTime atTime, std::function<void(OSStatus status, CVPixelBufferRef image)> callback) override {
        fixTime(atTime);
        if(!reader && videoFormat) {
            createReader();
        }
        MovSeg *seg = findMovSeg(atTime);
        if (!seg) {
            return kVTFrameSiloInvalidTimeStampErr;
        }
        
        segLock.lock();
        CMTime segTime = CMTimeSubtract(atTime, seg->start);
        int sampleNum  = (int)(segTime.value * frameRate / segTime.timescale);
        assert(sampleNum < seg->sampleSizes.size());
        int targetSampleNum = sampleNum;
        int keyFrame = seg->keyFrameForSample(targetSampleNum);
        if (keyFrame < 0) {
            return kVTParameterErr;
        }
        if (sampleNum != lastDecodeSample + 1) {
            if (keyFrame == lastDecodeKeyFrame && sampleNum > lastDecodeSample) {
                targetSampleNum = lastDecodeSample + 1;
            } else {
                targetSampleNum = keyFrame;
            }
        }
        assert(targetSampleNum <= sampleNum);
        int frameNum = sampleNum - targetSampleNum + 1;
        size_t sizes[frameNum];
        int totalSize = 0;
        int offset  = seg->offsetForSample(targetSampleNum);
        do {
            size_t size = seg->sampleSizes[targetSampleNum];
            int i = frameNum - (sampleNum - targetSampleNum) - 1;
            sizes[i] = size;
            totalSize += size;
        } while (++targetSampleNum <= sampleNum);
        segLock.unlock();
        readerCache.reserve(MAX(maxFrameSize, totalSize));
        auto readSize = seg->read(readerCache.data(), totalSize, offset);
        assert(readSize == totalSize);
        CFObject<CMBlockBufferRef> blockBuffer;
        CheckStatusAndReturn(CMBlockBufferCreateWithMemoryBlock(NULL, readerCache.data(), totalSize, kCFAllocatorNull, NULL, 0, totalSize, 0, blockBuffer.out()));
        CMSampleTimingInfo timeInfoArray[1] = { {
            .duration = CMTimeMake(1, frameRate),
            .presentationTimeStamp = atTime,
            .decodeTimeStamp = kCMTimeInvalid,
        } };
        //core media will crash without timeinfo;
        CFObject<CMSampleBufferRef> sampleBuffer;
        CheckStatusAndReturn(CMSampleBufferCreate(NULL, blockBuffer, true, NULL, NULL, videoFormat, frameNum, 1, timeInfoArray, frameNum, sizes, sampleBuffer.out()));
        
        //setSampleAttachment(sampleBuffer, keyFrame == targetSampleNum);
        __block ReaderFrameRef ref;
        {
            OSStatus error;
            std::lock_guard<std::mutex> sentry(decodeLock);
            auto session = reader.get();
            if (session) {
                error = VTDecompressionSessionDecodeFrameWithOutputHandler(session, sampleBuffer, 0, nullptr, ^(OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef  _Nullable imageBuffer, CMTime presentationTimeStamp, CMTime presentationDuration) {
                        ref.lastDecodedImage = imageBuffer;
                        ref.lastDecodeError  = status;
                });
            } else {
                return kVTInvalidSessionErr;
            }
            error = error ?: ref.lastDecodeError;
            if (!ref.lastDecodedImage && !error) {
                error = kVTVideoDecoderBadDataErr;
            }
            if (error) {
                lastDecodeSample = -1;
                reader = nullptr;
                return error;
            }
        }
        lastDecodeSample = sampleNum;
        lastDecodeKeyFrame = keyFrame;
        
        callback(0, ref.lastDecodedImage);
        return 0;
    }

    void cancelReading() override {
        std::lock_guard<std::mutex> sentry(decodeLock);
        reader = nullptr;
        lastDecodeSample = -1;
    }

    void cancelWriting() override {
        std::lock_guard<std::mutex> sentry(encodeLock);
        writer = nullptr;
        writerCallback = nullptr;
    }
public:
   static std::shared_ptr<IMovFile> create(int frameRate, int timeScale, int width, int height, EncodeQuality quality, const char *outputPath, int maxKeyFrameInterval, bool lazyWriter) {
       auto&& ret = std::shared_ptr<MovFile>((MovFile *)new MovFile(frameRate, timeScale, width, height, quality, outputPath, maxKeyFrameInterval));
       if (!lazyWriter) {
           ret->createWriter();
       } else {
           ret->lazyWriter = true;
       }
       return std::shared_ptr<IMovFile>(ret);
    }
};

std::shared_ptr<IMovFile> IMovFile::create(int frameRate, int timeScale, int width, int height, EncodeQuality quality, const char *outputPath, int maxKeyFrameInterval, bool lazyWriter) {
    auto&& ret = MovFile::create(frameRate, timeScale, width, height, quality, outputPath, maxKeyFrameInterval, lazyWriter);
    return std::move(ret);
}

}
