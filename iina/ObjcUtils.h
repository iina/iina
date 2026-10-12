//
//  ObjcUtils.h
//  iina
//
//  Created by lhc on 16/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

@class NSView;

@interface ObjcUtils : NSObject

+ (BOOL)catchException:(void(^)(void))tryBlock error:(__autoreleasing NSError **)error;
+ (BOOL)silenced:(void(^)(void))tryBlock;

+ (NSUInteger)levDistance:(NSString *)str0 and:(NSString *)str1;

/// Unarchive an object from data written by the deprecated `NSArchiver`, which `NSKeyedUnarchiver` can not read.
+ (id)unarchiveLegacyObjectWithData:(NSData *)data;

/// Enable the high resolution and extended dynamic range OpenGL surface of the given view using its deprecated properties.
+ (void)enableHighResolutionOpenGLSurfaceForView:(NSView *)view;

@end
