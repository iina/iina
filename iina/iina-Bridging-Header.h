#import <mpv/client.h>
#import <mpv/opengl_cb.h>
#import <stdio.h>
#import <stdlib.h>
#import "FixedFontManager.h"
#import "ObjcUtils.h"
#import <MASPreferences/MASPreferencesViewController.h>

#import <CommonCrypto/CommonCrypto.h>

#pragma mark - PIP.framework

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
- (BOOL)pipShouldClose:(PIPViewController * _Nonnull)pip;
- (void)pipDidClose:(PIPViewController * _Nonnull)pip;
- (void)pipActionPlay:(PIPViewController * _Nonnull)pip;
- (void)pipActionPause:(PIPViewController * _Nonnull)pip;
- (void)pipActionStop:(PIPViewController * _Nonnull)pip;

@end
