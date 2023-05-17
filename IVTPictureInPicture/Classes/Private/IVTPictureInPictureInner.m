//
//  IVTPictureInPicturePlayerView.m
//  pictureInPicture
//
//

#import "IVTPictureInPictureInner.h"
#import <sys/sysctl.h>

void(^IVTPictureInPictureLogCallaback)(NSUInteger level, const char *tag, const char *log);

void IVTPictureInPictureLog(int level, const char *format, ...) {
    __auto_type callback = IVTPictureInPictureLogCallaback;
    if (callback != nil) {
        char buffer[2048];
        va_list args;
        va_start(args, format);
        vsnprintf(buffer, 2048, format, args);
        va_end(args);
        callback(level, IVTPictureInPictureTag, buffer);
    }
    char buffer[2048];
    static const int MAX_TIME_STRING_BUF = 20;
    struct timeval current_time;
    struct tm *time_info;
    
    // 获取当前时间
    gettimeofday(&current_time, NULL);
    
    // 将当前时间转换为本地时间
    time_info = localtime(&current_time.tv_sec);

    char timeString[MAX_TIME_STRING_BUF];
    //"%Y-%m-%d %H:%M:%S"
    if (strftime(timeString, MAX_TIME_STRING_BUF, "%F %T", time_info) < 0) {
        timeString[0] = 0;
    }
    
    int prefixLength = snprintf(buffer, 2047, "%s.%06d [%s] ", timeString, (int)current_time.tv_usec, IVTPictureInPictureTag);
    if (prefixLength < 0) {
        prefixLength = 0;
    }
    va_list args;
    va_start(args, format);
    vsnprintf(buffer + prefixLength, 2047 - prefixLength, format, args);
    va_end(args);
    printf("%s\n", buffer);
}

///A10（iphone 7）以下最小16，A10以上最小6
extern CGSize IVTPIPCompressSize(CGSize originalSize) {
    CGSize newSize = CGSizeZero;
    CGFloat originalSizeScale = originalSize.height / originalSize.width;
    CGFloat sizeScale169 = 9.0 / 16.0;
    CGFloat sizeScale43 = 3.0 / 4.0;
    CGFloat tolerance = 0.001;//允许的误差
    
    CGFloat diff169 = fabs(originalSizeScale - sizeScale169);
    CGFloat diff43 = fabs(originalSizeScale - sizeScale43);
    
    if (diff169 < tolerance) {
        //在允许范围内满足 width:height = 16:9
        newSize.width = 16;
        newSize.height = 9;
        LOGI("hit 16:9");
    } else if (diff43 < tolerance) {
        //在允许范围内满足 width:height = 4:3
        newSize.width = 8;
        newSize.height = 6;
        LOGI("hit 4:3");
    } else {
        
        CGFloat scaleFactor = originalSize.height / originalSize.width;
        int startV = 6;
        if (scaleFactor < 1) {
            startV = (int)ceil(6 / scaleFactor);
        }
        int bestWidth = startV;
        CGFloat bestHeight = (int)(startV * scaleFactor);
        CGFloat bestScale = bestWidth / bestHeight;
        for (int i = startV; i < 30; i++) {
            CGFloat height = (int)(i * scaleFactor);
            CGFloat realScale = height / i;
            if (fabs(realScale - scaleFactor) < tolerance) {
                bestWidth = i;
                bestHeight = height;
                bestScale = realScale;
                break;
            }
            if (fabs(realScale - scaleFactor) < fabs(bestScale - scaleFactor)) {
                bestWidth = i;
                bestHeight = height;
                bestScale = realScale;
            }
            height = ceil(i * scaleFactor);
            realScale = height / i;
            if (fabs(realScale - scaleFactor) < tolerance) {
                bestWidth = i;
                bestHeight = height;
                bestScale = realScale;
                break;
            }
            if (fabs(realScale - scaleFactor) < fabs(bestScale - scaleFactor)) {
                bestWidth = i;
                bestHeight = height;
                bestScale = realScale;
            }
        }
        newSize.width = bestWidth;
        newSize.height = bestHeight;
        LOGI("hit size %d:%d", bestWidth, (int)bestHeight);
    }
    static BOOL isLowDevice;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        char platform[50];
        size_t size = 50;
        sysctlbyname("hw.machine", platform, &size, NULL, 0);
        
        if (strncmp(platform, "iPhone", 6) == 0) {
            if (atoi(&platform[6]) <  9) { //iPhone 7 lower
                isLowDevice = true;
            }
        } else if (strncmp(platform, "iPad", 4) == 0) {
            if (atoi(&platform[4]) <= 6) { //iPad Pro and lower
                isLowDevice = true;
            }
        }
    });
    
    if (isLowDevice) {
        double min = MIN(newSize.width, newSize.height);
        if (min < 16) {
            double scale = ceil(16 / min);
            newSize.width *= scale;
            newSize.height *= scale;
        }
    }
    
    return newSize;
}
