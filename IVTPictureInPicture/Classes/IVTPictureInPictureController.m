//
//  IVTPictureInPictureController.m
//  TTVideoBusiness
//

#import "IVTPictureInPictureController.h"
#import <objc/runtime.h>
#import "IVTPictureInPictureAVPlayerView.h"
#import "IVTPictureInPictureSampleBufferPlayerView.h"
#import "IVTPictureInPictureInner.h"

#define keypath(OBJ, PATH) \
(((void)(NO && ((void)OBJ.PATH, NO)), # PATH))
#define let __auto_type const
#define var __auto_type
#define MAX_RETRY_COUNT 1



@interface NSProxy (HiddenSelectors)
@property (nonatomic, getter= isPIPModeEnabled) bool PIPModeEnabled;
@property (nonatomic) BOOL canPausePlaybackWhenExitingPictureInPicture;
@property (nonatomic) long status;
@property (nonatomic) long controlsStyle;
- (id)platformAdapter;
- (id)pegasusProxy;
- (void)seekToTime;
- (void)currentTimeWithinEndTimes;
- (void)pictureInPictureProxy:(id)arg1 didReceivePlaybackCommand:(id)arg2;
- (id)pictureInPictureViewController;
- (void)_stopPictureInPictureAndRestoreUserInterface;
- (void)setAllowsPictureInPictureFromInlineWhenEnteringBackground:(BOOL)allow;
- (void)_stopPictureInPictureAndRestoreUserInterface:(BOOL)restore;
- (void)stopPictureInPictureEvenWhenInBackground;
@end

static SEL sPictureInPictureViewController;
static void * IVTPIPVCPositionContext = &IVTPIPVCPositionContext;
static void * IVTPIPVCBoundsContext = &IVTPIPVCBoundsContext;
static void * IVTPIPContentFrameContext = &IVTPIPContentFrameContext;
static void * IVTPIPSublayersContext = &IVTPIPSublayersContext;
static void * IVTPIPPossibleContext = &IVTPIPPossibleContext;

static SEL sStopPictureInPictureAndRestoreUserInterface;
static SEL sStopPictureInPictureEvenWhenInBackground;
static SEL sCurrentTimeWithinEndTimes;
static SEL sAllowAutomaticallyWhenEnteringBackground;
static SEL sControlsStyle;


static Ivar readIvar(Class c, const char *name) {
    uint count = 0;
    Ivar *ivars = class_copyIvarList(AVPictureInPictureController.class, &count);
    Ivar targetIvar = nil;
    for (int i = count; i--; ) {
        Ivar ivar = ivars[i];
        if (strcmp(ivar_getName(ivar), name) == 0) {
            targetIvar = ivar;
        }
    }
    free(ivars);
    return targetIvar;
}

@implementation AVPlayerLayer (PipHelper)

static SEL PIPModeEnabled;
static SEL SetPIPModeEnabled;

+ (void)load {
    PIPModeEnabled = @selector(isPIPModeEnabled);
    SetPIPModeEnabled = @selector(setPIPModeEnabled:);
}

- (BOOL)pictureInPictureModeEnabled {
    return boolValueForKey(self, PIPModeEnabled);
}

- (void)setPictureInPictureModeEnabled:(BOOL)pictureInPictureModeEnabled {
    setIntValueForKey(self, SetPIPModeEnabled, pictureInPictureModeEnabled);
}

@end

typedef enum : NSUInteger {
    IVTPGCommandPlaybackActionSeek = 1,
    IVTPGCommandPlaybackActionSetPlaying = 2,
} IVTPGCommandPlaybackAction;

@protocol IVTPGCommand <NSObject>
@property (nonatomic,readonly) IVTPGCommandPlaybackAction playbackAction;
@property (nonatomic,readonly) double associatedDoubleValue;
@property (nonatomic,readonly) BOOL associatedBoolValue;

@end

@protocol IVTPDelegated <NSObject>
@property (nonatomic, weak) id delegate;
@end

typedef enum : uint8_t {
    NotRestore,
    RestoreFromBackground,
    RestoreFromForeground,
} RestoreType;

API_AVAILABLE(ios(10.0))
__attribute__((objc_direct_members))
@interface IVTPictureInPictureController() <AVPictureInPictureControllerDelegate, IVTPictureInPicturePlayerViewDelegate> {
    uint8_t _autoPauseWhenPlayToEndTime;
}

@property (nonatomic) AVPictureInPictureController *pipController;
@property (nonatomic, strong) UIViewController *pipViewController;

@property (nonatomic) NSObject<IVTPictureInPicturePlayerView>  *pipPlayer;//小窗使用的播放器

@property (nonatomic, weak) UIView *playerSnapShot;
@property (nonatomic) NSTimer *liveTimer;
@property (nonatomic) RestoreType restoreType;//是否点击小窗返回按钮
@property (nonatomic) BOOL isResumable;//小窗是否可恢复
@property (nonatomic) BOOL isShowed;//小窗是否完成展示
@property (nonatomic) BOOL isActive;//小窗是否开始展示或者展示中
@property (nonatomic) BOOL shouldStopOnActive;//小窗是否应该停止展示
@property (nonatomic) BOOL pausedWhenScreenLocked;
@property (nonatomic) BOOL screenLockObserved;
@property (nonatomic) BOOL started;
@property (nonatomic) BOOL observedSubLayer;
@property (nonatomic) BOOL observedPipBounds;
@property (nonatomic) BOOL observedPipPosition;
@property (nonatomic) BOOL observedContentFrame;
@property (nonatomic) BOOL observedPossible;
@property (nonatomic) BOOL isForeground;
@property (nonatomic) BOOL observedAppState;
@property (nonatomic) BOOL aboutToRestore;
@property (nonatomic) BOOL readyToPlay;
@property (nonatomic) int appStateCount;
@property (nonatomic) int retryCount;
@property (nonatomic) int startCheckCount;
@property (nonatomic, copy) dispatch_block_t finishBlock;

@end

@interface IVTPictureInPictureController()
- (void)appDidEnterBackground;
- (void)appDidBecomeActive;
- (void)willEnterForeground;
- (void)appWillTerminate;
@end

__attribute__((objc_direct_members))
@implementation IVTPictureInPictureController

@dynamic autoPauseWhenPlayToEndTime;

static IVTPictureInPictureController* sCurrentInstance;

+ (instancetype)sharedInstance {
    if (sCurrentInstance == nil) {
        sCurrentInstance = [IVTPictureInPictureController new];
    }
    return sCurrentInstance;
}

+ (instancetype)currentInstance {
    return sCurrentInstance;
}

+ (BOOL)isPictureInPictureSupported {
    if (@available(iOS 14, *)) {
        return true;
    }
    return false;
}

+ (BOOL)isActive {
    return [IVTPictureInPictureController currentInstance].started;
}

+ (void)enableBackgroundGPUUsage {
    if (@available(iOS 15, *)) {
        [UIApplication.sharedApplication beginReceivingRemoteControlEvents];
    }
}

+ (void)setLogCallback:(void (^)(IVTPictureInPictureLogLevel, const char *, const char * _Nonnull))logCallback {
    IVTPictureInPictureLogCallaback = (typeof(IVTPictureInPictureLogCallaback))logCallback;
}

+ (void (^)(IVTPictureInPictureLogLevel, const char *, const char * _Nonnull))logCallback {
    return (void (^)(IVTPictureInPictureLogLevel, const char *, const char * _Nonnull))IVTPictureInPictureLogCallaback;
}

static void HookIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (@available(iOS 16, *)) {
            
        } else {
            Class playerControllerClass = objc_getClass("AVPlayerController");//
            SEL seekToTimeSelector = @selector(seekToTime);//
            sCurrentTimeWithinEndTimes = @selector(currentTimeWithinEndTimes);
            IMP imp = [playerControllerClass instanceMethodForSelector:seekToTimeSelector];
            if (imp && [playerControllerClass instanceMethodForSelector:sCurrentTimeWithinEndTimes]) {
                class_replaceMethod(playerControllerClass, seekToTimeSelector, imp_implementationWithBlock(^double(__unsafe_unretained id sf){
                    double v = ((double(*)(id, SEL))imp)(sf, seekToTimeSelector);
                    if (isnan(v)) {
                        v = doubleValueForKey(sf, sCurrentTimeWithinEndTimes);
                    }
                    return v;
                }), "v16@0:8");
            } else {
                LOGE("Could not find currentTime method");
            }
        }
        sPictureInPictureViewController = @selector(pictureInPictureViewController);
        sStopPictureInPictureEvenWhenInBackground =
        @selector(stopPictureInPictureEvenWhenInBackground);
        sStopPictureInPictureAndRestoreUserInterface =
        @selector(_stopPictureInPictureAndRestoreUserInterface:);
        sAllowAutomaticallyWhenEnteringBackground = @selector(setAllowsPictureInPictureFromInlineWhenEnteringBackground:);
        sControlsStyle = @selector(setControlsStyle:);
    });
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _rate = 1;
        _speed = 1;
        if (@available(iOS 15, *)) {
            _backBySampleBuffer = true;
        }
        HookIfNeeded();
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self stopPictureInPicture];
    [self clearKVO];
    [_pipPlayer removeFromSuper];
    
}

- (void)startPictureInPicture {
    assert_main_thread();
    if (sCurrentInstance && sCurrentInstance != self) {
        [sCurrentInstance stopWithFinishBlock:^{
            [self startPictureInPicture];
        }];
        return;
    }
    _started = true;
    sCurrentInstance = self;
    if (!_pipPlayer) {
        [self preparePlayerView];
    } else if (_readyToPlay) {
        [self startPipSafely];
    }
    
}

- (void)preparePictureInPicture {
    assert_main_thread();
    [self preparePlayerView];
}

- (void)stopPictureInPicture {
    assert_main_thread();
    [self stopWithFinishBlock:nil];
}

- (void)stopPictureInPictureEvenWhenInBackground {
    if ([_pipController respondsToSelector:sStopPictureInPictureEvenWhenInBackground]) {
        ((void(*)(id, SEL))objc_msgSend)(_pipController, sStopPictureInPictureEvenWhenInBackground);
    } else {
        [self stopPictureInPictureAndRestore:false];
    }
}

//原版的stopPictureInPicture有可能会把vc push回去，为了避免出现奇奇怪怪的bug，直接用隐藏接口
- (void)stopPictureInPictureAndRestore:(BOOL)restore {
    if ([_pipController respondsToSelector:sStopPictureInPictureAndRestoreUserInterface]) {
        //原参数就是布尔值，id是透传的，不做转换，所以直接传原值
        ((void(*)(id, SEL, BOOL))objc_msgSend)(_pipController, sStopPictureInPictureAndRestoreUserInterface, restore);
    } else {
        [_pipController stopPictureInPicture];
    }
}

- (void)stopAndRestore {
    assert_main_thread();
    [self stopAndRestore:true finishBlock:nil];
}

- (void)stopWithFinishBlock:(dispatch_block_t)block {
    assert_main_thread();
    [self stopAndRestore:false finishBlock:block];
}

- (void)stopAndRestore:(BOOL)restore finishBlock:(dispatch_block_t)block  {
    if ([_pipController isPictureInPictureActive]) {
        _isResumable = false;
        _isActive = false;
        if (_started) {
            if (restore) {
                [self stopPictureInPictureAndRestore:true];
            } else if (UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) {
                [self stopPictureInPictureEvenWhenInBackground];
            } else {
                [self stopPictureInPictureAndRestore:false];
            }
            _started = false; //防止重入
        }
        if (sCurrentInstance == self) {
            sCurrentInstance = nil;
        }
        [self appendFinishBlock:block];
    } else if (_isActive) {
        [self appendFinishBlock:block];
        _shouldStopOnActive = true;
    } else if (_started || _isResumable) {
        [self notifyWillStop];
        [self notifyDidStop];
        [self clear];
        if (block) {
            block();
        }
    } else if (block) {
        if (sCurrentInstance == self) {
            sCurrentInstance = nil;
        }
        block();
    }
}

- (void)appendFinishBlock:(dispatch_block_t)block {
    if (!block) {
        return;
    }
    if (!_finishBlock) {
        _finishBlock = block;
    } else {
        let f1 = _finishBlock;
        _finishBlock  = ^{
            f1();
            block();
        };
    }
}

- (void)hide {
    assert_main_thread();
    _isResumable = true;
    _started = false;
    ++_startCheckCount;
    if (_pipController.isPictureInPictureActive) {
        [self stopPictureInPictureAndRestore:false];
    } else if (_isActive) {
        _started = true;
        _shouldStopOnActive = true;
    } else if (_started) {
        _isResumable = false;
        [self stopPictureInPicture];// 没有启动的情况hide了相当于没启动成功
    }
}

- (void)hideAndPause {
    assert_main_thread();
    self.rate = 0;
    [self hide];
}

- (void)resume {
    if (_isResumable && _pipController && ![self isActive]) {
        self.rate = _speed;
        [self syncProgress];
        _started = true;
        if (_pipController.isPictureInPicturePossible) {
            [self startPipSafely];
        } else {
            [self ensureCategory];
            [self observePossible];
        }
    }
}


//小窗隐藏期间设置了其他参数,则小窗不再满足恢复条件,同时清空小窗所有数据
//显示期间设置了参数，直接杀死当前小窗
- (void)resetIfNeeded {
    let pipController = _pipController;
    if (pipController || _started || _isResumable) {
        pipController.delegate = nil;
        if (pipController) {
            [self stopPictureInPictureAndRestore:false];
        }
        [self notifyWillStop];
        [self notifyDidStop];
        [self clear];
    }
}

- (void)clear {
    [self clearKVO];
    UIViewController *pipVC = _pipViewController;
    if (pipVC && _contentView.superview == pipVC.view) {
        [_contentView removeFromSuperview];
    }
    _contentView = nil;
    [_pipPlayer removeFromSuper];
    
    _pipPlayer = nil;
    _pipViewController = nil;
    _pipController.delegate = nil;
    _pipController = nil;
    ++_startCheckCount;
    _delegate = nil;
    _enableSeek = false;
    _readyToPlay = false;
    _restoreType = NotRestore;
    _isShowed = false;
    _isActive = false;
    _shouldStopOnActive = false;
    _isResumable = false;
    _rate = 1;
    _speed = 1;
    _duration = 0;
    _started = false;
    _aboutToRestore = false;
    _finishBlock = nil;
    _keepSameLiveStyle = false;
    _autoPauseWhenScreenLocked = false;
    _autoResumeWhenScreenUnlocked = false;
    _targetFadeOutArea = CGRectZero;
    _targetForegroundRestoreArea = CGRectZero;
    _targetBackgroundRestoreArea = CGRectZero;
    _sourceArea = CGRectZero;
    if (_liveTimer) {
        [_liveTimer invalidate];
        _liveTimer = nil;
    }
    if (sCurrentInstance == self) {
        sCurrentInstance = nil;
    }
}

#pragma mark - Live

- (void)setupLiveTimer {
    //直播业务需要把进度保持在开始
    if(_duration != 0 || !_isShowed || (_backBySampleBuffer && !_keepSameLiveStyle)) {
        if (_liveTimer) {
            [_liveTimer invalidate];
            _liveTimer = nil;
        }
        return;
    }
    if (_liveTimer) {
        return;
    }
    if (@available(iOS 10.0, *)) {
        __auto_type __weak wSelf = self;
        NSTimer *timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer * _Nonnull timer) {
            [wSelf seekToTime:0];
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __auto_type __strong timer = wSelf.liveTimer;
            if (timer) {
                [NSRunLoop.currentRunLoop addTimer:timer forMode:NSDefaultRunLoopMode];
            }
        });
        _liveTimer = timer;
    }
}

#pragma mark - AVPictureInPictureControllerDelegate
/*!
    @method        pictureInPictureControllerWillStartPictureInPicture:
    @param        pictureInPictureController
                The Picture in Picture controller.
    @abstract    Delegate can implement this method to be notified when Picture in Picture will start.
 */
- (void)pictureInPictureControllerWillStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    if (!_started) {
        _started = true;
        sCurrentInstance = self;
    }
    _isActive = true;
    if (!_isResumable) {
        LOGI("will start");
        if ([_delegate respondsToSelector:@selector(pictureInPictureControllerWillStart:)]) {
            [_delegate pictureInPictureControllerWillStart:self];
        }
    } else {
        LOGI("will resume");
    }
    _pipViewController = [self readPipViewController];
    if (_autoEnableBackgroundRendering) {
        enumerateVisibleLayers(_contentView.layer, ^(CALayer *layer) {
            if ([layer isMemberOfClass:CALayer.class]) {
                return;
            }
            if ([layer isKindOfClass:AVPlayerLayer.class]) {
                ((AVPlayerLayer *)layer).pictureInPictureModeEnabled = true;
            } else if ([layer isKindOfClass:CAMetalLayer.class] || [layer isKindOfClass:CAEAGLLayer.class]) {
                [IVTPictureInPictureController enableBackgroundGPUUsage];
            }
        });
    }
    // allow user add view only when pip started.
    // 允许用户在willStart内添加view，以提升性能
    if (!_contentView) {
        return;
    }
    UIView *pipView = _pipViewController.view;
    [pipView addSubview:_contentView];
    _contentView.frame = pipView.bounds;
    _contentView.translatesAutoresizingMaskIntoConstraints = YES;
    _contentView.autoresizingMask = UIViewAutoresizingNone;
    [pipView.layer addObserver:self forKeyPath:@keypath(pipView.layer, sublayers) options: NSKeyValueObservingOptionNew context:IVTPIPSublayersContext];
    _observedSubLayer = YES;
    [pipView.layer addObserver:self forKeyPath:@keypath(pipView.layer, bounds) options: NSKeyValueObservingOptionNew context:IVTPIPVCBoundsContext];
    _observedPipBounds = YES;
    [_contentView.layer addObserver:self forKeyPath:@keypath(_contentView.layer, bounds) options: NSKeyValueObservingOptionNew context:IVTPIPContentFrameContext];
    _observedContentFrame = YES;
    
    [self addStartCheckTimer];
}

/*!
    @method        pictureInPictureControllerDidStartPictureInPicture:
    @param        pictureInPictureController
                The Picture in Picture controller.
    @abstract    Delegate can implement this method to be notified when Picture in Picture did start.
 */
- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    UIView *pipView = _pipViewController.view;
    _contentView.frame = pipView.bounds;
    _isShowed = true;
    //小窗展示过程中设置rate有概率同步不到小窗的按钮上
    _pipPlayer.rate = _rate;
    [self clearStartedKVO];
    [_pipPlayer onPipStarted];
    [self setupLiveTimer];
    [_pipPlayer syncProgress];
    _pipPlayer.frame = _targetFadeOutArea;
    ++_startCheckCount;
    [self observeScreenLock];
    if (!_isResumable) {
        LOGI("did start");
        if ([_delegate respondsToSelector:@selector(pictureInPictureControllerDidStart:)]) {
            [_delegate pictureInPictureControllerDidStart:self];
        }
    } else {
        LOGI("did resume");
        if (!_shouldStopOnActive) { //停止过程中，不需要清空这个标记位
            _isResumable = false;
        }
    }
   
    if (_shouldStopOnActive) {
        if (_isResumable) {
            [self hide];
        } else {
            [self stopPictureInPicture];
        }
        _shouldStopOnActive = false;
    }
    
}

/*!
    @method        pictureInPictureController:failedToStartPictureInPictureWithError:
    @param        pictureInPictureController
                The Picture in Picture controller.
    @param        error
                An error describing why it failed.
    @abstract    Delegate can implement this method to be notified when Picture in Picture failed to start.
 */
- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController failedToStartPictureInPictureWithError:(NSError *)error {
    if (_retryCount < MAX_RETRY_COUNT) {
        return;
    }
    if ([_delegate respondsToSelector:@selector(pictureInPictureController:failedToStartWithError:)]) {
        [_delegate pictureInPictureController:self failedToStartWithError:error];
    }
    
    LOGError("failedToStartWithError", error);
    [self clear];
}

- (void)pictureInPictureControllerWillStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    _isShowed = false;//小窗隐藏关闭后的不允许playing回调到原播放器上
    if (!_isResumable) {
        LOGI("will stop");
        [self notifyWillStop];
        [self generateSnapShot];
        _playerSnapShot.alpha = 1;
        if (_aboutToRestore) {
            if (_restoreType == RestoreFromForeground) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self restoreUserInterface];
                });
            } else {
                [self restoreUserInterface];
            }
        }
    } else {
        LOGI("will hide");
    }
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    _playerSnapShot = nil;
    _isActive = false;
    if (!_isResumable) {
        LOGI("did stop");
        _started = false;// 防止回调重入stopPictureInPicture
        let finishBlock = self.finishBlock;
        if (_aboutToRestore) { //主线程卡死导致dispatch比stop慢
            [self restoreUserInterface];
        }
        let strongSelf = self;
        [self notifyDidStop];
        [self clear];
        if (finishBlock) {
            finishBlock();
        }
    } else {
        LOGI("did hide");
    }
}
/**
 * 假设
 *A : pictureInPictureControllerWillStopPictureInPicture
 *B : pictureInPictureControllerDidStopPictureInPicture
 *C : pictureInPictureController:restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
 *那么
 *点击小窗返回按钮：C -> A -> B
 *点击小窗关闭按钮：A -> B
 *另外要注意此方法并不能执行耗时操作，push vc这种活就不回调出去了
 */
- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL restored))completionHandler {
    _restoreType = _isForeground ? RestoreFromForeground : RestoreFromBackground;
    _started = false;//防止vc回去时调用了stop
    _isShowed = false;//防止返回是播放器暂停了
    _aboutToRestore = isAvailableAudioCategory();
    if ([_delegate respondsToSelector:@selector(pictureInPictureController:willRestoreFromForeground:)]) {
        [_delegate pictureInPictureController:self willRestoreFromForeground:_isForeground];
    }
    _pipPlayer.frame = _isForeground ? _targetForegroundRestoreArea : _targetBackgroundRestoreArea;
    if (completionHandler) {
        completionHandler(YES);
    }
}

#pragma mark - AVPipUtils
- (NSTimeInterval)currentPlaybackTime {
    if ([_delegate respondsToSelector:@selector(currentPlaybackTimeOfPictureInPictureController:)]) {
        return [_delegate currentPlaybackTimeOfPictureInPictureController:self];
    }
    return 0;
}

- (void)notifyWillStop {
    if ([_delegate respondsToSelector:@selector(pictureInPictureController:willStopForRestore:)]) {
        [_delegate pictureInPictureController:self willStopForRestore:_restoreType != NotRestore];
    }
}

- (void)notifyDidStop {
    if ([_delegate respondsToSelector:@selector(pictureInPictureController:didStopForRestore:)]) {
        [_delegate pictureInPictureController:self didStopForRestore:_restoreType != NotRestore];
    }
}

- (void)generateSnapShot {
    if (_playerSnapShot) {
        return;
    }
    [self updateSnapshot];
}

- (void)updateSnapshot {
    let view = _pipViewController.view;
    if (!view || !_contentView) {
        return;
    }
    UIView *snapShot = [_contentView snapshotViewAfterScreenUpdates:false];
    if (_playerSnapShot) {
        [_playerSnapShot removeFromSuperview];
    }
    _playerSnapShot = snapShot;
    snapShot.frame = view.bounds;
    snapShot.alpha = 0;
    [view insertSubview:snapShot belowSubview:_contentView];
    if (!_observedPipPosition) {
        _observedPipPosition = true;
        [view.layer addObserver:self forKeyPath:@keypath(view.layer, position) options:NSKeyValueObservingOptionNew context:IVTPIPVCPositionContext];
    }
}

- (void)restoreUserInterface {
    if (!_aboutToRestore) {
        return;
    }
    if ([_delegate respondsToSelector:@selector(pictureInPictureController:restoreFromForeground:)]) {
        //自定义场景恢复
        [_delegate pictureInPictureController:self restoreFromForeground:_restoreType == RestoreFromForeground];
    }
    _aboutToRestore = false;
}

- (BOOL)canSyncPlaybackStatus:(BOOL)playing {
    if (_isShowed) {
        return true;
    }
    if (_isActive) {
        if (_observedSubLayer) {
            return false;
        }
        if (_canPauseWhenExiting) {
            return true;
        }
        return !playing;
    }
    
    if (_started) {
        return false;
    }
    if (_readyToPlay) {
        return false;
    }
    return true;
}

- (void)addStartCheckTimer {
    if (@available(iOS 10.0, *)) {
        __weak __auto_type weakSelf = self;
        int count = ++_startCheckCount;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong __auto_type self = weakSelf;
            if (self && self.startCheckCount == count && !self.isShowed ) {
                [self failsWithMessage:"remote failed to open"];
            }
        });
    }
}
         
#pragma mark - IVTPictureInPicturePlayerViewDelegate

- (void)pictureInPicturePlayerViewFailed:(NSError *)error {
    LOGError("player view failed",error);
    [self stopPictureInPicture];
}


- (void)pictureInPicturePlayerViewPlaying:(BOOL)playing {
    LOGI("player playing:%d",playing);
    if (!playing) {
        _rate = 0;
    }
    if (![self canSyncPlaybackStatus:playing]) {
        return;
    }
    if ([_delegate respondsToSelector:@selector(pictureInPictureController:isPlaying:)]) {
        [_delegate pictureInPictureController:self isPlaying:playing];
    }
}

//快进快退15s或暂停
- (void)pictureInPicturePlayerViewSeekToTime:(double)seekToTime completion:(dispatch_block_t)completion {
    if (!_isShowed) {
        return;
    }
    LOGI("pip seekToTime:%f", seekToTime);
    if (_enableSeek) {
        //增加条件:判断为seek时再调用
        if ([_delegate respondsToSelector:@selector(pictureInPictureController:seekToTime:completion:)]) {
            [_delegate pictureInPictureController:self seekToTime:seekToTime completion:completion];
        }
    }
}

- (void)pictureInPicturePlayerViewReadyToPlay {
    LOGI("ready to play");
    _readyToPlay = true;
    [self initPipController];
}

- (double)currentTimeOfPictureInPicturePlayerView {
    return [self currentPlaybackTime];
}

#pragma mark --App state

- (void)observeAppState {
    if (!_observedAppState) {
        _isForeground = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appDidEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(willEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appWillTerminate) name:UIApplicationWillTerminateNotification object:nil];
        _observedAppState = true;
    }
}

- (void)clearAppStateObserver {
    if (_observedAppState) {
        _isForeground = true;
        [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
        [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
        [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
        [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationWillTerminateNotification object:nil];
        _observedAppState = false;
    }
}

- (void)appWillTerminate {
    if (_notifyStopWhenTerminated) {
        [self notifyDidStop];
    }
}

- (void)appDidEnterBackground {
    ++_appStateCount;
    _isForeground = false;
    LOGI("did enter background");
}

- (void)appDidBecomeActive {
    int count = ++_appStateCount;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self onAppReallyActive:count];
    });
}

- (void)onAppReallyActive:(int)count {
    if (count == _appStateCount) {
        _isForeground = true;
    }
    if (_restoreType != RestoreFromBackground && _playerSnapShot) {
        [_playerSnapShot removeFromSuperview];
        _playerSnapShot = nil;
    }
    LOGI("did become active");
}

- (void)willEnterForeground {
    if (_playerSnapShot) {
        [_playerSnapShot removeFromSuperview];
        _playerSnapShot = nil;
    }
    if (!_contentView.window) {
        return;
    }
    if (!_started) {
        return;
    }
    [self generateSnapShot];
}

- (BOOL)isRestoringFromBackground {
    return _restoreType == RestoreFromForeground;
}

- (void)failsWithMessage:(const char *)message {
    LOGE("%s", message);
    [self pictureInPictureController:self.pipController failedToStartPictureInPictureWithError:[NSError errorWithDomain:@"IVTPictureInPicture" code:1 userInfo:@{NSLocalizedDescriptionKey:@(message)}]];
    [self clear];
}

#pragma mark - start pip

NS_INLINE BOOL isAvailableAudioCategory(void) {
    let category = AVAudioSession.sharedInstance.category;
    if (category != AVAudioSessionCategoryPlayback && category != AVAudioSessionCategoryPlayAndRecord && category != AVAudioSessionCategoryMultiRoute) {
        return false;
    }
    let options = AVAudioSession.sharedInstance.categoryOptions;
    if (options & AVAudioSessionCategoryOptionMixWithOthers) {
        return false;
    }
    return true;
}

- (void)ensureCategory {
    BOOL shouldFix = NO;
    var category = AVAudioSession.sharedInstance.category;
    let oldCategory = category;
    if (category != AVAudioSessionCategoryPlayback && category != AVAudioSessionCategoryPlayAndRecord && category != AVAudioSessionCategoryMultiRoute) {
        category = AVAudioSessionCategoryPlayback;
        shouldFix = YES;
    }
    var options = AVAudioSession.sharedInstance.categoryOptions;
    let oldOptions = options;
    if ((options & AVAudioSessionCategoryOptionMixWithOthers) == AVAudioSessionCategoryOptionMixWithOthers) {
        options = options & (~AVAudioSessionCategoryOptionMixWithOthers);
        shouldFix = YES;
    }
    
    if ((options & AVAudioSessionCategoryOptionDuckOthers) == AVAudioSessionCategoryOptionDuckOthers) {
        options = options & (~AVAudioSessionCategoryOptionDuckOthers);
        shouldFix = YES;
    }
    if ((options & AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers) == AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers) {
        options = options & (~AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers);
        shouldFix = YES;
    }
    if (@available(iOS 14.6, *)) {
        ///14.5 即以下机型不支持playandrecord
    } else if (shouldFix) {
        category = AVAudioSessionCategoryPlayback;
    }
    if (shouldFix) {
        LOGI("category fix from %s to %s, options from %lx to %lx", [oldCategory cStringUsingEncoding:NSASCIIStringEncoding], [category cStringUsingEncoding:NSASCIIStringEncoding], (unsigned long)oldOptions, (unsigned long)options);
        if (@available(iOS 10.0, *)) {
            [AVAudioSession.sharedInstance setCategory:category mode:AVAudioSession.sharedInstance.mode options:options error:nil];
        } else {
            [AVAudioSession.sharedInstance setCategory:category withOptions:options error:nil];
        }
        
    }
}

- (void)configAutomaticallyStart {
    if (@available(iOS 14.2, *)) {
        _pipController.canStartPictureInPictureAutomaticallyFromInline = _canStartAutomaticallyFromInline;
    } else {
        setIntValueForKey(_pipController, sAllowAutomaticallyWhenEnteringBackground, _canStartAutomaticallyFromInline);
    }
}

- (void)configCanPauseWhenExiting {
    static SEL selector;
    if (!selector) {
        selector = @selector(setCanPausePlaybackWhenExitingPictureInPicture:);
    }
    if ([_pipController respondsToSelector:selector]) {
        setIntValueForKey(_pipController, selector, _canPauseWhenExiting);
    }
}

- (void)makePipController {
    
    if (_started && !_backBySampleBuffer && ![self isVisibleAtStart]) {
        LOGI("fix pip view frame for invisible at start");
        _pipPlayer.frame = CGRectZero;
    }
    
    LOGI("start init pipController");
    _pipController = [_pipPlayer makePipController];
    
    _pipController.delegate = self;
    if (@available(iOS 14.0, *)) {
        _pipController.requiresLinearPlayback = !_enableSeek;
    }
    if (_controlsHidden) {
        [self configsControlsHidden];
    }
    
    [self configAutomaticallyStart];
    
    [self configCanPauseWhenExiting];
    
    [self monitorSeekEvents];
    
    if (!_pipController) {
        [self failsWithMessage:"system does not support picture in picture"];
        return;
    }
    
    [self observePossible];
    [self observeAppState];
    
    LOGI("pipController inited");
}

- (id)readPipViewController {
    if ([_pipController respondsToSelector:sPictureInPictureViewController]) {
        return objectValueForKey(_pipController, sPictureInPictureViewController);
    } else {
        static Ivar sIvarPictureInPictureViewController;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            char name[40];
            strcpy(name, "_");
            strcat(name, sel_getName(sPictureInPictureViewController));
            sIvarPictureInPictureViewController = readIvar(AVPictureInPictureController.class, name);
        });
        if (sIvarPictureInPictureViewController) {
            return object_getIvar(_pipController, sIvarPictureInPictureViewController);
        }
        return nil;
    }
}

- (void)initPipController {
    //WTF 为啥这时就有pipViewController了
    if (_pipController) {
        [self clearKVO];
        _pipController = nil;
        _pipViewController = nil;
    }
    
    [_pipPlayer beforeMakePip:!_started];
    
    [self makePipController];
    
}

- (void)observePossible {
    _observedPossible = true;
    [_pipController addObserver:self forKeyPath:@keypath(self.pipController, pictureInPicturePossible) options: NSKeyValueObservingOptionNew context:IVTPIPPossibleContext];
    if (_pipController.pictureInPicturePossible) {
        [self startPipSafely];
    }
}


- (BOOL)isActiveOrFailed {
    if (_isActive) {
        return true;//不是viewController，认为已经开启了
    }
    if (!_started || !_pipController) {
        return true;// 销毁了或者还没开始
    }
    return false;
}

- (void)startPipSafely {
    [self startPipIfNeeded];
    if ([self isActiveOrFailed]) {
        return;
    }
    AVPictureInPictureController *controller = _pipController;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (controller != self.pipController) {
            return;
        };
        [self startPipIfNeeded];
        if ([self isActiveOrFailed]) {
            return;
        }
        //0.5s后仍不能启动成功的直接上报异常
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (controller != self.pipController) {
                return;
            }
            [self startPipAndCheckFailed:true];
        });
    });
}

- (void)startPipIfNeeded {
    [self startPipAndCheckFailed:false];
}

static id pegasusProxyFromPlatformAdapter(id platformAdapter) {
    if (!platformAdapter) {
        return nil;
    }
    SEL proxyKey = @selector(pegasusProxy);
    if (![platformAdapter respondsToSelector:proxyKey]) {
        return nil;
    }
    return objectValueForKey(platformAdapter, proxyKey);
}

- (id)pipPlatformAdapter {
    if ([_pipController respondsToSelector:@selector(platformAdapter)]) {
        return objectValueForKey(_pipController, @selector(platformAdapter));
    }
    return nil;
}

- (id<IVTPDelegated>)pegasusProxy {
    return pegasusProxyFromPlatformAdapter([self pipPlatformAdapter]);
}

- (void)startPipAndCheckFailed:(BOOL)failWhenImpossible {
    if ([self isActiveOrFailed]) {
        return;
    }
    if (!_started) {
        return;
    }
    id platformAdapter = [self pipPlatformAdapter];
    id pegasusProxy = pegasusProxyFromPlatformAdapter(platformAdapter);
    if ([pegasusProxy respondsToSelector:@selector(isPictureInPicturePossible)]) {
        if (!boolValueForKey(pegasusProxy, @selector(isPictureInPicturePossible))) {
            if (failWhenImpossible) {
                _retryCount = 0;
                [self failsWithMessage:"system failed to open picture in picture on recheck"];
            }
            return;
        }
        SEL setStatus = @selector(setStatus:);
        if ([platformAdapter respondsToSelector:setStatus]) {
            setIntValueForKey(platformAdapter, setStatus, 1);
        }
    } else {
        if (![_pipController isPictureInPicturePossible]) {
            if (failWhenImpossible) {
                _retryCount = 0;
                [self failsWithMessage:"system failed to open picture in picture on recheck"];
            }
            return;
        }
    }

    LOGI("start pip");
    [self clearPossibleKVO];
    BOOL isOK = UIApplication.sharedApplication.applicationState == UIApplicationStateActive && !self.pipController.isPictureInPictureActive;
    if (![self isVisibleAtStart]) {
        if ([_pipPlayer isKindOfClass:IVTPictureInPictureSampleBufferPlayerView.class]) {
            _pipPlayer.layer.hidden = YES;
        } else if (!CGRectEqualToRect(CGRectZero, _pipPlayer.frame)){
            LOGI("start pip return for not visible at start");
            _pipPlayer.frame = CGRectZero;
            //等待frame同步才打开
            [self observePossible];
            return;
        }
    }
    [_pipPlayer prepareBeforeStartWithRate:_rate];
    
    if (isOK) {
        [_pipController startPictureInPicture];
    }
    if (_pipViewController && (!_contentView || _pipViewController.view == _contentView.superview)) {
        _retryCount = 0;
        LOGI("startPictureInPicture success tryCount:%d, recheck:%d", _retryCount, failWhenImpossible);
        return;
    }
    if (!failWhenImpossible) {
        return;
    }
    if(_retryCount < MAX_RETRY_COUNT && isOK) {
        [self clearKVO];
        _pipController.delegate = nil;
        _pipController = nil;
        _pipViewController = nil;
        [_pipPlayer removeFromSuper];
        _pipPlayer = nil;
        ++_retryCount;
        LOGI("startPictureInPicture failed and retry %d", _retryCount);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self startPictureInPicture];
        });
    } else{
        _retryCount = 0;
        [self failsWithMessage:[NSString stringWithFormat:@"system failed to open picture in picture, possible:%d", self.pipController.isPictureInPicturePossible].UTF8String];
    }
    
}

#pragma mark - KVO

- (void)clearStartedKVO {
    if (_observedSubLayer) {
        @try {
            [_pipViewController.view.layer removeObserver:self forKeyPath:@keypath(self.pipViewController.view.layer, sublayers) context:IVTPIPSublayersContext];
            _observedSubLayer = false;
        } @catch (NSException *exception) {
            LOGError("clear kvo failed", exception);
        }
    }
}

- (void)clearPossibleKVO {
    if (_observedPossible) {
        @try {
            [_pipController removeObserver:self forKeyPath:@keypath(self.pipController, pictureInPicturePossible) context:IVTPIPPossibleContext];
            _observedPossible = false;
        } @catch (NSException *exception) {
            LOGError("clear kvo failed", exception);
        }
    }
}

- (void)clearBoundsKVO {
    if (_observedPipBounds) {
        @try {
            [self.pipViewController.view.layer removeObserver:self forKeyPath:@keypath(((CALayer *)nil), bounds) context:IVTPIPVCBoundsContext];
        } @catch (NSException *exception) {
            LOGError("clear kvo failed", exception);
        }
        _observedPipBounds = false;
    }
}

- (void)clearPipPositionKVO {
    if (_observedPipPosition) {
        @try {
            [self.pipViewController.view.layer removeObserver:self forKeyPath:@keypath(((CALayer *)nil), position) context:IVTPIPVCPositionContext];
        } @catch (NSException *exception) {
            LOGError("clear kvo failed", exception);
        }
        _observedPipPosition = false;
    }
}

- (void)clearContentFrameKVO {
    if (_observedContentFrame) {
        @try {
            [_contentView.layer removeObserver:self forKeyPath:@keypath(((CALayer *)nil), bounds) context:IVTPIPContentFrameContext];
        } @catch (NSException *exception) {
            LOGError("clear kvo failed", exception);
        }
        _observedContentFrame = false;
    }
}

- (void)clearKVO {
    [self clearStartedKVO];
    [self clearPossibleKVO];
    [self clearAppStateObserver];
    [self unObserveScreenLock];
    [self clearBoundsKVO];
    [self clearPipPositionKVO];
    [self clearContentFrameKVO];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSString *,id> *)change
                       context:(void *)context {
  
    if (context == IVTPIPPossibleContext) {
        if (_observedPossible) {
            [self startPipSafely];
        }
    } else if (context == IVTPIPSublayersContext) {
        let playerView = _contentView;
        NSArray *subviews = self.pipViewController.view.subviews;
        NSInteger index = [subviews indexOfObject:playerView];
        if (index != NSNotFound && index != subviews.count - 1) {
            [self.pipViewController.view bringSubviewToFront:playerView];
        }
        for (UIView *view in subviews) {
            if (view != playerView) {
                view.alpha = 0;
            }
        }
    } else if (context == IVTPIPContentFrameContext) {
        let pipView = _pipViewController.view;
        if (!CGRectEqualToRect(_contentView.frame, pipView.bounds)) {
            if (_contentView.superview == pipView && !_observedPipPosition) {
                LOGE("abnormal code set content frame to %s", NSStringFromCGRect(_contentView.frame).UTF8String);
                _contentView.frame = pipView.bounds;
            }
        }
    } else if (context == IVTPIPVCBoundsContext){
        CALayer *layer = (CALayer *)object;
        if (_contentView.superview == _pipViewController.view && !_observedPipPosition) {
            _contentView.frame = layer.bounds;
        }
    }
    else if (context == IVTPIPVCPositionContext) {
        CALayer *layer = (CALayer *)object;
        let snapShot = self.playerSnapShot;
        if (!snapShot.frame.size.height) {
            return;
        }
        CGRect frame = layer.frame;
        CGSize snapShotSize = snapShot.frame.size;
        CGFloat ratio = snapShotSize.width / snapShotSize.height;
        //fix 14.0后台回去位置不准的问题, 动画的最终位置必须是0
        if (_restoreType == RestoreFromBackground && _targetBackgroundRestoreArea.origin.y > 0 &&
             frame.origin.y == 0 && frame.size.height > _targetBackgroundRestoreArea.size.height && frame.size.height < UIScreen.mainScreen.bounds.size.height ) {
            frame.size.height = _targetBackgroundRestoreArea.size.height;
        }
        if (ratio > 1) {
            CGRect newFrame = frame;
            newFrame.size.height = frame.size.width / ratio;
            snapShot.frame = newFrame;
            snapShot.center = CGPointMake(frame.size.width / 2, frame.size.height / 2);
        } else {
            CGRect newFrame = frame;
            newFrame.size.width = frame.size.height * ratio;
            snapShot.frame = newFrame;
            snapShot.center = CGPointMake(frame.size.width / 2, frame.size.height / 2);
        }
        if (_contentView.superview == _pipViewController.view) {
            _contentView.frame = snapShot.frame;
            _contentView.center = snapShot.center;
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

NS_INLINE UIView * topMostViewOfView(UIView *view) {
    while (true) {
        UIView *parentView = view.superview;
        if (parentView) {
            view = parentView;
        } else {
            return view;
        }
    }
}

//MARK: Player View creation

- (CGRect)videoOriginalFrame {
    CGRect sourceArea = _sourceArea;
    if (sourceArea.size.width > 0 && sourceArea.size.height > 0) {
        return sourceArea;
    }
    if (_contentView){
        CGRect windowFrame = [topMostViewOfView(_contentView) convertRect:_contentView.bounds fromView:_contentView];
        
        return windowFrame;
    }
    return CGRectZero;
}

- (BOOL)isVisibleAtStart {
    CGRect sourceArea = _sourceArea;
    if (sourceArea.size.width > 0 && sourceArea.size.height > 0) {
        return true;
    }
    return false;
}

static UIWindow * FindKeyWindow(void) {
    if (@available(iOS 13, *)) {
        for(UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) {
                continue;
            }
            if (scene.activationState != UISceneActivationStateForegroundActive) {
                continue;
            }
            for (UIWindow *window in scene.windows) {
                if (window.isKeyWindow) {
                    return window;
                }
            }
        }
    }
    __auto_type window = UIApplication.sharedApplication.keyWindow;
    if (window) {
        return window;
    }
    if ([UIApplication.sharedApplication.delegate respondsToSelector:@selector(window)]) {
        window = UIApplication.sharedApplication.delegate.window;
    }
    return window;
}

static BOOL isValidPipContainerView(UIView *view) {
    if (!view) {
        return false;
    }
    
    if ([view isKindOfClass:UIWindow.class]) {
        return false;
    }
    
    if (@available(iOS 13.0, *)) {
        if (!view.window || view.window.windowScene.activationState != UISceneActivationStateForegroundActive) {
            return false;
        }
    } else {
        if (!view.window) {
            return false;
        }
    }
    
    return true;
}

- (void)preparePlayerView {
    if (_pipPlayer) {
        return;
    }
    
    [self ensureCategory];
    
    CGRect originalFrame = [self videoOriginalFrame];
    //This is required to be valid size for smaple buffer case.
    //AVPlayer can handle this case.
    if (originalFrame.size.width == 0 || originalFrame.size.height == 0) {
        LOGI("set up with empty frame or without view");
        originalFrame.size = UIScreen.mainScreen.bounds.size;
    }
    CGSize videoSize = _videoSize;
    if (videoSize.width == 0 || videoSize.height == 0) {
        videoSize = originalFrame.size;
    }
    if (@available(iOS 15, *)) {
        [self checkEnableSampleBuffer];
        if (_backBySampleBuffer) {
            LOGI("start create sample buffer playerView");
            __auto_type playerView = [[IVTPictureInPictureSampleBufferPlayerView alloc] initWithSize:videoSize duration:_duration];
            if (_duration == 0) {
                playerView.keepSameLiveStyle = _keepSameLiveStyle;
            }
            _pipPlayer = playerView;
        }
    }
    if (!_pipPlayer) {
        LOGI("start create av player  playerView");
        _pipPlayer = [[IVTPictureInPictureAVPlayerView alloc] initWithSize:videoSize duration:_duration];
    }
    _pipPlayer.delegate = self;
    _pipPlayer.frame = originalFrame;
    _pipPlayer.layer.opacity = 0;
    _pipPlayer.autoPauseWhenPlayToEndTime = self.autoPauseWhenPlayToEndTime;
    //为了成功开启小窗,需要将pipPlayer的layer添加到一个可见的view上,不能是UIWindow
    UIView *containerView = self.sourceContainerView;
    if (!isValidPipContainerView(containerView)) {
        UIWindow * mainWindow = FindKeyWindow();
        self.sourceContainerView = containerView = mainWindow.rootViewController.view;
    }
   
    [containerView.layer insertSublayer:_pipPlayer.layer atIndex:0];
    
    [_pipPlayer prepareToPlay];
}

#pragma mark - Setter

- (void)setContentView:(UIView *)contentView {
    assert_main_thread();
    if (_contentView && _contentView.superview == _pipViewController.view) {
        [_contentView removeFromSuperview];
    }
    [self clearContentFrameKVO];
    _contentView = contentView;
    if (_pipViewController && contentView) {
        [_pipViewController.view addSubview:contentView];
    }
}

- (void)setEnableSeek:(BOOL)enableSeek {
    _enableSeek = enableSeek;
    if (@available(iOS 14.0, *)) {
        _pipController.requiresLinearPlayback = !enableSeek;
    }
}

- (void)resetVideoWithCompletion:(void (^)(NSError * _Nullable))completion {
    assert_main_thread();
    CGSize newSize = _videoSize;
    if (newSize.width == 0 || newSize.height == 0) {
        newSize = _sourceArea.size;
    }
    if (!_pipPlayer) {
        !completion ?: completion(nil);
        return;
    }
    [_pipPlayer resetDuration:_duration size:_videoSize completion:^(NSError * error){
        if (!error) {
            [self setupLiveTimer];
        }
        !completion ?: completion(error);
    }];
}

- (void)setStalled:(BOOL)stalled {
    _pipPlayer.stalled = stalled;
}

- (BOOL)stalled {
    return _pipPlayer.stalled;
}

- (void)setRate:(double)rate {
    assert_main_thread();
    if (rate < 0) {
        return;
    }
    _rate = rate;
    if (rate > 0) {
        _speed = rate;
    }
    if ([self canSyncPlaybackStatus:rate != 0]) {
        _pipPlayer.rate = rate;
    }
}

- (void)setSpeed:(double)speed {
    assert_main_thread();
    if (speed <= 0) {
        return;
    }
    if (_rate > 0) {
        [self setRate:speed];
    } else {
        _speed = speed;
    }
}

- (void)play {
    assert_main_thread();
    self.rate = _speed;
}

- (void)pause {
    assert_main_thread();
    self.rate = 0;
}

@synthesize backBySampleBuffer = _backBySampleBuffer;

- (void)setBackBySampleBuffer:(BOOL)backBySampleBuffer {
    if (@available(iOS 15, *)) {
        _backBySampleBuffer = backBySampleBuffer;
    } else {
        LOGI("sample buffer not available");
    }
}

- (BOOL)backBySampleBuffer {
    if (_pipPlayer) {
        return [_pipPlayer isKindOfClass:IVTPictureInPictureSampleBufferPlayerView.class];
    }
    return _backBySampleBuffer;
}

- (void)setkeepSameLiveStyle:(BOOL)keepSameLiveStyle {
    _keepSameLiveStyle = keepSameLiveStyle;
    if (_duration == 0 && [_pipPlayer isKindOfClass:IVTPictureInPictureSampleBufferPlayerView.class]) {
        [(IVTPictureInPictureSampleBufferPlayerView *)_pipPlayer setKeepSameLiveStyle:keepSameLiveStyle];
        [self setupLiveTimer];
    }
}

- (void)checkEnableSampleBuffer {
    if (@available(iOS 16.1, *)) {
        return;
    }
    if (@available(iOS 16, *)) {
        _backBySampleBuffer = _backBySampleBuffer && _controlsHidden;
    }
    return;
}

- (void)setCanStartAutomaticallyFromInline:(BOOL)canStartAutomaticallyFromInline {
    _canStartAutomaticallyFromInline = canStartAutomaticallyFromInline;
    [self configAutomaticallyStart];
}

- (void)setCanPauseWhenExiting:(BOOL)canPauseWhenExiting {
    _canPauseWhenExiting = canPauseWhenExiting;
    [self configCanPauseWhenExiting];
}

- (void)setControlsHidden:(BOOL)controlsHidden {
    _controlsHidden = controlsHidden;
    [self configsControlsHidden];
}

- (void)configsControlsHidden {
    if (!_pipController) {
        return;
    }
    if ([_pipController respondsToSelector:sControlsStyle]) {
        setIntValueForKey(_pipController, sControlsStyle, (long)_controlsHidden);
    }
}

- (void)setSourceArea:(CGRect)sourceArea {
    _sourceArea = sourceArea;
    if (!_started && _pipPlayer) {
        _pipPlayer.frame = [self videoOriginalFrame];
    }
}

- (void)setAutoPauseWhenPlayToEndTime:(BOOL)autoPauseWhenPlayToEndTime {
    _autoPauseWhenPlayToEndTime = autoPauseWhenPlayToEndTime ? 1 : -1;
    _pipPlayer.autoPauseWhenPlayToEndTime = autoPauseWhenPlayToEndTime;
}

- (BOOL)autoPauseWhenPlayToEndTime {
    switch (_autoPauseWhenPlayToEndTime) {
        case 0:
            return !_backBySampleBuffer;
        case 1:
            return true;
        default:
            return false;
    };
}

//MARK: screen Lock

- (void)setAutoPauseWhenScreenLocked:(BOOL)autoPauseWhenScreenLocked {
    _autoPauseWhenScreenLocked = autoPauseWhenScreenLocked;
    if (!autoPauseWhenScreenLocked) {
        [self unObserveScreenLock];
    }
}

static void ScreenLockCallback(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
    [(__bridge IVTPictureInPictureController *)observer screenLockStateChanged];
}

static NSString * ScreenLockNoteName(void) {
    const char *nameList[] = {"com", ".apple", ".springboard", ".lock", "state"};
    char buffer[128];
    concatString(buffer, nameList, 5);
    return (__bridge_transfer NSString *)CFStringCreateWithCString(kCFAllocatorDefault, buffer, NSASCIIStringEncoding);
}

- (void)observeScreenLock  {
    if (_autoPauseWhenScreenLocked && !_screenLockObserved && _isActive) {
        LOGI("screen lock observed");
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, ScreenLockCallback, (__bridge CFStringRef)ScreenLockNoteName(), nil, 0);
        _screenLockObserved = true;
    }
}

- (void)unObserveScreenLock {
    if(_screenLockObserved) {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, (__bridge CFStringRef)ScreenLockNoteName(), nil);
        _screenLockObserved = false;
        _screenLocked = false;
        _pausedWhenScreenLocked = false;
    }
}

- (void)screenLockStateChanged {
    _screenLocked = !_screenLocked;
    LOGI("screen locked %d", _screenLocked);
    if (_screenLocked) {
        if (_autoPauseWhenScreenLocked && self.rate > 0) {
            _pausedWhenScreenLocked = true;
            self.rate = 0;
        }
    } else if (_pausedWhenScreenLocked) {
        _pausedWhenScreenLocked = false;
        if (_autoResumeWhenScreenUnlocked) {
            [self play];
        }
    }
}

//MARK: Progress modification

- (void)seekToTime:(NSTimeInterval)time {
    assert_main_thread();
    [_pipPlayer seekToTime:time];
}

- (void)syncProgress {
    assert_main_thread();
    [_pipPlayer syncProgress];
}

- (void)skipByInterval:(double)skip {
    bool shouldPlayAgain = false;
    //case for loop play;
    if (self.rate > 0 && skip + [self currentPlaybackTime] > self.duration) {
        [self pause];
        shouldPlayAgain = true;
    }
    [_pipPlayer skipByInterval:skip completion:^{
        if (shouldPlayAgain) {
            [self play];
        }
    }];
}

static IMP sOriginalDidReceivePlaybackCommandIMP;

static void newDidReceivePlaybackCommandIMP(__unsafe_unretained id self, SEL cmd, id proxy, id<IVTPGCommand> playbackCommand) {
    ((void(*)(id, SEL, id, id))sOriginalDidReceivePlaybackCommandIMP)(self, cmd, proxy, playbackCommand);
    @try {
        if (playbackCommand.playbackAction == IVTPGCommandPlaybackActionSeek){
            double skip = playbackCommand.associatedDoubleValue;
            dispatch_async(dispatch_get_main_queue(), ^{
                IVTPictureInPictureController *controller = sCurrentInstance;
                if (controller && !controller.backBySampleBuffer) {
                    [controller skipByInterval:skip];
                }
            });
        }
    } @catch (...) {
        
    }
}

- (BOOL)addSeekMethodHook {
    id platformAdapter = [self pipPlatformAdapter];
    if (!platformAdapter) {
        return false;
    }
    @try {
        static SEL hookTarget = nil;
        if (!hookTarget) {
            hookTarget = @selector(pictureInPictureProxy:didReceivePlaybackCommand:);
            if (![platformAdapter respondsToSelector:hookTarget]) {
                return false;
            }
            sOriginalDidReceivePlaybackCommandIMP = class_replaceMethod([platformAdapter class], hookTarget, (IMP)newDidReceivePlaybackCommandIMP, "v32@0:8@16@24");
        }
        return sOriginalDidReceivePlaybackCommandIMP != nil;
    } @catch (...) {
        return false;
    }
    
    return false;
}

- (void)monitorSeekEvents {
    if (_backBySampleBuffer) {
        return;
    }
    if ([self addSeekMethodHook]) {
        LOGI("seek hook added");
        return;
    }
    [self.pipPlayer monitorSeekEvents];
}

#pragma mark - Scene switch

static id sScene;

- (void)enterScene:(NSObject *)scene {
    if (_pipController.isPictureInPictureActive && !sScene) {
        if ([_delegate respondsToSelector:@selector(pictureInPictureController:enterScene:)]) {
            if ([_delegate pictureInPictureController:self enterScene:scene]) {
                sScene = scene;
            }
        }
    }
}

- (void)leaveScene:(NSObject *)scene {
    if (scene == sScene) {
        if ([_delegate respondsToSelector:@selector(pictureInPictureController:leaveScene:)]) {
            [_delegate pictureInPictureController:self leaveScene:scene];
        }
        sScene = nil;
    }
}

+ (void)enterScene:(NSObject *)scene {
    let controller =  IVTPictureInPictureController.currentInstance;
    if (controller.started && !sScene) {
        let delegate = controller.delegate;
        if ([delegate respondsToSelector:@selector(pictureInPictureController:enterScene:)]) {
            if ([delegate pictureInPictureController:controller enterScene:scene]) {
                sScene = scene;
            }
        }
    }
}

+ (void)leaveScene:(NSObject *)scene {
    if (scene == sScene) {
        let delegate = IVTPictureInPictureController.currentInstance.delegate;
        if ([delegate respondsToSelector:@selector(pictureInPictureController:leaveScene:)]) {
            [delegate pictureInPictureController:IVTPictureInPictureController.currentInstance leaveScene:scene];
        }
        sScene = nil;
    }
}


@end



