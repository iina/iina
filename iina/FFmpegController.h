//
//  FFmpegController.h
//  iina
//
//  Created by lhc on 9/6/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface FFThumbnail: NSObject

@property(nonatomic) NSImage * _Nullable image;
@property(nonatomic) double realTime;

@end


@protocol FFmpegControllerDelegate <NSObject>

/**
 A notification being sent
 */
- (void)didUpdateThumbnails:(nullable NSArray<FFThumbnail *> *)thumbnails forFile:(nonnull NSString *)filename withProgress:(NSInteger)progress;

/**
 Did generated thumbnails for the video.
 */
- (void)didGenerateThumbnails:(nonnull NSArray<FFThumbnail *> *)thumbnails forFile:(nonnull NSString *)filename succeeded:(BOOL)succeeded;

@end


@interface FFmpegController: NSObject

@property(nonatomic, weak) id<FFmpegControllerDelegate> _Nullable delegate;

@property(nonatomic) NSInteger thumbnailCount;

/// Initializes and returns an image object with the contents of the specified URL
///
/// At this time, the normal [NSImage](https://developer.apple.com/documentation/appkit/nsimage/1519907-init)
/// initializer will fail to create an image object if the image file was encoded in [JPEG XL](https://jpeg.org/jpegxl/) format.
/// In older versions of macOS this will also occur if the image file was encoded in [WebP](https://en.wikipedia.org/wiki/WebP/)
/// format. As these are supported formats for screenshots it is desirable to have an alternative method for creating image objects that
/// supports these formats so that a screenshot preview can be displayed as is done for other screenshot formats. This method is
/// intended to be used when the normal AppKit supplied initializer is unable to create an image.
/// - Attention: This method only supports decoding JPEG XL and WebP encoded images. It is not intended to replace the normal
///       AppKit supplied initializer.
/// - Parameter url: The URL identifying the image.
/// - Returns: An initialized NSImage object or null if the method cannot create an image representation from the contents of the
///       specified URL.
+ (nullable NSImage *)createNSImageWithContentsOfURL:(nonnull NSURL *)url;

- (void)generateThumbnailForFile:(nonnull NSString *)file
                      thumbWidth:(int)thumbWidth;

+ (nullable NSDictionary *)probeVideoInfoForFile:(nonnull NSString *)file;

@end
