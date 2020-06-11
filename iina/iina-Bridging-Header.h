#define MPV_ENABLE_DEPRECATED 0

#import <mpv/client.h>
#import <mpv/render.h>
#import <mpv/render_gl.h>

#import <stdio.h>
#import <stdlib.h>
#import "FixedFontManager.h"
#import "ObjcUtils.h"
#import "FFmpegController.h"

#import <CommonCrypto/CommonCrypto.h>

#import <Availability.h>

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
// it seems the system doesn't call this function since macOS 10.15
- (BOOL)pipShouldClose:(PIPViewController *)pip __OSX_AVAILABLE_STARTING(__MAC_10_12,__IPHONE_NA);
// instead this is added in macOS 10.15
- (void)pipWillClose:(PIPViewController *)pip __OSX_AVAILABLE_STARTING(__MAC_10_12,__IPHONE_NA);
- (void)pipDidClose:(PIPViewController *)pip __OSX_AVAILABLE_STARTING(__MAC_10_12,__IPHONE_NA);
- (void)pipActionPlay:(PIPViewController *)pip __OSX_AVAILABLE_STARTING(__MAC_10_12,__IPHONE_NA);
- (void)pipActionPause:(PIPViewController *)pip __OSX_AVAILABLE_STARTING(__MAC_10_12,__IPHONE_NA);
- (void)pipActionStop:(PIPViewController *)pip __OSX_AVAILABLE_STARTING(__MAC_10_12,__IPHONE_NA);
@end

NS_ASSUME_NONNULL_END
