#define MPV_ENABLE_DEPRECATED 0

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#import <mpv/client.h>
#import <mpv/render.h>
#import <mpv/render_gl.h>

#import <libavcodec/avcodec.h>
#import <libavformat/avformat.h>
#import <libavutil/avutil.h>
#import <libswscale/swscale.h>
#pragma clang diagnostic pop

#import <stdio.h>
#import <stdlib.h>
#import "FixedFontManager.h"
#import "ObjcUtils.h"
#import "FFmpegController.h"

#import <CommonCrypto/CommonCrypto.h>

#import <Availability.h>

#pragma mark - CoreDisplay.framework

extern CFDictionaryRef _Nullable CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID display);

#pragma mark - PIP.framework

NS_ASSUME_NONNULL_BEGIN

@protocol PIPViewControllerDelegate;
@class PIPMutablePlaybackState;

@interface PIPViewController : NSViewController

@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, weak, nullable) id<PIPViewControllerDelegate> delegate;
@property (nonatomic, weak, nullable) NSWindow *replacementWindow;
@property (nonatomic) NSRect replacementRect;
@property (nonatomic) bool playing;
@property (nonatomic) NSSize aspectRatio;

- (void)presentViewControllerAsPictureInPicture:(NSViewController *)viewController;
- (void)updatePlaybackStateUsingBlock:(void (NS_NOESCAPE ^)(PIPMutablePlaybackState *))updateBlock;

@end

@interface PIPPlaybackState : NSObject
@end

@interface PIPMutablePlaybackState : PIPPlaybackState
@property (nonatomic) NSTimeInterval contentDuration;
@property (nonatomic) NSInteger contentType;
- (void)setPlaybackRate:(double)playbackRate elapsedTime:(NSTimeInterval)elapsedTime timeControlStatus:(NSInteger)timeControlStatus;
@end

@protocol PIPViewControllerDelegate <NSObject>

@optional
- (void)pipWillClose:(PIPViewController *)pip;
- (void)pipDidClose:(PIPViewController *)pip;
- (void)pipActionPlay:(PIPViewController *)pip;
- (void)pipActionPause:(PIPViewController *)pip;
- (void)pipActionStop:(PIPViewController *)pip;
- (void)pipAction:(PIPViewController *)pip skipInterval:(NSTimeInterval)interval;
@end

NS_ASSUME_NONNULL_END
