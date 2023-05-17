//
//  TSVMovFormat.h
//  cmd
//
//  Created by Osl on 2020/2/15.
//  Copyright © 2020 Osl. All rights reserved.
//

#ifndef IVTMovFormat_h
#define IVTMovFormat_h

#ifdef __cplusplus

#include "IVTMovDataType.h"
namespace IVT {
#define IdentityMatrix \
{ 1, 0, 0, 0, 1, 0, 0, 0, 1 }

#define DEF_WRITE uint8_t *writeTo(uint8_t *addr)

#define DEF_SIMPLE_WRITE                               \
    uint8_t *writeTo(uint8_t *addr) {                  \
        return addr + copy<sizeof(*this)>(addr, this); \
    }

template <size_t v>
struct _not_neg {
    static_assert(v >= 0, "value must not be negative");
    static constexpr const size_t value = v;
};

#define sizeofrange(f1, f2) _not_neg<(offsetof(std::remove_reference<decltype(*this)>::type, f2) - offsetof(std::remove_reference<decltype(*this)>::type, f1) + sizeof(f2))>::value

struct PACKED() Atom {
    buint32_t size;
    union {
        uint type;
        char charType[4];
    };
    Atom() {}
    Atom(const char *_type): type(*(uint *)_type) {
    }
    Atom(uint32_t _size, const char *_type)
        : type(*(uint *)_type), size(_size) {
    }
    DEF_SIMPLE_WRITE
};
struct PACKED() FileTypeAtom : Atom {
    char majorBrand[4];
    buint32_t minorVersion = 1;
    char compatibleBrand[4];
    char compatibleBrand1[4];
    char compatibleBrand2[4];
    FileTypeAtom()
        : Atom(sizeof(*this), "ftyp") {
        copystr(majorBrand, "mp42");
        copystr(compatibleBrand, "isom");
        copystr(compatibleBrand1, "mp41");
        copystr(compatibleBrand2, "mp42");
    }

    DEF_SIMPLE_WRITE
};

struct WideAtom : Atom {
    WideAtom()
        : Atom(sizeof(*this), "wide") {}
};

struct PACKED() MediaDataAtom : Atom {
    buint64_t size64; // optional
    //data is appended;
    MediaDataAtom()
        : Atom("mdat") {}
    
    int32_t headerSize() {
        return size == 1 ? sizeof(*this) : sizeof(Atom);
    }
    
    void setSizeWithDataSize(uint64_t size, bool prefer64) {
        if (size > UINT32_MAX || prefer64) {
            this->size = 1;
            size64 = size + sizeof(*this);
        } else {
            this->size = size + sizeof(Atom);
        }
    }
    
    uint8_t *writeTo(uint8_t *addr) {
        if (size == 1) {
            return addr + copy<sizeof(*this)>(addr, this);
        } else {
            return addr + copy<sizeof(Atom)>(addr, this);
        }
        
    }
};

struct VersionAndFlag {
    uint8_t version = 0;
    uint8_t flags[3] = {};
};

struct PACKED() FullAtom : Atom {
    VersionAndFlag vf;
    using Atom::Atom;
    DEF_SIMPLE_WRITE
};

struct PACKED() MovHeaderAtom : FullAtom {
    buint64_t createTime PACKED(); // 32 bit on version 0, 64 bit on version 1
    buint64_t modTime PACKED();
    buint32_t timeScale;
    buint64_t duration PACKED();
    struct PACKED() {
        bff32 preferredRate       = 1;
        bff16 preferredVolume      = 0;
        char reserved[10]         = {};
        Matrix preferredTransfrom = IdentityMatrix;
        int reserved1[6]          = {}; //Preview time,Preview duration,Poster time,Selection time,Selection duration,Current time,
        bint nextTrackID          = 2;
    } others;

    MovHeaderAtom(uint64_t createTime, uint64_t modTime, uint32_t timeScale, uint64_t duration)
        : FullAtom("mvhd")
        , createTime(createTime)
        , modTime(modTime)
        , timeScale(timeScale)
        , duration(duration) {
        vf.version = this->createTime > UINT32_MAX || this->modTime > UINT32_MAX || duration > UINT32_MAX;
        size       = sizeof(MovHeaderAtom) - (vf.version ? 0 : 12);
    }

    DEF_WRITE {
        addr = FullAtom::writeTo(addr);
        if (vf.version) {
            addr += copy<sizeofrange(createTime, others)>(addr, &createTime);
        } else {
            addr += copy<4>(addr, &(buint32_t &)createTime);
            addr += copy<4>(addr, &(buint32_t &)modTime);
            addr += copy<4>(addr, &timeScale);
            addr += copy<4>(addr, &(buint32_t &)duration);
            addr += copy<sizeof(others)>(addr, &others);
        }
        return addr;
    }
};

struct PACKED() TrackHeaderAtom : FullAtom {
    buint64_t createTime PACKED(); // 32 bit on version 0, 64 bit on version 1
    buint64_t modTime PACKED();
    bint trackID = 1;
    int reseverd;
    buint64_t duration PACKED();
    struct PACKED() {
        uint64_t reserved1;
        bint16_t layer;
        bint16_t alternativeGroup;
        bff16 volume = 1;
        int16_t reserved2;
        Matrix preferredTransfrom = IdentityMatrix;
        bff32 width;
        bff32 height;
    } others;

    TrackHeaderAtom(time_t createTime, time_t modTime, uint64_t duration, uint32_t width, uint32_t height)
        : FullAtom("tkhd")
        , createTime(createTime)
        , modTime(modTime)
        , duration(duration)
        , others({ .width = width, .height = height }) {
        vf.version = createTime > UINT32_MAX || modTime > UINT32_MAX || duration > UINT32_MAX;
        enum : uint8_t {
            IN_POSTER  = 8,
            IN_PREVIEW = 4,
            IN_MOVIE   = 2,
            ENABLED    = 1
        };
        vf.flags[2] = /*IN_POSTER | IN_PREVIEW | IN_MOVIE |*/ ENABLED;
        size        = sizeof(TrackHeaderAtom) - (vf.version ? 0 : 12);
    }

    DEF_WRITE {
        addr = FullAtom::writeTo(addr);
        if (vf.version) {
            addr += copy<sizeofrange(createTime, others)>(addr, &createTime);
        } else {
            addr += copy<4>(addr, &(bint32_t &)createTime);
            addr += copy<4>(addr, &(bint32_t &)modTime);
            addr += copy<4>(addr, &trackID);
            addr += 4;
            addr += copy<4>(addr, &(bint32_t &)duration);
            addr += copy<sizeof(others)>(addr, &others);
        }
        return addr;
    }
};

struct EditListAtom : FullAtom {
    static constexpr int curEntries = 1;
    const bint numberOfEntries      = curEntries;
    struct PACKED() {
        buint64_t duration PACKED();
        buint64_t mediaStart PACKED();
        bff32 rate = 1.0;
    } listTable[curEntries];

    EditListAtom(uint64_t duration)
        : FullAtom("elst") {
        listTable[0].duration = duration;
        vf.version            = duration > UINT32_MAX;
        size                  = sizeof(EditListAtom) - (vf.version ? 0 : 8);
    }

    DEF_WRITE {
        addr = FullAtom::writeTo(addr);
        addr += copy<4>(addr, &numberOfEntries);
        if (vf.version) {
            addr += copy<sizeof(listTable)>(addr, &listTable);
        } else {
            addr += copy<4>(addr, &(bint32_t &)listTable[0].duration);
            addr += copy<4>(addr, &(bint32_t &)listTable[0].mediaStart);
            addr += copy<4>(addr, &listTable[0].rate);
        }
        return addr;
    }
};

struct EditAtom : Atom {
    EditListAtom editList;
    EditAtom(uint64_t duration)
        : Atom("edts")
        , editList(duration) {
        size = sizeof(Atom) + editList.size;
    }

    DEF_WRITE {
        addr = Atom::writeTo(addr);
        addr = editList.writeTo(addr);
        return addr;
    }
};

struct PACKED() MediaHeaderAtom : FullAtom {
    buint64_t createTime; // 32 bit on version 0, 64 bit on version 1
    buint64_t modTime;
    buint32_t timescale;
    buint64_t duration;
    bint16_t languageCode = 0x55C4;
    bint16_t quality;

    MediaHeaderAtom(uint64_t createTime, uint64_t modTime, uint32_t timescale, int64_t duration)
        : FullAtom("mdhd")
        , createTime(createTime)
        , modTime(modTime)
        , timescale(timescale)
        , duration(duration) {
        vf.version = createTime > UINT32_MAX || modTime > UINT32_MAX || duration > UINT32_MAX;
        size       = sizeof(MediaHeaderAtom) - (vf.version ? 0 : 12);
    }

    DEF_WRITE {
        addr = FullAtom::writeTo(addr);
        if (vf.version) {
            addr += copy<sizeofrange(createTime, quality)>(addr, &createTime);
        } else {
            addr += copy<4>(addr, &(bint32_t &)createTime);
            addr += copy<4>(addr, &(bint32_t &)modTime);
            addr += copy<4>(addr, &timescale);
            addr += copy<4>(addr, &(bint32_t &)duration);
            addr += copy<sizeofrange(languageCode, quality)>(addr, &languageCode);
        }
        return addr;
    }
};

using namespace std::string_view_literals;
struct PACKED() HandlerReferrenceAtom : FullAtom {
    char componentType[4] = {};
    char componentSubType[4];
    bint componentManufacturer;
    bint componentFlags;
    bint componentFlagsMask;
#define coreMediaVideo "Core Media Video"
    static constexpr uint8_t NAME_LENGTH = sizeof(coreMediaVideo);
    //uint8_t nameLength                   = NAME_LENGTH;
    const char *componentName            = coreMediaVideo;

    HandlerReferrenceAtom()
        : FullAtom("hdlr") {
        //copystr(componentType, "mdlr");
        copystr(componentSubType, "vide");
        size = sizeof(FullAtom) + sizeofrange(componentType, componentFlagsMask) + NAME_LENGTH;
    }

    DEF_WRITE {
        addr = FullAtom::writeTo(addr);
        addr += copy<sizeofrange(componentType, componentFlagsMask)>(addr, &componentType);
        addr += copy<NAME_LENGTH>(addr, componentName);
        return addr;
    }
};

struct VideoMediaInfoHeaderAtom : FullAtom {
    buint16_t graphicsMode; //= 0x40;
    uint16_t opqueRed      =0;//= 0x80;
    uint16_t opqueGreen    =0;//= 0x80;
    uint16_t opqueBlue     =0;//= 0x80;
    VideoMediaInfoHeaderAtom()
        : FullAtom(sizeof(VideoMediaInfoHeaderAtom), "vmhd") {
        enum {
            NO_LEAN_AHEAD = 1,
        };
        vf.flags[2] |= NO_LEAN_AHEAD;
    }
    DEF_WRITE {
        addr = FullAtom::writeTo(addr);
        addr += copy<sizeofrange(graphicsMode, opqueBlue)>(addr, &graphicsMode);
        return addr;
    }
};

struct DataRefAtom : FullAtom {
    bint entryCount = 1;
    struct RefAtom : FullAtom {
        RefAtom()
            : FullAtom(sizeof(FullAtom), "url ") {
            vf.flags[2] = 0x1;
        }
    } refs[1];
    DataRefAtom()
        : FullAtom(sizeof(DataRefAtom), "dref") {}

    DEF_WRITE {
        addr = FullAtom::writeTo(addr);
        addr += copy<sizeofrange(entryCount, refs)>(addr, &entryCount);
        return addr;
    }
};

struct DataInfoAtom : Atom {
    DataRefAtom dataRef;
    DataInfoAtom()
        : Atom(sizeof(DataInfoAtom), "dinf") {}
    DEF_WRITE {
        addr = Atom::writeTo(addr);
        addr = dataRef.writeTo(addr);
        return addr;
    }
};

struct PACKED() VideoSampleDescription {
    buint16_t version;
    buint16_t revisionLevel;
    buint32_t vendor;
    buint32_t temporalQuality;
    buint32_t spatialQuality;
    bint16_t width;
    bint16_t height;
    bff32 horizontalResolution = 0x48;
    bff32 verticalResolution = 0x48;
    buint32_t dataSize;
    buint16_t frameCount = 1;
    uint8_t nameLength = 0;
    char compressorName[31] = {};
    buint16_t pixelDepth   = 24;
    buint16_t colorTableID = -1;
    VideoSampleDescription() {
        //nameLength = 5;
        //copy<5>(compressorName, "H.264");
    }
};

#define DEF_CALC_SIZE(exp)  \
    size_t calcSize() {     \
        auto _size = exp;   \
        size       = _size; \
        return _size;       \
    }

#if defined(DEBUG)
#define safewrite(f) ({ \
auto base = addr;  addr = f.writeTo(addr); assert(addr - base == (uint)f.size);\
})
#else
#define safewrite(f) addr = f.writeTo(addr)
#endif

struct PACKED() AVCCDesciption : Atom {
    uint8_t configurationVersion = 1;
    uint8_t AVCProfileIndication = 0;
    uint8_t profile_compatibility = 0;
    uint8_t AVCLevelIndication = 0;
    uint8_t lengthSizeMinusOne : 2;         //ob11 sizeof(NALUnitLength(should be bint)) -1
    uint8_t reserved : 6;                   //0b111111
    uint8_t numOfSequenceParameterSets : 5; //should be 1;
    uint8_t reserved1 : 3;                  //0b111
    bint16_t sequenceParameterSetLength;
    std::unique_ptr<uint8_t[]> sps;
    uint8_t numOfPictureParameterSets = 1; //should be 1;
    bint16_t pictureParameterSetLength;
    std::unique_ptr<uint8_t[]> pps;

    //some extra bytes are specified for some profiles, ignore it;

    AVCCDesciption()
        : Atom("avcC")
        , reserved(0b111111)
        , lengthSizeMinusOne(0b11)
        , reserved1(0b111)
        , numOfSequenceParameterSets(0b1) {
    }

    void fillIn(size_t spsLength, const uint8_t *_sps, size_t ppsLength, const uint8_t *_pps) {
        sequenceParameterSetLength = spsLength;
        pictureParameterSetLength  = ppsLength;
        sps                        = std::make_unique<uint8_t[]>(spsLength);
        copy<sizeofrange(AVCProfileIndication, AVCLevelIndication)>(&AVCProfileIndication, _sps + 1);
        assert(AVCProfileIndication && AVCLevelIndication);
        pps = std::make_unique<uint8_t[]>(ppsLength);
        std::copy_n(_sps, spsLength, sps.get());
        std::copy_n(_pps, ppsLength, pps.get());
    }

    DEF_CALC_SIZE(sizeof(*this) - sizeof(uintptr_t) * 2 + sequenceParameterSetLength + pictureParameterSetLength);

    DEF_WRITE {
        addr += copy<sizeofrange(size, sequenceParameterSetLength)>(addr, &size);
        memcpy(addr, sps.get(), sequenceParameterSetLength);
        addr += sequenceParameterSetLength;
        addr += copy<sizeofrange(numOfPictureParameterSets, pictureParameterSetLength)>(addr, &numOfPictureParameterSets);
        memcpy(addr, pps.get(), pictureParameterSetLength);
        addr += pictureParameterSetLength;
        return addr;
    }
};

struct PixelAspectRatioAtom : Atom {
    bint32_t hSpacing = 1;
    bint32_t vSpacing = 1;
    PixelAspectRatioAtom():Atom(sizeof(*this),"pasp"){}
};

struct VideoExtensionAtom : Atom {
    uint32_t dataLength;
    const void * atomData;
    VideoExtensionAtom():Atom() {};
    
    DEF_CALC_SIZE(sizeof(Atom) + dataLength);
    DEF_WRITE {
        addr = Atom::writeTo(addr);
        memcpy(addr, atomData, dataLength);
        return addr + dataLength;
    }
};

struct PACKED() SampleDescriptionAtom : FullAtom {
    buint32_t entryCount = 1;
    struct PACKED() Datum : Atom {
        char reserved[6] = {};
        buint16_t dataRef = 1;
        VideoSampleDescription videoDecription; //the below is video specialized;
        VideoExtensionAtom videoExtionsion;
        PixelAspectRatioAtom pasp;
        Datum()
            : Atom() {}

        DEF_CALC_SIZE(sizeof(*this) - sizeof(VideoExtensionAtom) + videoExtionsion.calcSize());

        DEF_WRITE {
            addr += copy<sizeofrange(size, videoDecription)>(addr, &size);
            addr = videoExtionsion.writeTo(addr);
            addr += copy<sizeof(PixelAspectRatioAtom)>(addr, &pasp);
            return addr;
        }
        
        void fillIn(buint& mediaSubType, VideoExtensionAtom extAtom, const char * formatName, int hspacing, int vSpacing) {
            type = mediaSubType;
            videoExtionsion = extAtom;
            if (formatName) {
                videoDecription.nameLength = strlen(formatName);
                memcpy(videoDecription.compressorName, formatName, videoDecription.nameLength);
            }
            if (hspacing && vSpacing) {
                pasp.hSpacing = hspacing;
                pasp.vSpacing = vSpacing;
            }
        }

    } data[1];

    SampleDescriptionAtom(uint32_t width, uint32_t height)
        : FullAtom("stsd") {
        data[0].videoDecription.width  = width;
        data[0].videoDecription.height = height;
    }

    DEF_CALC_SIZE(sizeof(FullAtom) + 4 + data[0].calcSize());

    DEF_WRITE {
        addr += copy<sizeofrange(size, entryCount)>(addr, &size);
        addr = data[0].writeTo(addr);
        return addr;
    }
};

struct PACKED() SampleToTimeAtom : FullAtom {
    bint entryCount = 1;
    struct {
        bint sampleCount;    // need set
        bint sampleDuration; // need set
    } entries[1];
    SampleToTimeAtom()
        : FullAtom(sizeof(SampleToTimeAtom), "stts") {}

    DEF_SIMPLE_WRITE
};

template <class T = buint>
struct PACKED() MovArray {
    bint entryCount;
    std::unique_ptr<T[]> entries PACKED();

    MovArray() {}

    template <class K>
    MovArray(std::vector<K> list) {
        entries    = std::move(std::make_unique<T[]>(list.size()));
        entryCount = list.size();
        std::copy_n(list.begin(), list.size(), entries.get());
    }

    size_t size() {
        return 4 + entryCount * sizeof(T);
    }

    DEF_WRITE {
        addr += copy<4>(addr, &entryCount);
        size_t dataSize = entryCount * sizeof(T);
        memcpy(addr, entries.get(), dataSize);
        addr += dataSize;
        return addr;
    }
};

struct PACKED() SyncSampleAtom : FullAtom {
    MovArray<> samples;

    SyncSampleAtom()
        : FullAtom("stss") {
    }

    DEF_CALC_SIZE(sizeof(FullAtom) + samples.size())

    DEF_WRITE {
        addr = FullAtom::writeTo(addr);
        addr = samples.writeTo(addr);
        return addr;
    }
};

struct PACKED() SampleSizeAtom : FullAtom {
    buint sampleSize; // keep zero
    MovArray<> sampleSizes;
    SampleSizeAtom()
        : FullAtom("stsz") {}

    DEF_CALC_SIZE(sizeof(FullAtom) + 4 + sampleSizes.size())

    DEF_WRITE {
        addr = FullAtom::writeTo(addr);
        addr += copy<4>(addr, &sampleSize);
        addr = sampleSizes.writeTo(addr);
        return addr;
    }
};

struct PACKED() SampleToChunkAtom : FullAtom {
    struct SampleToChunkEntry {
        bint firstChunk;
        bint smaplePerChunck;
        bint sampleDescription = 1;
    };
    MovArray<SampleToChunkEntry> sizes;
    SampleToChunkAtom()
        : FullAtom("stsc") {}

    DEF_CALC_SIZE(sizeof(FullAtom) + sizes.size())

    DEF_WRITE {
        addr = FullAtom::writeTo(addr);
        addr = sizes.writeTo(addr);
        return addr;
    }
};

struct PACKED() ChunkOffsetAtom : FullAtom {
    MovArray<> offsets;
    ChunkOffsetAtom()
        : FullAtom("stco") {}

    DEF_CALC_SIZE(sizeof(FullAtom) + offsets.size())

    DEF_WRITE {
        addr = FullAtom::writeTo(addr);
        addr = offsets.writeTo(addr);
        return addr;
    }
    
    void updateOffset(int offset) {
        int count = offsets.entryCount;
        auto&& array = offsets.entries;
        for (int i = count; i--; ) {
            auto addr = array.get() + i;
            *addr = *addr + offset;
        }
    }
};

struct SampleTableAtom : Atom {
    SampleDescriptionAtom description;
    SampleToTimeAtom timeInfo; // no b frame;
    SyncSampleAtom syncSamples;
    SampleToChunkAtom sampleToChunk;
    SampleSizeAtom sizeAtom;
    ChunkOffsetAtom chunkOffsetAtom;

    SampleTableAtom(uint32_t width, uint32_t height)
        : Atom("stbl")
        , description(width, height) {}

    DEF_CALC_SIZE(sizeof(Atom) + description.calcSize() + timeInfo.size + syncSamples.calcSize()  + sampleToChunk.calcSize()+ sizeAtom.calcSize() + chunkOffsetAtom.calcSize())

    void handleInfo(MovArray<> &&sampleSizes,
                    MovArray<> &&chunkOffsets,
                    MovArray<SampleToChunkAtom::SampleToChunkEntry> &&chunkSizes,
                    MovArray<> &&keyFrames) {
        timeInfo.entries[0].sampleCount = sampleSizes.entryCount;
        sizeAtom.sampleSizes            = std::move(sampleSizes);
        chunkOffsetAtom.offsets         = std::move(chunkOffsets);
        sampleToChunk.sizes             = std::move(chunkSizes);
        syncSamples.samples             = std::move(keyFrames);
    }

    DEF_WRITE {
        addr = Atom::writeTo(addr);
        safewrite(description);
        safewrite(timeInfo);
        safewrite(syncSamples);
        safewrite(sampleToChunk);
        safewrite(sizeAtom);
        safewrite(chunkOffsetAtom);
        return addr;
    }
};

struct MediaInfoAtom : Atom {
    VideoMediaInfoHeaderAtom videoHeader;
    DataInfoAtom dataInfo;
    SampleTableAtom sampleTable;

    MediaInfoAtom(uint32_t width, uint32_t height)
        : Atom("minf")
        , sampleTable(width, height) {}

    DEF_CALC_SIZE(sizeof(Atom) + videoHeader.size + dataInfo.size + sampleTable.calcSize())

    DEF_WRITE {
        addr = Atom::writeTo(addr);
        safewrite(videoHeader);
        safewrite(dataInfo);
        safewrite(sampleTable);
        return addr;
    }
};

struct MediaAtom : Atom {
    MediaHeaderAtom header;
    HandlerReferrenceAtom handler;
    MediaInfoAtom mediaInfo;

    MediaAtom(uint64_t createTime, uint64_t modTime, uint32_t timescale, int64_t duration, uint32_t width, uint32_t height)
        : Atom("mdia")
        , header(createTime, modTime, timescale, duration)
        , mediaInfo(width, height) {}

    DEF_CALC_SIZE(sizeof(Atom) + header.size + handler.size + mediaInfo.calcSize())

    DEF_WRITE {
        addr = Atom::writeTo(addr);
        safewrite(header);
        safewrite(handler);
        safewrite(mediaInfo);
        return addr;
    }
};

struct TrackAtom : Atom {
    TrackHeaderAtom header;
    EditAtom edits;
    MediaAtom media;

    TrackAtom(uint64_t createTime, uint64_t modTime, uint32_t timescale, int64_t duration, uint32_t width, uint32_t height)
        : Atom("trak")
        , header(createTime, modTime, duration, width, height)
        , edits(duration)
        , media(createTime, modTime, timescale, duration, width, height) {}

    DEF_CALC_SIZE(sizeof(Atom) + header.size + edits.size + media.calcSize())

    DEF_WRITE {
        addr = Atom::writeTo(addr);
        safewrite(header);
        safewrite(edits);
        safewrite(media);
        return addr;
    }
};

struct MovieAtom : Atom {
    MovHeaderAtom header;
    TrackAtom videoTrack;

    MovieAtom(uint64_t createTime, uint64_t modTime, uint32_t timescale, uint32_t frameRate, int64_t duration, uint32_t width, uint32_t height)
        : Atom("moov")
        , header(createTime, modTime, timescale, duration)
        , videoTrack(createTime, modTime, timescale, duration, width, height) {
        videoTrack.media.mediaInfo.sampleTable.timeInfo.entries[0].sampleDuration = timescale / frameRate;
    }

    DEF_CALC_SIZE(sizeof(Atom) + header.size + videoTrack.calcSize());

    DEF_WRITE {
        addr = Atom::writeTo(addr);
        safewrite(header);
        safewrite(videoTrack);
        return addr;
    }
};
}
#endif
#endif /* IVTMovFormat_h */
