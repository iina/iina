//
//  ObjcUtils.h
//  iina
//
//  Created by lhc on 16/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

@interface ObjcUtils : NSObject

+ (BOOL)catchException:(void(^)())tryBlock error:(__autoreleasing NSError **)error;
+ (BOOL)silenced:(void(^)())tryBlock;

+ (NSUInteger)levDistance:(NSString *)str0 and:(NSString *)str1;

@end
