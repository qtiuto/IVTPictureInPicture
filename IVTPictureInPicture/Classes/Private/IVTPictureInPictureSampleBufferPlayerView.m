
#import "IVTPictureInPictureSampleBufferPlayerView.h"
#import <AVKit/AVKit.h>
#import "IVTPictureInPictureInner.h"



@interface IVTPictureInPictureSampleBufferPlayerView ()
@property (nonatomic, readwrite) AVSampleBufferDisplayLayer *layer;
@property (nonatomic) CGSize size;//原始位置
@property (nonatomic) NSTimeInterval duration;//视频时长
@property (nonatomic, weak) AVPictureInPictureController * pipController;
@property (nonatomic) double speed;
@property (nonatomic) NSTimer * endTimer;
@end

@implementation IVTPictureInPictureSampleBufferPlayerView
@synthesize rate = _rate, delegate = _delegate, stalled = _stalled, autoPauseWhenPlayToEndTime = _autoPauseWhenPlayToEndTime, layer = _layer;

- (instancetype)initWithSize:(CGSize)sourceSize duration:(NSTimeInterval)duration {
    if (self = [super init]) {
        _size = IVTPIPCompressSize(sourceSize);
        _layer = [AVSampleBufferDisplayLayer new];
        _duration = duration;
        _speed = 1;
        _rate = 1;
    }
    return self;
}



- (void)dealloc {
    [_endTimer invalidate];
}

- (void)invalidatePlayback {
    if (![NSThread isMainThread]) {
        return;
    }
    if (@available(iOS 15.0, *)) {
        [_pipController invalidatePlaybackState];
    }
}

- (double)currentTime {
    return [_delegate currentTimeOfPictureInPicturePlayerView];
}


- (void)removeFromSuper {
    [self.layer removeFromSuperlayer];
}

- (CGRect)frame {
    return self.layer.frame;
}

//zero frame will cause the pipController to be loading
- (void)setFrame:(CGRect)frame {
    if (CGRectEqualToRect(frame, CGRectZero)) {
        self.layer.hidden = YES;
    } else {
        self.layer.hidden = NO;
        self.layer.frame = frame;
    }
}


//MARK: IVTPictureInPicturePlayerView

- (AVPictureInPictureController *)makePipController {
    if (@available(iOS 15.0, *)) {
        AVPictureInPictureController * controller =  [[AVPictureInPictureController alloc] initWithContentSource:[AVPictureInPictureControllerContentSource.alloc initWithSampleBufferDisplayLayer:self.layer playbackDelegate:self]];
        _pipController = controller;
        return controller;
    } else {
        return nil;
    }
}

- (void)onPipStarted {
    if (_autoPauseWhenPlayToEndTime) {
        [self addEndTimer];
    }
    
}

- (void)beforeMakePip:(BOOL)forPrepare {}

- (void)syncProgress {
    if (_duration == 0) {
        if (_keepSameLiveStyle) {
            CMTimebaseSetTime(_layer.controlTimebase, CMTimeMakeWithSeconds(0, 600));
        }
        return;
    }
    double time = [self currentTime];
    time = MIN(time, _duration);
    time = MAX(0, time);
    CMTimebaseSetTime(_layer.controlTimebase, CMTimeMakeWithSeconds(time, 600));
}


- (void)seekToTime:(double)time {
    if (_duration == 0) {
        if (_keepSameLiveStyle) {
            CMTimebaseSetTime(_layer.controlTimebase, CMTimeMakeWithSeconds(0, 600));
        }
        return;
    }
    time = MIN(time, _duration);
    time = MAX(0, time);
    CMTimebaseSetTime(_layer.controlTimebase, CMTimeMakeWithSeconds(time, 600));
    [_delegate pictureInPicturePlayerViewSeekToTime:time completion:^{
        [self invalidatePlayback];
    }];
}

- (void)resetDuration:(double)newDuration size:(CGSize)newSize completion:(nullable void (^)(NSError * _Nullable))completion {
    _duration = newDuration;
    CMTimebaseSetTime(_layer.controlTimebase, kCMTimeZero);
    newSize = newSize.width == 0 || newSize.height == 0 ? _size : IVTPIPCompressSize(newSize);
    if (!CGSizeEqualToSize(_size, newSize)) {
        _size = newSize;
        [self drawOneFrame];
    }
    !completion ?: completion(nil);
    [self invalidatePlayback];
}

- (void)notifyFailed:(NSString *)message {
    [_delegate pictureInPicturePlayerViewFailed:[NSError errorWithDomain:@IVTPictureInPictureTag code:0 userInfo:@{NSLocalizedDescriptionKey:message}]];
}

- (void)notifyError:(NSError *)error {
    [_delegate pictureInPicturePlayerViewFailed:error];
}

- (void)prepareBeforeStartWithRate:(double)rate {
    self.rate = rate;
}

- (void)prepareToPlay {
    
    AVSampleBufferDisplayLayer *playerLayer = self.layer;
    CMTimebaseRef timebase;
    CMTimebaseCreateWithSourceClock(nil, CMClockGetHostTimeClock(), &timebase);
    CMTimebaseSetTime(timebase, kCMTimeZero);
    CMTimebaseSetRate(timebase, _duration == 0 ? 0.0001 : 1);
    playerLayer.controlTimebase = timebase;
    if (timebase) {
        CFRelease(timebase);
    }
    
    [self drawOneFrame];
    [_delegate pictureInPicturePlayerViewReadyToPlay];
}

- (void)drawOneFrame {
    CMSampleBufferRef sampleBuffer = [self makeSampleBuffer];
    if (sampleBuffer) {
        [_layer enqueueSampleBuffer:sampleBuffer];
        CFRelease(sampleBuffer);
    } else {
        [self notifyFailed:@"Sample Buffer create failed"];
    }
}

- (CMSampleBufferRef)makeSampleBuffer {
    size_t width = (size_t)_size.width;
    size_t height = (size_t)_size.height;

    const int pixel = 0xFFFF9900;// {0x00, 0x99, 0xFF, 0xFF};//BGRA

    CVPixelBufferRef pixelBuffer = NULL;
    
    if (CVPixelBufferCreate(NULL, width, height, kCVPixelFormatType_32BGRA,
                            (__bridge CFDictionaryRef)@{
                                (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
                            }, &pixelBuffer) != kCVReturnSuccess) {
        [self notifyFailed:@"CVPixelBuffer alloc failed"];
        return nil;
    }
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    int *bytes = CVPixelBufferGetBaseAddress(pixelBuffer);
    for (NSUInteger i = 0, length = height * CVPixelBufferGetBytesPerRow(pixelBuffer) / 4 ; i < length; ++i) {
        bytes[i] = pixel;
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    CMSampleBufferRef sampleBuffer = [self sampleBufferFromPixelBuffer:pixelBuffer];
    CVPixelBufferRelease(pixelBuffer);
    return sampleBuffer;
}

- (CMSampleBufferRef)sampleBufferFromPixelBuffer:(CVPixelBufferRef)pixelBuffer {

    CMSampleBufferRef sampleBuffer = NULL;
    OSStatus err = noErr;
    CMVideoFormatDescriptionRef formatDesc = NULL;
    err = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDesc);

    if (err != noErr) {
        return nil;
    }

    CMSampleTimingInfo sampleTimingInfo = {
        .duration = CMTimeMakeWithSeconds(1, 600),
        .presentationTimeStamp = CMTimebaseGetTime(_layer.timebase),
        .decodeTimeStamp = kCMTimeInvalid
    };

    err = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, pixelBuffer, formatDesc, &sampleTimingInfo, &sampleBuffer);

    if (err != noErr) {
        return nil;
    }

    CFRelease(formatDesc);

    return sampleBuffer;

}

- (void)setStalled:(BOOL)stalled {
    if (stalled != _stalled) {
        _stalled = stalled;
        if (stalled) {
            CMTimebaseSetRate(_layer.controlTimebase, 0.001);
        } else {
            CMTimebaseSetRate(_layer.controlTimebase, _rate);
            [self syncProgress];
        }
    }
}

- (void)setRate:(double)rate {
    
    if (_duration == 0) {
        rate = rate > 0 ? 0.0001 : 0;
    }
    
    if (CMTimebaseGetRate(_layer.controlTimebase) != rate) {
        CMTimebaseSetRate(_layer.controlTimebase, rate != 0 && _stalled ? 0.001 : rate);
    }
    
    double oldRate = _rate;
    if (rate == oldRate) {
        return;
    }
    if (rate != 0) {
        _speed = rate;
    }
    _rate = rate;
    
    [self syncProgress];
    runOnMainThread(^{
        [self invalidatePlayback];
    });
    
    if (rate > 0 != oldRate > 0) {
        [self.delegate pictureInPicturePlayerViewPlaying:rate > 0];
    }
}

- (void)setKeepSameLiveStyle:(bool)keepSameLiveStyle {
    _keepSameLiveStyle = keepSameLiveStyle;
    [self invalidatePlayback];
}

- (void)setAutoPauseWhenPlayToEndTime:(BOOL)autoPauseWhenPlayToEndTime {
    if (_autoPauseWhenPlayToEndTime == autoPauseWhenPlayToEndTime) {
        return;
    }
    _autoPauseWhenPlayToEndTime = autoPauseWhenPlayToEndTime;
    
    if (!autoPauseWhenPlayToEndTime) {
        [_endTimer invalidate];
        _endTimer = nil;
    } else if (_pipController.isPictureInPictureActive) {
        [self addEndTimer];
    }
}

- (void)addEndTimer {
    if (@available(iOS 10.0, *)) {
        [_endTimer invalidate];
        __weak __auto_type weakSelf = self;
        NSTimer *timer = [NSTimer timerWithTimeInterval:0.45 repeats:YES block:^(NSTimer * _Nonnull timer) {
            __strong __auto_type self = weakSelf;
            if (!self) {
                [timer invalidate];
                return;
            }
            if (CMTimeGetSeconds(CMTimebaseGetTime(self.layer.controlTimebase)) >= self.duration) {
                self.rate = 0;
            }
        }];
        [NSRunLoop.mainRunLoop addTimer:timer forMode:NSDefaultRunLoopMode];
        _endTimer = timer;
    }
}

//MARK: AVPictureInPictureSampleBufferPlaybackDelegate

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController setPlaying:(BOOL)playing {
    runOnMainThread(^{
        if (playing) {
            self.rate = self.speed;
        } else {
            self.rate = 0;
        }
    });
}

- (CMTimeRange)pictureInPictureControllerTimeRangeForPlayback:(AVPictureInPictureController *)pictureInPictureController {
    if (_duration == 0) {
        if (_keepSameLiveStyle) {
            return CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(IVTDefaultLiveDuration, 600));
        }
        return CMTimeRangeMake(kCMTimeZero, kCMTimePositiveInfinity);
    }
    return CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(_duration, 600));
}

- (BOOL)pictureInPictureControllerIsPlaybackPaused:(AVPictureInPictureController *)pictureInPictureController {
    //player should be paused for automatically start
    return _rate == 0;
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController didTransitionToRenderSize:(CMVideoDimensions)newRenderSize {
    
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController skipByInterval:(CMTime)skipInterval completionHandler:(void (^)(void))completionHandler {
    [self skipByInterval:CMTimeGetSeconds(skipInterval) completion:completionHandler];
    
}

- (void)skipByInterval:(double)interval completion:(nonnull void (^)(void))completionHandler {
    runOnMainThread(^{
        double newTime = [self currentTime] + interval;
        [self.delegate pictureInPicturePlayerViewSeekToTime:newTime completion:^{
            LOGI("seek over");
            double currentTime = [self currentTime];
            if (fabs(currentTime - newTime) > 0.5) {
                runOnMainThread(^{
                    completionHandler();
                    CMTimebaseSetTime(self.layer.controlTimebase, CMTimeMakeWithSeconds(currentTime, 600));
                });
            } else {
                runOnMainThread(completionHandler);
                CMTimebaseSetTime(self.layer.controlTimebase, CMTimeMakeWithSeconds(currentTime, 600));
            }
        }];
    });
}


@end
