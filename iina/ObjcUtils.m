//
//  ObjcUtils.m
//  iina
//
//  Created by lhc on 16/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ObjcUtils.h"

static inline int min(int a, int b, int c) {
  int m = a;
  if (b < m) m = b;
  if (c < m) m = c;
  return m;
}

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

+ (NSUInteger)levDistance:(NSString *)str0 and:(NSString *)str1 {
  int i, j, d1, d2, d3;
  const char *cstr0 = str0.UTF8String;
  const char *cstr1 = str1.UTF8String;
  int len0 = (int)str0.length;
  int len1 = (int)str1.length;

  int **dist = malloc(sizeof(int*) * len0);
  for (i = 0; i < len0; i++) {
    dist[i] = malloc(sizeof(int*) * len1);
    memset(dist[i], 0, sizeof(int) * len1);
  }

  for (i = 0; i < len0; i++) {
    dist[i][0] = i;
  }
  for (i = 0; i < len1; i++) {
    dist[0][i] = i;
  }
  for (i = 1; i < len0; i++) {
    for (j = 1; j < len1; j++) {
      d1 = dist[i-1][j] + 1;
      d2 = dist[i][j-1] + 1;
      d3 = dist[i-1][j-1] + (cstr0[i] == cstr1[j] ? 0 : 1);
      dist[i][j] = min(d1, d2, d3);
    }
  }
  int result = dist[len0 - 1][len1 - 1];
  for (i = 0; i < len0; i++) {
    free(dist[i]);
  }
  free(dist);

  return result;
}


@end
