//
//  FFmpegController.h
//  iina
//
//  Created by lhc on 9/6/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol FFmpegControllerDelegate <NSObject>

/** 
 Did generated thumbnails for the video.
 */
- (void)didGeneratedThumbnailsWithSuccess:(BOOL)success;

@end


@interface FFmpegController : NSObject

@property (nonatomic) NSMutableArray *thumbnails;
@property (nonatomic, weak) id<FFmpegControllerDelegate> delegate;

- (void)generateThumbnailForFile:(NSString *)file;

@end
