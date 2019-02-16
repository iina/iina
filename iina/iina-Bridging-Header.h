#import <Availability.h>
#import <CommonCrypto/CommonCrypto.h>

#pragma mark - MPV

#define MPV_ENABLE_DEPRECATED 0

#import <mpv/client.h>
#import <mpv/render.h>
#import <mpv/render_gl.h>

#pragma mark - FFmpeg

#import <libavcodec/avcodec.h>
#import <libavformat/avformat.h>
#import <libswscale/swscale.h>
#import <libavutil/avutil.h>
#import <libavutil/imgutils.h>

// Unfortunately, these two are declared as macros in such a way that they can't
// be used in Swift-thus, we need to wrap them.
AVRational avTimeBaseQ = AV_TIME_BASE_Q;

int averror(int error) {
  return AVERROR(error);
}

#pragma mark - IINA

#import "FixedFontManager.h"
#import "ObjcUtils.h"

#pragma mark - PIP.framework

NS_ASSUME_NONNULL_BEGIN

@protocol PIPViewControllerDelegate;

@interface PIPViewController : NSViewController

@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, weak, nullable) id<PIPViewControllerDelegate> delegate;
@property (nonatomic, weak, nullable) NSWindow *replacementWindow;
@property (nonatomic) NSRect replacementRect;
@property (nonatomic) bool playing;
@property (nonatomic) NSSize aspectRatio;

- (void)presentViewControllerAsPictureInPicture:(NSViewController *)viewController;

@end

@protocol PIPViewControllerDelegate <NSObject>

@optional
- (BOOL)pipShouldClose:(PIPViewController *)pip __OSX_AVAILABLE_STARTING(__MAC_10_12,__IPHONE_NA);
- (void)pipDidClose:(PIPViewController *)pip __OSX_AVAILABLE_STARTING(__MAC_10_12,__IPHONE_NA);
- (void)pipActionPlay:(PIPViewController *)pip __OSX_AVAILABLE_STARTING(__MAC_10_12,__IPHONE_NA);
- (void)pipActionPause:(PIPViewController *)pip __OSX_AVAILABLE_STARTING(__MAC_10_12,__IPHONE_NA);
- (void)pipActionStop:(PIPViewController *)pip __OSX_AVAILABLE_STARTING(__MAC_10_12,__IPHONE_NA);
@end

NS_ASSUME_NONNULL_END
