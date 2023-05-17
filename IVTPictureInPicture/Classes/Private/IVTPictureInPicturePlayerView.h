//
//  TTVPictureInPicturePlayerView.h
//  pictureInPicture
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol IVTPictureInPicturePlayerViewDelegate <NSObject>

- (void)pictureInPicturePlayerViewReadyToPlay;
- (void)pictureInPicturePlayerViewFailed:(NSError *)error;
- (void)pictureInPicturePlayerViewPlaying:(BOOL)playing;
- (void)pictureInPicturePlayerViewSeekToTime:(double)seekToTime completion:(nullable dispatch_block_t)completion;
- (double)currentTimeOfPictureInPicturePlayerView;
@end

@protocol IVTPictureInPicturePlayerView <NSObject>
@property (nonatomic, strong, readonly) __kindof CALayer *layer;
@property (nonatomic, assign) CGRect frame;
@property (nonatomic, assign) double rate;
@property (nonatomic, assign) BOOL stalled;
@property (nonatomic, assign) BOOL autoPauseWhenPlayToEndTime;
@property (nonatomic, weak, nullable) id<IVTPictureInPicturePlayerViewDelegate> delegate;

- (instancetype)initWithSize:(CGSize)size duration:(NSTimeInterval)duration;

- (void)removeFromSuper;

- (void)prepareToPlay;

- (void)syncProgress;

- (void)seekToTime:(double)time;

- (void)skipByInterval:(double)interval completion:(void (^)(void))completionHandler;

- (void)resetDuration:(double)newDuration size:(CGSize)newSize completion:(nullable void(^)(NSError * _Nullable error))completion;

- (AVPictureInPictureController *)makePipController;

//setFrame is override for visibility adjust
//sync rate on manually stared
- (void)prepareBeforeStartWithRate:(double)rate;

- (void)beforeMakePip:(BOOL)forPrepare;

- (void)onPipStarted;

@optional

- (void)monitorSeekEvents;


@end






NS_ASSUME_NONNULL_END
