//
//  IVTMovFile.hpp
//  IESVideoEditorDemo
//
//  Created by Osl on 2020/1/31.
//  Copyright © 2020 Gavin. All rights reserved.
//

#ifndef IVTMovFile_hpp
#define IVTMovFile_hpp

#ifdef __cplusplus

#include "IVTCFObject.h"
#include <VideoToolbox/VideoToolbox.h>
#include <atomic>
#include <stdio.h>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#ifdef DEBUG
#define DLOG(format, ...) NSLog(@"osl " format, ##__VA_ARGS__)
#else
#define DLOG(format, ...)
#endif

namespace IVT {

class IMovFile {
protected:
    IMovFile(int frameRate, int timeScale, int width, int height,
             const char *outputPath, int maxKeyFrameInterval)
    : frameRate(frameRate), timeScale(timeScale), width(width),
    height(height), outputPath(outputPath), maxKeyFrameInterval(maxKeyFrameInterval) {}
    
public:
    enum FinishWay {
        BY_CUSTOM,
        BY_SYSTEM
    };
    enum EncodeQuality {
        BaseQuality,
        MainQuality,
        HighQuality
    };
    
    struct FinishConfig {
        FinishWay way = BY_CUSTOM;
        uint copyLastFrameCount = 0;
        uint samplePerChunk = 0;
    };
    
    const int frameRate;
    const int timeScale;
    const int width;
    const int height;
    const int maxKeyFrameInterval;
    const std::string outputPath;
    bool autoCreateReaderOnWriting = false;
    bool cacheFileToMemory = false;
    FinishConfig finishConfig;
    CMTime lastEncodedFrameTime = kCMTimeInvalid;
    static std::shared_ptr<IMovFile>
    create(int frameRate, int timeScale, int width, int height, EncodeQuality quality, const char *outputPath, int maxKeyFrameInterval = 5, bool lazyWriter = false);
    virtual int encodeSample(CMSampleBufferRef buffer) = 0;
    virtual int encodeFrame(CVPixelBufferRef buffer, CMTime frameTime) = 0;
    virtual int
    decodeSample(CMTime atTime, std::function<void(OSStatus status, CVPixelBufferRef image)>
                 callback) = 0;
    
    virtual void finishWriting(std::function<void(NSError *err)> completion) = 0;
    
    virtual void cancelWriting() = 0;
    virtual void cancelReading() = 0;
    virtual ~IMovFile(){};
};

} // namespace TSV
#endif
#endif /* IVTMovFile_hpp */
