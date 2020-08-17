//
//  ObjcUtils.h
//  iina
//
//  Created by lhc on 16/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

@interface ObjcUtils : NSObject

+ (BOOL)catchException:(void(^)(void))tryBlock error:(__autoreleasing NSError **)error;
+ (BOOL)silenced:(void(^)(void))tryBlock;

+ (NSUInteger)levDistance:(NSString *)str0 and:(NSString *)str1;
+ (NSImage *)getImageFrom:(mpv_node *)image;

@end
