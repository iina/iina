//
//  FFmpegController.h
//  iina
//
//  Created by Saagar Jha on 2/16/19.
//  Copyright © 2019 lhc. All rights reserved.
//

#ifndef FFmpegController_h
#define FFmpegController_h

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

// Dummy interface for the Swift parts of FFmpegController we want to call.
@interface FFmpegController : NSObject
- (void)saveWithThumbnail:(nullable void *)thumbnail width:(NSInteger)width height:(NSInteger)height index:(NSInteger)index timestamp:(NSInteger)timestamp forFileAtPath:(NSString *)path;
- (BOOL)handleNewTimestamp:(int64_t)timestamp progress:(NSInteger)progress forFileAtPath:(NSString *)path;
@end

// Additional bits that we add in Objective-C++.
@interface FFmpegController (Bridge)
- (BOOL)synchronouslyGenerateThumbnailsForFileAtPath:(NSString *)path;
+ (double)videoDurationForFileAtPath:(NSString *)path NS_SWIFT_NAME(videoDuration(forFileAtPath:));
@end

NS_ASSUME_NONNULL_END

#endif /* FFmpegController_h */
