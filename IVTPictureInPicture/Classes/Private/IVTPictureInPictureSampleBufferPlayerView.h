//
//  IVTPictureInPictureSampleBufferPlayerView.h
//  IVTPictureInPicture
//
//  Created by osl on 2023/5/12.
//

#import <UIKit/UIKit.h>
#import "IVTPictureInPicturePlayerView.h"

NS_ASSUME_NONNULL_BEGIN


@interface IVTPictureInPictureSampleBufferPlayerView : NSObject<IVTPictureInPicturePlayerView, AVPictureInPictureSampleBufferPlaybackDelegate>

@property (nonatomic, assign) bool keepSameLiveStyle;

@end

NS_ASSUME_NONNULL_END
