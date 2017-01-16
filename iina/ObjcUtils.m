//
//  ObjcUtils.m
//  iina
//
//  Created by lhc on 16/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ObjcUtils.h"

@implementation ObjcUtils

  + (BOOL)catchException:(void(^)())tryBlock error:(__autoreleasing NSError **)error {
    @try {
      tryBlock();
      return YES;
    }
    @catch (NSException *exception) {
      *error = [[NSError alloc] initWithDomain:exception.name code:0 userInfo:exception.userInfo];
    }
  }

  + (BOOL)silenced:(void(^)())tryBlock {
    @try {
      tryBlock();
      return YES;
    }
    @catch (NSException *exception) {
      // do nothing
    }
  }

@end
