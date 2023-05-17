

#import "IVTPictureInPictureAVPlayerView.h"
#import "IVTPictureInPictureInner.h"
#import "IVTMovieFileBuilder.h"
#import <pthread/pthread.h>
#import <sys/sysctl.h>
#import <AVKit/AVKit.h>

static void * IVTPictureInPicturePlayerViewContext = &IVTPictureInPicturePlayerViewContext;

@interface IVTPictureInPictureAVPlayerView()
@property (nonatomic, strong) AVPlayerItem *playerItem;
@property (nonatomic, readwrite) AVPlayerLayer *layer;
@property (nonatomic) AVPlayer *player;
@property (nonatomic) CGSize size;//视频尺寸
@property (nonatomic) NSTimeInterval duration;//视频时长
@property (nonatomic) NSTimeInterval lastPauseTime;
@property (nonatomic) BOOL skipJump;
@property (nonatomic) BOOL readyToPlay;
@property (nonatomic) NSString *movFilePath;
@property (nonatomic) double speed;
@end

@implementation IVTPictureInPictureAVPlayerView
@synthesize rate = _rate, delegate = _delegate, stalled = _stalled, autoPauseWhenPlayToEndTime = _autoPauseWhenPlayToEndTime;

 
- (instancetype)initWithSize:(CGSize)size duration:(NSTimeInterval)duration {
    if (self = [super init]) {
        _size = IVTPIPCompressSize(size);
        _duration = duration;
        _layer = [AVPlayerLayer new];
        _rate = 1;
        _autoPauseWhenPlayToEndTime = true;
    }
    return self;
}

- (void)dealloc {
    [self free];
}

- (void)setPlayer:(AVPlayer *)player {
    _layer.player = player;
}

- (AVPlayer *)player {
    return _layer.player;
}

- (void)setFrame:(CGRect)frame {
    _layer.frame = frame;
}

- (CGRect)frame {
    return _layer.frame;
}

- (void)removeFromSuper {
    [self.layer removeFromSuperlayer];
}


- (void)free {
    [self.playerItem removeObserver:self forKeyPath:@"status" context:IVTPictureInPicturePlayerViewContext];
    [self.player removeObserver:self forKeyPath:@"rate" context:IVTPictureInPicturePlayerViewContext];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_duration != 0 && _movFilePath.length) {
        [NSFileManager.defaultManager removeItemAtPath:_movFilePath error:nil];
    }
}

- (void)clear {
    [self free];
    _playerItem = nil;
}


NS_INLINE AVAsset *assetFromPath(NSString *path) {
    NSURL *url = [[NSURL alloc] initFileURLWithPath:path];
    // Create asset to be played
    AVAsset *asset = [[AVURLAsset alloc] initWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    if (asset && CMTimeGetSeconds(asset.duration) > 0) {
        return asset;
    }
    return nil;
}

- (void)createMovieFileWithDuration:(double)duration size:(CGSize)size completion:(void (^)(AVAsset *asset,NSError * _Nullable))completion {

    IVTMovieModel *movieModel = [[IVTMovieModel alloc] init];
    movieModel.frameRate = 10;
    movieModel.duration = duration != 0 ? duration + 0.5 : IVTDefaultLiveDuration;
    movieModel.width = size.width;
    movieModel.height = size.height;
    NSString *libDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    NSString *pipDir = [libDir stringByAppendingString:@"/picture_in_picture_mov_file"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:pipDir]) {
        [fileManager createDirectoryAtPath:pipDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSString *movFilePath = [pipDir stringByAppendingString:
                             [NSString stringWithFormat:@"/pip_%dx%d_%.1f.mov",
                              movieModel.width, movieModel.height, duration]];
    
    if ([NSFileManager.defaultManager fileExistsAtPath:movFilePath]) {
        _movFilePath = movFilePath;
        AVAsset *asset = assetFromPath(movFilePath);
        if (asset) {
            completion(asset, nil);
        }
        return;
    }
    static int counter = 0;
    NSString *tmpMovFilePath = [movFilePath stringByAppendingFormat:@"%d.mov", ++counter];
    movieModel.outputPath = tmpMovFilePath;
    movieModel.isFillLast = YES;
    IVTMovieFileBuilder *movieFileBuilder = [[IVTMovieFileBuilder alloc] initWithMovieModel:movieModel];
    [movieFileBuilder movieFileBuild:^(NSError *err) {
        if (!err) {
            [NSFileManager.defaultManager moveItemAtPath:tmpMovFilePath toPath:movFilePath error:&err];
        }
        AVAsset *asset = err ? nil : assetFromPath(movFilePath);
        err = asset ? nil : err ?: [NSError errorWithDomain:@IVTPictureInPictureTag code:-1 userInfo:@{
            NSLocalizedDescriptionKey:@"create asset for pip failed"
        }];
        [IVTMovieSampleCacheCenter cacheAsset:asset size:size];
        !completion ?: completion(asset, err);
    }];
}

- (void)monitorSeekEvents {
    if (_duration > 0) {
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(AVPlayerItemTimeJumpedNotificationCallback:) name:AVPlayerItemTimeJumpedNotification object:self.playerItem];
    }
}

#pragma mark - Public

- (void)generatePlayerWithAsset:(AVAsset *)asset {
    LOGI("player view asset created");
    NSArray *assetKeys = @[@"playable"];
    
    _playerItem = [AVPlayerItem playerItemWithAsset:asset
                           automaticallyLoadedAssetKeys:assetKeys];
    
    [_playerItem addObserver:self
                      forKeyPath:@"status"
                         options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionInitial
                         context:IVTPictureInPicturePlayerViewContext];
    
    // Associate the player item with the player
    self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
    
    [self.player addObserver:self
                  forKeyPath:@"rate"
                     options: NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
                     context:IVTPictureInPicturePlayerViewContext];
    
    [self configActionAtEnd];
    //self.player.muted = YES;
}

- (void)prepareToPlay {
    __weak typeof(self) weakSelf = self;
    [self createMovieFileWithDuration:_duration size:_size completion:^(AVAsset *asset, NSError * _Nonnull err) {
        __strong typeof(weakSelf) self = weakSelf;
        if (err || !asset) {
            if ([self.delegate respondsToSelector:@selector(pictureInPicturePlayerViewFailed:)]) {
                [self.delegate pictureInPicturePlayerViewFailed:err];
            }
            return;
        }
        [self generatePlayerWithAsset:asset];
    }];
}

- (AVPictureInPictureController *)makePipController {
    return [AVPictureInPictureController.alloc initWithPlayerLayer:self.layer];
}


- (double)currentTime {
    if (_duration == 0) {
        return 0;
    }
    if ([_delegate respondsToSelector:@selector(currentTimeOfPictureInPicturePlayerView)]) {
        return [_delegate currentTimeOfPictureInPicturePlayerView];
    }
    return CMTimeGetSeconds(self.player.currentTime);
}

- (void)syncProgress {
    [self seekToTime:[self currentTime] skipJump:YES completion:nil];
}

- (void)seekToTime:(double)time skipJump:(BOOL)skipJump completion:(void(^)(void))completion{
    _skipJump = skipJump;
    [self.player seekToTime:CMTimeMakeWithSeconds(time, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        self.skipJump = false;
        !completion ?:completion();
    }];
}

- (void)seekToTime:(double)time {
    [self seekToTime:time skipJump:NO completion:nil];
}

- (void)setStalled:(BOOL)stalled {
    if (stalled != _stalled) {
        _stalled = stalled;
        if (stalled) {
            [self updatePlayerRate:0.0001f];
        } else {
            [self updatePlayerRate:_rate];
        }
    }
}

- (void)setRate:(double)rate {
    _rate = rate;
    if (rate >0) {
        _speed = rate;
    }
    [self updatePlayerRate:rate];
}

- (void)updatePlayerRate:(float)rate {
    if (_duration == 0) {
        //Fix rate for live
        rate = rate > 0 ? 0.0001f : 0;
        if (self.player.rate != (float)rate) {
            self.player.rate = rate;
        }
        return;
    }
    if (self.player.rate != rate) {
        double currentTime = [self currentTime];
        if (currentTime - _duration > -0.1) { // reach end
            if (rate != 0) { // play should start from 0 again
                [self seekToTime:0 skipJump:YES completion:nil];
            }
        } else if (fabs(currentTime - CMTimeGetSeconds(self.player.currentTime)) > 0.1) {
            [self seekToTime:currentTime skipJump:YES completion:nil];
        }
        self.player.rate = rate != 0 && _stalled ? 0.0001f : rate;
    }
}

- (void)prepareBeforeStartWithRate:(double)rate {
    if (rate > 0) {
        self.rate = rate;
    } else if (@available(iOS 14, *)){
        self.rate = rate;
    }
}

- (void)beforeMakePip:(BOOL)forPrepare {
    if (forPrepare) {
        // stalled the rate of the inner player view temporary;
        // or the pip won't be opened
        self.rate = 0.0001;
    }
}

- (void)onPipStarted {
}

- (void)resetDuration:(double)duration size:(CGSize)size completion:(void (^)(NSError * _Nullable error))completion {
    if (!_playerItem) {
        !completion ?: completion(nil);
        return;
    }
    if (size.width == 0 || size.height == 0) {
        size = _size;
    } else {
        size = IVTPIPCompressSize(size);
    }
    if ((_duration == duration || fabs(duration - CMTimeGetSeconds(_playerItem.duration)) < 0.1) &&
        CGSizeEqualToSize(size, _size)) {
        [self seekToTime:0 skipJump:YES completion:^{
            !completion ?: completion(nil);
        }];
        return;
    }
   
    [self createMovieFileWithDuration:duration size:size completion:^(AVAsset *asset, NSError * _Nullable error) {
        if (error) {
            !completion ?: completion(error);
            return;
        }
        [self clear];
        self.duration = duration;
        self.size = size;
        [self generatePlayerWithAsset:asset];
        [self syncProgress];
        [self setRate:self.rate];
        !completion ?: completion(nil);
    }];
}

- (void)setAutoPauseWhenPlayToEndTime:(BOOL)autoPauseWhenPlayToEndTime {
    _autoPauseWhenPlayToEndTime = autoPauseWhenPlayToEndTime;
    [self configActionAtEnd];
}

- (void)configActionAtEnd {
     self.player.actionAtItemEnd = _autoPauseWhenPlayToEndTime ? AVPlayerActionAtItemEndPause : AVPlayerActionAtItemEndNone;
}


#pragma mark - Notification

//暂停或seek时调用
- (void)AVPlayerItemTimeJumpedNotificationCallback:(NSNotification *)noti {
    NSTimeInterval time = CACurrentMediaTime();
    if (fabs(time - _lastPauseTime) < 0.5) {
        return;
    }
    if (_skipJump) {
        return;
    }
    if ([_delegate respondsToSelector:@selector(pictureInPicturePlayerViewSeekToTime:completion:)]) {
        [_delegate pictureInPicturePlayerViewSeekToTime:CMTimeGetSeconds(self.player.currentTime) completion:nil];
    }
}

- (void)skipByInterval:(double)interval completion:(void (^)(void))completionHandler {
    runOnMainThread(^{
        double newTime = [self currentTime] + interval;
        [self.delegate pictureInPicturePlayerViewSeekToTime:newTime completion:^{
            LOGI("seek over");
            double currentTime = [self currentTime];
            if (fabs(currentTime - newTime) > 0.5) {
                runOnMainThread(^{
                    [self seekToTime:currentTime skipJump:YES completion:nil];
                    completionHandler();
                });
            } else {
                runOnMainThread(completionHandler);
            }
        }];
    });
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSString *,id> *)change
                       context:(void *)context {
    if (context != IVTPictureInPicturePlayerViewContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    if ([keyPath isEqualToString:@"status"]) {
        AVPlayerItemStatus status = [(NSNumber *)[change valueForKey:NSKeyValueChangeNewKey] integerValue];
        AVPlayerItem *playerItem = (AVPlayerItem *)object;
        switch (status) {
            case AVPlayerItemStatusReadyToPlay:
            {
                if (@available(iOS 14, *)) {
                } else {
                    self.rate = 1;
                }
                if (_readyToPlay) {
                    return;
                }
                _readyToPlay = true;
                if ([self.delegate respondsToSelector:@selector(pictureInPicturePlayerViewReadyToPlay)]) {
                    [self.delegate pictureInPicturePlayerViewReadyToPlay];
                }
                break;
            }
                break;
            case AVPlayerItemStatusFailed:
            {
                if ([self.delegate respondsToSelector:@selector(pictureInPicturePlayerViewFailed:)]) {
                    [self.delegate pictureInPicturePlayerViewFailed:playerItem.error];
                }
            }
                break;
            case AVPlayerItemStatusUnknown:
            {
            }
                break;
        }
    } else if ([keyPath isEqualToString:@"rate"]) {
        double rate = [(NSNumber *)[change valueForKey:NSKeyValueChangeNewKey] doubleValue];
        double oldRate = [(NSNumber *)[change valueForKey:NSKeyValueChangeOldKey] doubleValue];
            
        if (rate > 0 != oldRate > 0 && [_delegate respondsToSelector:@selector(pictureInPicturePlayerViewPlaying:)]) {
            if (rate == 0) {
                _lastPauseTime = CACurrentMediaTime();
            }
            if (oldRate == 0) {
                [self updatePlayerRate:_stalled ? 0.0001f : _speed];
            }
            [_delegate pictureInPicturePlayerViewPlaying:rate > 0];
        }
        
    }
}

@end
