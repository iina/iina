#import <mpv/client.h>
#import <mpv/opengl_cb.h>
#import <stdio.h>
#import <stdlib.h>
#import "FixedFontManager.h"
#import "ObjcUtils.h"
#import <MASPreferences/MASPreferencesViewController.h>

#import <CommonCrypto/CommonCrypto.h>

#import <Availability.h>

#import "SPMediaKeyTap.h"

#pragma mark - PIP.framework

NS_ASSUME_NONNULL_BEGIN

@protocol PIPViewControllerDelegate;

@interface PIPViewController : NSViewController

@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, weak, nullable) id<PIPViewControllerDelegate> delegate;
@property (nonatomic, weak, nullable) NSWindow *replacementWindow;
@property (nonatomic) NSRect replacementRect;
@property (nonatomic) bool playing;
@property (nonatomic) bool userCanResize;
@property (nonatomic) NSSize aspectRatio;

- (void)presentViewControllerAsPictureInPicture:(NSViewController * _Nonnull)viewController;

@end

@protocol PIPViewControllerDelegate <NSObject>

@optional
- (BOOL)pipShouldClose:(PIPViewController * _Nonnull)pip __OSX_AVAILABLE_STARTING(__MAC_10_12,__IPHONE_NA);
- (void)pipDidClose:(PIPViewController * _Nonnull)pip __OSX_AVAILABLE_STARTING(__MAC_10_12,__IPHONE_NA);
- (void)pipActionPlay:(PIPViewController * _Nonnull)pip __OSX_AVAILABLE_STARTING(__MAC_10_12,__IPHONE_NA);
- (void)pipActionPause:(PIPViewController * _Nonnull)pip __OSX_AVAILABLE_STARTING(__MAC_10_12,__IPHONE_NA);
- (void)pipActionStop:(PIPViewController * _Nonnull)pip __OSX_AVAILABLE_STARTING(__MAC_10_12,__IPHONE_NA);
@end

NS_ASSUME_NONNULL_END
