//
//  ObjcUtils.m
//  iina
//
//  Created by lhc on 16/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ObjcUtils.h"

#import <wchar.h>

#define INDEL_WEIGHT 1
#define SUBSTITUTION_WEIGHT 2

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
  int i, j;

  str0 = [@" " stringByAppendingString:str0];
  str1 = [@" " stringByAppendingString:str1];
  const wchar_t *cstr0 = (const wchar_t *)[str0 cStringUsingEncoding:NSUTF32LittleEndianStringEncoding];
  const wchar_t *cstr1 = (const wchar_t *)[str1 cStringUsingEncoding:NSUTF32LittleEndianStringEncoding];
  size_t len0 = wcslen(cstr0);
  size_t len1 = wcslen(cstr1);

  int dist[len0 + 1][len1 + 1];
  for (i = 0; i <= len0; ++i)
    memset(dist[i], 0, sizeof(int) * (len1 + 1));

  for (i = 0; i <= len0; ++i)
    for (j = 0; j <= len1; ++j)
        dist[i][j] = 0;

  for (i = 1; i <= len0; ++i)
    dist[i][0] = dist[i -1][0] + INDEL_WEIGHT;
  for (j = 1; j <= len1; ++j)
    dist[0][j] = dist[0][i-1] + INDEL_WEIGHT;

  for (j = 1; j <= len1; ++j)
    for (i = 1; i <= len0; ++i)
        dist[i][j] = min(dist[i - 1][j] + INDEL_WEIGHT,
                         dist[i][j - 1] + INDEL_WEIGHT,
                         dist[i - 1][j - 1] + (cstr0[i] == cstr1[j] ? 0 : SUBSTITUTION_WEIGHT));
  return dist[len0][len1];
}

@end
