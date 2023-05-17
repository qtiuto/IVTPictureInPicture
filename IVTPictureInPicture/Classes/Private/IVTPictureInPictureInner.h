//
//  IVTPictureInPictureInner.h
//  Pods
//
//  Created by osl on 2023/5/12.
//

#ifndef IVTPictureInPictureInner_h
#define IVTPictureInPictureInner_h
#import <pthread/pthread.h>
#import <assert.h>

NS_ASSUME_NONNULL_BEGIN

#define IVTPictureInPictureTag "IVTPictureInPicture"

#define IVTDefaultLiveDuration 120

extern  void(^IVTPictureInPictureLogCallaback)(NSUInteger level,const char *tag, const char *log);

extern void IVTPictureInPictureLog(int level, const char *format, ...);

#define LOGI(format, ...) IVTPictureInPictureLog(1, format, ##__VA_ARGS__)
#define LOGE(format, ...) IVTPictureInPictureLog(3, format, ##__VA_ARGS__)

#ifdef DEBUG
#define assert_main_thread() assert(__PRETTY_FUNCTION__ && "must be called on main thread" && pthread_main_np())
#else
#define assert_main_thread()
#endif

NS_INLINE void LOGError(char *info, id error)  {
    char buffer[2048];
    buffer[0] = 0;
    CFStringRef errorDesc = CFCopyDescription((__bridge CFTreeRef)error);
    if (errorDesc){
        CFStringGetCString(errorDesc, buffer, 2048, kCFStringEncodingUTF8);
        CFRelease(errorDesc);
    }
    LOGE("%s:%s", info, buffer);
}


extern CGSize IVTPIPCompressSize(CGSize originalSize);

NS_INLINE void runOnMainThread(void (^ _Nullable block)(void)) {
    if (!block) {
        return;
    }
    if (pthread_main_np()) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}
extern void objc_msgSend(void);

NS_INLINE id objectValueForKey(_Nullable __unsafe_unretained id self, SEL selector) {
    return ((id(*)(id, SEL))objc_msgSend)(self, selector);
}

NS_INLINE double doubleValueForKey(_Nullable __unsafe_unretained id self, SEL selector) {
    return ((double(*)(id, SEL))objc_msgSend)(self, selector);
}

NS_INLINE BOOL boolValueForKey(_Nullable __unsafe_unretained id self, SEL selector) {
    return ((BOOL(*)(id, SEL))objc_msgSend)(self, selector);
}

NS_INLINE void setIntValueForKey(_Nullable __unsafe_unretained id self, SEL selector, int64_t value) {
     ((void(*)(id, SEL, int64_t))objc_msgSend)(self, selector, value);
}

NS_INLINE void concatString(char *outStr, const char *_Nonnull * _Nonnull list, int count) {
    outStr[0] = 0;
    for (int i = 0; i < count; ++i) {
        strcat(outStr, list[i]);
    }
}

NS_INLINE void enumerateVisibleLayers(CALayer *layer,  void(^ _Nonnull callback)(CALayer *layer)) {
    @autoreleasepool {
        if (layer.isHidden) {
            return;
        }
        CGRect frame = layer.frame;
        if (frame.size.width <= 0.000001 || frame.size.height <= 0.00001) {
            return;
        }
        if (layer.opacity <= 0.000001) {
            return;
        }
        callback(layer);
        for (CALayer *sublayer in layer.sublayers){
            enumerateVisibleLayers(sublayer, callback);
        };
    }
}

NS_ASSUME_NONNULL_END

#endif /* IVTPictureInPictureInner_h */
