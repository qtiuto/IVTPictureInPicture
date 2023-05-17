//
//  MovieFileBuilder.h
//  TTVideoBusiness
//
//  Created by 吴桂兴 on 2021/1/18.
//

#import <Foundation/Foundation.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <objc/runtime.h>
#include <time.h>
#include <mach/mach_time.h>
#include <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>

enum EncodeQuality {
    BaseQuality,
    MainQuality,
    HighQuality
};

//视频帧
@interface IVTPixelBuffer : NSObject
@property (nonatomic, assign, direct) CVPixelBufferRef buffer;//buffer
@property (nonatomic, assign, direct) CMSampleBufferRef sampleBuffer;// optional
@end

@interface IVTMovieModel : NSObject
@property (nonatomic, assign) int frameRate;//必需
@property (nonatomic, assign) NSTimeInterval duration;//必需,视频总长,设置0为直播模式
@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;
@property (nonatomic, copy) NSArray<IVTPixelBuffer *> *pixelBuffers;//必需
@property (nonatomic, strong) NSString *outputPath;//必需
@property (nonatomic, assign) enum EncodeQuality quality;//默认为 HighQuality
@property (nonatomic, assign) int maxKeyFrameInterval;//默认为 20
@property (nonatomic, assign) int copyLastFrameCount;//追加lastKeyFrame的copy帧,默认为 0
@property (nonatomic, assign) BOOL isFillLast;//是否自动设置copyLastFrameCount以追加满尾部帧,默认为 NO
@end

@interface IVTMovieFileBuilder : NSObject
@property (nonatomic, readonly, strong) IVTMovieModel *movieModel;
- (instancetype)initWithMovieModel:(IVTMovieModel *)movieModel;
- (void)movieFileBuild:(void (^)(NSError *err))completion;
@end

@interface IVTMovieSampleCacheCenter : NSObject
@property (nonatomic) BOOL cacheFileToDisk;
+ (NSArray<IVTPixelBuffer *> *)createSamplesForSize:(CGSize)size;
+ (void)cacheAsset:(AVAsset *)asset size:(CGSize)size;

@end
