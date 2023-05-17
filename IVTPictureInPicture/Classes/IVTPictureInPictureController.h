//
//  TTVPictureInPictureController.h
//  TTVideoBusiness
//

#import <Foundation/Foundation.h>
#import <AVKit/AVKit.h>
#import <AVKit/AVKitDefines.h>

NS_ASSUME_NONNULL_BEGIN
@protocol IVTPictureInPictureControllerDelegate;

typedef enum : NSUInteger {
    IVTPictureInPicturePaused,
    IVTPictureInPicturePlaying,
} IVTPictureInPicturePlaybackStatus;

typedef enum : NSUInteger {
    IVTPictureInPictureLogLevelDebug = 0,
    IVTPictureInPictureLogLevelInfo = 1,
    IVTPictureInPictureLogLevelWarn = 2,
    IVTPictureInPictureLogLevelError = 3,
} IVTPictureInPictureLogLevel;

@interface AVPlayerLayer (PipHelper)

///AVPlayerLayer是否可以进行后台渲染
@property (nonatomic) BOOL pictureInPictureModeEnabled;

@end

/**
 画中画(悬浮窗 , 小窗)控制器
 */
@interface IVTPictureInPictureController : NSObject

///当前显示的小窗
+ (instancetype)currentInstance;
///是否支持画中画功能,如果该值为NO,则画中画相关方法不应被使用
+ (BOOL)isPictureInPictureSupported;
///小窗是否正在使用
+ (BOOL)isActive;

///允许后台使用GPU进行计算
+ (void)enableBackgroundGPUUsage;

@property (nonatomic, class) void(^logCallback)(IVTPictureInPictureLogLevel logLevel, const char *tag, const char *log);

///当前需要显示在小窗内的view, 用于承载小窗内容。
@property (nonatomic, nullable) UIView *contentView;

///通常指contentView在应用内的原本container，只作为sourceArea，targtFadeOutArea, targetBackgroundRestoreArea，targetForegroundRestoreArea的frame参考view
///必须在activeWindow上
///为空或者无效表示是主UIWindow.rootViewController.view
@property (nonatomic, nullable) UIView *sourceContainerView;

///画中画代理
@property (nonatomic, nullable, weak) id<IVTPictureInPictureControllerDelegate> delegate;

///小窗的视频长度，定长视频允许seek的情况下必须设置。
///小窗改变视频长度会使小窗的进度归零
@property (nonatomic) NSTimeInterval duration;

/// 小窗的尺寸，当其不为CGSizeZero时，小窗的尺寸比例与其相同，否则使用sourceArea的尺寸，
/// 当sourceArea的尺寸为CGSizeZero时使用videoPlayView的尺寸
@property (nonatomic) CGSize videoSize;

///是否显示前进后退15s按钮,默认不显示
@property (nonatomic) BOOL enableSeek;

///是否通过sampleBufferDisplayLayer生成小窗，14 false， 15+ true
@property (nonatomic) BOOL backBySampleBuffer;

///保持直播情况的小窗的样式为AVPlayer的版本
@property (nonatomic) BOOL keepSameLiveStyle;

///是否进入进入其他app，返回桌面时自动打开小窗
@property (nonatomic) BOOL canStartAutomaticallyFromInline;
///是否隐藏播放按钮和进度条，开启后所有播放按钮都不再显示
///@Note 自iOS16.2开始，添加的view不再收到任何触摸事件
@property (nonatomic) BOOL controlsHidden;

///小窗关闭时是否暂停当前播放源，默认关, 不影响小窗返回
@property (nonatomic) BOOL canPauseWhenExiting;
///锁屏后自动暂停，, 只有在小窗打开前设置才会生效
///ios 14 这个feature一直是开的，15后可以选择性打开
@property (nonatomic) BOOL autoPauseWhenScreenLocked;
///解锁后是否继续播放， 默认关
@property (nonatomic) BOOL autoResumeWhenScreenUnlocked;
/// 当前锁屏锁屏状态，仅autoPauseWhenScreenLocked 打开生效且小窗显示时失效， KVO不生效。
@property (nonatomic) BOOL screenLocked;
///app被杀死时回调stop
@property (nonatomic) BOOL notifyStopWhenTerminated;

///视频播放到结尾时是否自动暂停，默认backBySampleBuffer 的情况下关闭，反之打开
@property (nonatomic) BOOL autoPauseWhenPlayToEndTime;

///是否自动启用后台渲染，避免GPU的任务被打断
@property (nonatomic) BOOL autoEnableBackgroundRendering;

///播放器在当前屏幕上的位置，CGRectZero的情况画中画会从最终位置的中心弹出，
///其他情况下小窗画中画会从该位置弹出
///相对于sourceView
@property (nonatomic) CGRect sourceArea;
///小窗消失时的最终位置, CGRectZero的情况画中画会从消失开始位置的中心消失
///相对于sourceContainerView
@property (nonatomic) CGRect targetFadeOutArea;
///小窗前台返回时的最终位置, CGRectZero的情况画中画会从消失开始位置的中心消失
///相对于sourceContainerView
@property (nonatomic) CGRect targetForegroundRestoreArea;
///小窗后台返回时的最终位置, CGRectZero的情况画中画会从消失开始位置的中心消失
///相对于sourceContainerView
@property (nonatomic) CGRect targetBackgroundRestoreArea;

///开启小窗
- (void)startPictureInPicture;

///提前创建小窗，可设置canStartAutomaticallyFromInline = true 使得系统在进入后台时自动打开小窗 或者手动调用startPictureInPicture打开小窗
- (void)preparePictureInPicture;

///停止小窗, 如果当前小窗是隐藏状态会不会再恢复
- (void)stopPictureInPicture;

///停止小窗并触发恢复方法
- (void)stopAndRestore;

///如果需要上一个小窗和下一个小窗之间流畅切换，清调用此方法，并在block回调后在开启小窗
- (void)stopWithFinishBlock:(nullable dispatch_block_t)block;

///当小窗的视频时长/尺寸比例发生改变时，调用该方法重置小窗UI，播放进度会被重置为0
- (void)resetVideoWithCompletion:(nullable void(^)(NSError * _Nullable error))completion;


//MARK: - Player Sync
///播放速率, 0的情况视为暂停, 非0视为播放
@property (nonatomic) double rate;
///纯播放速度
@property (nonatomic) double speed;
///开始播放
- (void)play;
///暂停播放,
- (void)pause;

///是否卡顿了
@property (nonatomic) BOOL stalled;
///播放器主动seek
- (void)seekToTime:(NSTimeInterval)time;
///同步播放器的进度和小窗的进度
- (void)syncProgress;

//MARK: -Stautus
//小窗释放是在展示中
- (BOOL)isActive;

//MARK: - Resume PictureInPicture
///小窗恢复场景(暂时隐藏小窗而后恢复小窗,中间无需再手动设置小窗属性)
///若在隐藏小窗期间改变了小窗源,则小窗数据均清空并不再可恢复
@property (nonatomic, readonly) BOOL isResumable;
///隐藏小窗，不暂停播放，不改变播放状态
- (void)hide;
- (void)resume;
///隐藏小窗并暂停播放，还原后恢复原播放器状态
- (void)hideAndPause;

//MARK: Readonly State
///是否在后台台返回前台的过程中
@property (nonatomic, readonly) BOOL isRestoringFromBackground;

//MARK: - Scene switch
///小窗进入了某个场景，对scene强引用
+ (void)enterScene:(NSObject *)scene;
///小窗退出了某个场景，如果scene相同，清除对scene的引用
+ (void)leaveScene:(NSObject *)scene;

@end


@protocol IVTPictureInPictureControllerDelegate <NSObject>

@optional
/// 小窗即将打开
/// @param controller 小窗
- (void)pictureInPictureControllerWillStart:(IVTPictureInPictureController *)controller;

/// 小窗完全打开，动画结束
/// @param controller 小窗
- (void)pictureInPictureControllerDidStart:(IVTPictureInPictureController *)controller;

/// 小窗打开失败
/// @param controller 小窗
/// @param error 错误对象
- (void)pictureInPictureController:(IVTPictureInPictureController *)controller failedToStartWithError:(NSError *)error;

/// 关闭小窗和小窗返回均会调用
/// @param controller 小窗
/// @param isRestore isRestore=YES 说明是小窗返回，否则时正常小窗关闭
- (void)pictureInPictureController:(IVTPictureInPictureController *)controller willStopForRestore:(BOOL)isRestore;
///关闭小窗和小窗返回均会调用，小窗完全消失，动画结束
- (void)pictureInPictureController:(IVTPictureInPictureController *)controller didStopForRestore:(BOOL)isRestore;

/// 若需要自定义场景恢复,则实现此方法，小窗点击返回按钮时会触发
/// @param controller 小窗
/// @param isForeground 是否前台返回
- (void)pictureInPictureController:(IVTPictureInPictureController *)controller restoreFromForeground:(BOOL)isForeground;

/// 小窗即将返回前台时处理
/// @param controller 小窗
/// @param isForeground 是否前台返回 
- (void)pictureInPictureController:(IVTPictureInPictureController *)controller willRestoreFromForeground:(BOOL)isForeground;

/// 小窗播放状态变化时调用
/// @param controller 小窗
/// @param playing 小窗的播放状态，暂停或者播放中
- (void)pictureInPictureController:(IVTPictureInPictureController *)controller isPlaying:(BOOL)playing;

/// 当 enableSeek=YES 时才生效
/// @param controller 小窗
/// @param seekToTime 当前时间
/// @param completion 跳转结束回调
- (void)pictureInPictureController:(IVTPictureInPictureController *)controller seekToTime:(NSTimeInterval)seekToTime completion:(nullable void(^)(void))completion;

/// 返回当前播放器的时间
/// @param controller 小窗
- (NSTimeInterval)currentPlaybackTimeOfPictureInPictureController:(IVTPictureInPictureController *)controller;

/// 小窗进入某个场景
/// @param controller 小窗
/// @param scene 场景的描述对象
- (BOOL)pictureInPictureController:(IVTPictureInPictureController *)controller enterScene:(NSObject *)scene;

/// 小窗离开某个场景
/// @param controller 小窗
/// @param scene 场景的描述对象
- (void)pictureInPictureController:(IVTPictureInPictureController *)controller leaveScene:(NSObject *)scene;

@end

NS_ASSUME_NONNULL_END
