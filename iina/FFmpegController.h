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
- (void)didUpdatedThumbnails:(nullable NSArray<FFThumbnail *> *)thumbnails withProgress:(NSInteger)progress;

/** 
 Did generated thumbnails for the video.
 */
- (void)didGeneratedThumbnails:(nonnull NSArray<FFThumbnail *> *)thumbnails succeeded:(BOOL)succeeded;

@end


@interface FFmpegController: NSObject

@property(nonatomic, weak) id<FFmpegControllerDelegate> _Nullable delegate;

@property(nonatomic) NSInteger thumbnailCount;

- (void)generateThumbnailForFile:(nonnull NSString *)file;

@end
