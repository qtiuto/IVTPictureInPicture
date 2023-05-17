//
//  MovieFileBuilder.mm
//  TTVideoBusiness
//
//  Created by 吴桂兴 on 2021/1/18.
//

#import "IVTMovieFileBuilder.h"
#include "IVTMovFile.h"
#include <array>
#include <mutex>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include "IVTMovFormat.h"

static bool sCacheToDisk = YES;

namespace IVTMV {
template <typename F>
struct FinalAction {
    FinalAction(F f) : clean_{f} {}
   ~FinalAction() {clean_(); }
  private:
    F clean_;
};
}

template <typename F>
IVTMV::FinalAction<F> finally(F f) {
    return IVTMV::FinalAction<F>(f); }

@interface IVTPixelBuffer()

@end

@implementation IVTPixelBuffer

- (void)dealloc
{
    CVPixelBufferRelease(_buffer);
}

@end

@interface IVTMovieModel()

@end

@implementation IVTMovieModel

- (instancetype)init
{
    if (self = [super init]) {
        _quality = HighQuality;
        _maxKeyFrameInterval = 20;
    }
    return self;
}

@end

static void ensureSampleBufferCache();

@interface IVTMovieFileBuilder()
@property (nonatomic, strong) IVTMovieModel *movieModel;
@property (nonatomic, assign) NSInteger totalFrameCount;
@end

@implementation IVTMovieFileBuilder

- (instancetype)initWithMovieModel:(IVTMovieModel *)movieModel {
    if (self = [super init]) {
        _movieModel = movieModel;
        _totalFrameCount = ceil(movieModel.frameRate * movieModel.duration);
    }
    return self;
}

- (void)movieFileBuild:(void (^)(NSError * _Nonnull))completion {
    if (self.totalFrameCount == 0 || !self.movieModel.outputPath) {
        completion([NSError errorWithDomain:@"required argument missed" code:0 userInfo:nil]);
        return ;
    }
    ensureSampleBufferCache();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        const char *outputPath = [self.movieModel.outputPath UTF8String];
        auto frameRate = self.movieModel.frameRate;
        auto width = self.movieModel.width;
        auto height = self.movieModel.height;
        auto&& file = IVT::IMovFile::create(self.movieModel.frameRate, frameRate, width, height, (IVT::IMovFile::EncodeQuality)self.movieModel.quality, outputPath, self.movieModel.maxKeyFrameInterval, true);
        file->cacheFileToMemory = true;
        int maxIndex = 0;
        auto pixelBuffers = self.movieModel.pixelBuffers ?: [IVTMovieSampleCacheCenter createSamplesForSize:CGSizeMake(width, height)];
        for (IVTPixelBuffer *pb in pixelBuffers) {
            if (CVPixelBufferRef buffer = pb.buffer) {
                file->encodeFrame(buffer, CMTimeMake(maxIndex, frameRate));
                ++maxIndex;
            } else if (auto sampleBufferRef = pb.sampleBuffer) {
                auto sampleCount = CMSampleBufferGetNumSamples(sampleBufferRef);
                CMSampleTimingInfo *timeInfo = new CMSampleTimingInfo[sampleCount];
                CMSampleBufferRef sampleCopy = nil;
                auto cleaner = finally([=]{
                    CFBridgingRelease(sampleCopy);
                    delete [] timeInfo;
                });
                for (auto i = 0; i < sampleCount; ++i, ++maxIndex) {
                    timeInfo[i] = CMSampleTimingInfo {
                        .duration = CMTimeMake(1, frameRate),
                        .presentationTimeStamp = CMTimeMake(maxIndex, frameRate),
                        .decodeTimeStamp = kCMTimeInvalid
                    };
                    
                }
                CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault, sampleBufferRef, sampleCount, timeInfo, &sampleCopy);
                file->encodeSample(sampleCopy);
            } else {
            }
        }
        if (self.movieModel.isFillLast) {
            self.movieModel.copyLastFrameCount = (int)self.totalFrameCount - maxIndex - 1;
        }
        file->finishConfig.way = IVT::IMovFile::FinishWay::BY_CUSTOM;
        file->finishConfig.copyLastFrameCount = self.movieModel.copyLastFrameCount;
        file->finishWriting([completion](NSError * error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(error);
            });
        });
    });
   
}

@end

@implementation IVTMovieSampleCacheCenter

- (void)setCacheFileToDisk:(BOOL)cacheFileToDisk {
    sCacheToDisk = cacheFileToDisk;
}

- (BOOL)cacheFileToDisk {
    return sCacheToDisk;
}

struct CGSizeHash {
    size_t operator()(CGSize size) const  {
        return size_t(size.width) + size_t(size.height);
    }
};
struct CGSizeEqual {
    bool operator()(CGSize size1, CGSize size2) const {
        return size1.width == size2.width && size1.height == size2.height;
    }
};

typedef std::unordered_map<CGSize, std::array<CMSampleBufferRef, 2>, CGSizeHash, CGSizeEqual> SampleCacheMap;

static SampleCacheMap* sSampleBufferCache;
static std::mutex sInitLock;


static void ensureSampleBufferCache() {
    if (sSampleBufferCache) {
        return;
    }
    std::scoped_lock guard(sInitLock);
    sSampleBufferCache = new SampleCacheMap;
}

static NSString * cachePipDir() {
    NSString *libDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    NSString *pipDir = [libDir stringByAppendingString:@"/picture_in_picture_cache_file"];
    return pipDir;
}
static NSString * cachePathForSize(CGSize size) {
    NSString *pipDir = cachePipDir();
    NSString *movFilePath = [pipDir stringByAppendingString:
                             [NSString stringWithFormat:@"/pip_%dx%d",
                              (int)size.width, (int)size.height]];
    return movFilePath;
}

static NSArray<IVTPixelBuffer *> * createPixelBuffersForSize(CGSize size) {
    CVPixelBufferRef ref = nil;
    CVPixelBufferCreate(nil, size.width, size.height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &ref);
    IVTPixelBuffer *pixelBuffer = [[IVTPixelBuffer alloc] init];
    pixelBuffer.buffer = ref;
    return @[pixelBuffer, pixelBuffer];
}


+ (NSArray<IVTPixelBuffer *> *)createSamplesForSize:(CGSize)size {
    std::scoped_lock guard(sInitLock);
    auto cache = sSampleBufferCache;
    
    if (!cache) {
        return createPixelBuffersForSize(size);
    }
    auto&& iterator = cache->find(size);
    if (iterator != cache->end()) {
        auto&& buffers = iterator->second;
        if (buffers[0] == nullptr) {
            return createPixelBuffersForSize(size);
        }
        auto createBuffer = [&](int index) {
            IVTPixelBuffer *pixelBuffer = [[IVTPixelBuffer alloc] init];
            pixelBuffer.sampleBuffer = buffers[index];
            return pixelBuffer;
        };
        return @[createBuffer(0), createBuffer(1)];
    }
    if (!sCacheToDisk) {
        return createPixelBuffersForSize(size);
    }
    NSString *path = cachePathForSize(size);
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        cache->try_emplace(size);
        return createPixelBuffersForSize(size);
    }
    
    auto buffers = readSampleBufferFromCache(path, size);
    if (buffers[0] == nullptr) {
        return createPixelBuffersForSize(size);
    }
    cache->try_emplace(size, buffers);
    auto createBuffer = [&](int index) {
        IVTPixelBuffer *pixelBuffer = [[IVTPixelBuffer alloc] init];
        pixelBuffer.sampleBuffer = buffers[index];
        return pixelBuffer;
    };
    return @[createBuffer(0), createBuffer(1)];
}

+ (void)cacheAsset:(AVAsset *)asset size:(CGSize)size {
    if (!asset) {
        return;
    }
    std::scoped_lock guard(sInitLock);
    auto&& current = sSampleBufferCache->find(size);
    if (current != sSampleBufferCache->end() && current->second.at(0) != nullptr) {
        return;
    }
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        auto buffers = readSampleBufferFromAsset(asset);
        if (!buffers[0]) {
            return;
        }
        
        {
            std::scoped_lock guard(sInitLock);
            sSampleBufferCache->insert_or_assign(size, buffers);
        }
        if (!sCacheToDisk) {
            return;
        }
        if (![NSFileManager.defaultManager fileExistsAtPath:cachePipDir()]) {
            [NSFileManager.defaultManager createDirectoryAtPath:cachePipDir() withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSString *path = cachePathForSize(size);
        if ([NSFileManager.defaultManager isReadableFileAtPath:path]) {
            return;
        }

        int bufferLength = 0;
        for (auto sampleBuffer : buffers) {
            CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sampleBuffer);
            bufferLength += CMBlockBufferGetDataLength(block);
        }
        auto format = CMSampleBufferGetFormatDescription(buffers[0]);
        
        NSDictionary * dict = (__bridge NSDictionary *)CMFormatDescriptionGetExtensions(format);
        NSData * formatData = [NSKeyedArchiver archivedDataWithRootObject:dict];
        auto buffer = std::make_unique<char[]>(bufferLength + 16 + formatData.length);
        int writeLength = 0;
        for (auto sampleBuffer : buffers) {
            CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sampleBuffer);
            size_t length = 0;
            char *dataPointer = nullptr;
            OSStatus err =  CMBlockBufferGetDataPointer(block, 0, nullptr, &length, &dataPointer);
            if (!err) {
                std::memcpy(buffer.get() + writeLength, &length, sizeof(length));
                std::memcpy(buffer.get() + writeLength + sizeof(length), dataPointer, length);
                writeLength += length + sizeof(length);
            }
        }
        std::memcpy(buffer.get() + writeLength, formatData.bytes, formatData.length);
        writeLength += formatData.length;
        
        if (writeLength >= bufferLength + 16) {
            [[NSData dataWithBytes:buffer.get() length:writeLength] writeToFile:path atomically:NO];
        }
    });
}

static size_t fileSize(int fd) {
   struct stat s;
   if (fstat(fd, &s) == -1) {
      return (-1);
   }
   return(s.st_size);
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

static CMSampleBufferRef createSample(const char * sourceData, size_t size, CMTime time, CMVideoFormatDescriptionRef videoFormat, bool isSync) {
    CMBlockBufferRef blockBuffer = NULL;
    auto cleaner1 = finally([=] {
        CFBridgingRelease(blockBuffer);
    });
    char *data = (char *)malloc(size);
    memcpy(data, sourceData, size);
    CMBlockBufferCreateWithMemoryBlock(NULL, (void *)data, size, kCFAllocatorMalloc, NULL, 0, size, 0, &blockBuffer);
    CMSampleTimingInfo timeInfoArray[1] = { {
        .duration = CMTimeMake(1, 60),
        .presentationTimeStamp = time,
        .decodeTimeStamp = kCMTimeInvalid,
    } };
    CMSampleBufferRef sample = NULL;
    
    //core media will crash without timeinfo;
    CMSampleBufferCreate(NULL, blockBuffer, true, NULL, NULL, videoFormat, 1, 1, timeInfoArray, 1, &size, &sample);
    
    CFArrayRef attachmentArray = CMSampleBufferGetSampleAttachmentsArray(sample, true);
    
    CFMutableDictionaryRef dictionary = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachmentArray, 0);
    if (!isSync) {
        CFDictionarySetValue(dictionary, kCMSampleAttachmentKey_NotSync, kCFBooleanFalse);
    }
    
    return sample;
}

static std::array<CMSampleBufferRef, 2> readSampleBufferFromCache(NSString * path, CGSize videoSize) {
    std::array<CMSampleBufferRef, 2> result = {nil, nil};
    int fd = open(path.UTF8String,  O_RDONLY);
    auto cleaner = finally([=] {
        close(fd);
    });
    auto size = fileSize(fd);
    if (size == -1 || size < 2 * sizeof(size_t)) {
        return result;
    }
    auto buffer = std::make_unique<char[]>(size);
    if(read(fd, buffer.get(), size) != size) {
        return result;
    }
    size_t firstSize = *reinterpret_cast<size_t *>(buffer.get());
    if (firstSize + 8 > size) {
        return result;
    }
    size_t secSize = *reinterpret_cast<size_t *>(buffer.get() + firstSize + sizeof(size_t));
    if (firstSize + secSize >= size - 2 * sizeof(size_t)) {
        return result;
    }
    if (!validateSampleData(buffer.get() + sizeof(size_t), firstSize)
        || !validateSampleData(buffer.get() + sizeof(size_t) * 2 + firstSize, secSize)) {
        return result;
    }
    
    auto extensions = buffer.get() + sizeof(size_t) * 2 + firstSize + secSize;
    auto extensionsLength = size - (sizeof(size_t) * 2 + firstSize + secSize);
    NSData *data = [NSData dataWithBytes:extensions length:extensionsLength];
    NSDictionary * extensionsDict = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    
    CMVideoFormatDescriptionRef videoFormat = NULL;
    CMVideoFormatDescriptionCreate(NULL,kCMVideoCodecType_H264,videoSize.width,videoSize.height,
                                   (__bridge CFDictionaryRef)extensionsDict, &videoFormat);
    auto cleaner1 = finally([=] {
        CFBridgingRelease(videoFormat);
    });
    
    result[0] = createSample(buffer.get() + sizeof(size_t), firstSize, kCMTimeZero, videoFormat, YES);
    if (result[0]) {
        result[1] = createSample(buffer.get() + sizeof(size_t) * 2 + firstSize, secSize, CMTimeMake(1, 60), videoFormat, NO);
    }
    
    if (CMSampleBufferGetNumSamples(result[1]) < 1) {
        if (result[0]) {
            CFRelease(result[0]);
            result[0] = nullptr;
        }
    }
    
    return result;
}


static std::array<CMSampleBufferRef, 2> readSampleBufferFromAsset(AVAsset * asset) {
    std::array<CMSampleBufferRef, 2> result = {nil, nil};
    NSError *error;
    AVAssetReader * reader = [AVAssetReader assetReaderWithAsset:asset error:&error];
    if (error) {
        return result;
    }
    auto output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:[asset tracksWithMediaType:AVMediaTypeVideo].firstObject outputSettings:nil];
    output.alwaysCopiesSampleData = false;
    [reader addOutput:output];
    [reader startReading];
    auto cleaner = finally([&] {
        [reader cancelReading];
    });
    for (int i = 0; i< 100; ++i) {
        auto buffer = [output copyNextSampleBuffer];
        if (!buffer) {
            continue;
        }
        if (CMSampleBufferGetNumSamples(buffer) > 0) {
            result[0] = buffer;
            break;
        } else {
            CFRelease(buffer);
        }
    }
    if (!result[0]) {
        return result;
    }
    result[1] = [output copyNextSampleBuffer];
    if (!result[1]) {
        CFRelease(result[0]);
        result[0] = nil;
        return result;
    }
    if (CMSampleBufferGetNumSamples(result[1]) == 0) {
        CFRelease(result[0]);
        CFRelease(result[1]);
        result[0] = nil;
        return result;
    }
    return result;
}

@end
