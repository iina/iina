//
//  ObjcUtils.m
//  iina
//
//  Created by lhc on 16/1/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "iina-Bridging-Header.h"
#import "ObjcUtils.h"

#import <wchar.h>

#define INDEL_WEIGHT 1
#define SUBSTITUTION_WEIGHT 4

static inline int min(int a, int b, int c) {
  int m = a;
  if (b < m) m = b;
  if (c < m) m = c;
  return m;
}

@implementation ObjcUtils

+ (BOOL)catchException:(void(^)(void))tryBlock error:(__autoreleasing NSError **)error {
  @try {
    tryBlock();
    return YES;
  }
  @catch (NSException *exception) {
    *error = [[NSError alloc] initWithDomain:exception.name code:0 userInfo:exception.userInfo];
    return NO;
  }
}

+ (BOOL)silenced:(void(^)(void))tryBlock {
  @try {
    tryBlock();
    return YES;
  }
  @catch (NSException *exception) {
    return NO;
  }
}

+ (NSUInteger)levDistance:(NSString *)str0 and:(NSString *)str1 {
  int i, j;
  
  // Prepend a blank space and add a null terminator. The leading space is required so the strings
  // can be accessed using the one based indexes in the last loop below. The string must be null
  // terminated to be able to use the wcslen method and because the loop expects to be able to
  // access a null at the end of the string.
  str0 = [@" " stringByAppendingFormat:@"%@\0", str0];
  str1 = [@" " stringByAppendingFormat:@"%@\0", str1];

  // Convert from variable length character encoding to fixed length UTF-32 to make it easy to
  // access individual characters.
  const NSData *str0AsUTF32 = [str0 dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
  const NSData *str1AsUTF32 = [str1 dataUsingEncoding:NSUTF32LittleEndianStringEncoding];

  const wchar_t *cstr0 = (const wchar_t *)[str0AsUTF32 bytes];
  const wchar_t *cstr1 = (const wchar_t *)[str1AsUTF32 bytes];;
  const size_t len0 = wcslen(cstr0);
  const size_t len1 = wcslen(cstr1);

  int *_dist = malloc(sizeof(int) * (len0 + 1) * (len1 + 1));
  int (*dist)[len0 + 1][len1 + 1] = (int (*)[len0 + 1][len1 + 1])_dist;
  for (i = 0; i <= len0; ++i)
    for (j = 0; j <= len1; ++j)
      (*dist)[i][j] = 0;
  
  for (i = 1; i <= len0; ++i)
    (*dist)[i][0] = (*dist)[i - 1][0] + INDEL_WEIGHT;
  for (j = 1; j <= len1; ++j)
    (*dist)[0][j] = (*dist)[0][j - 1] + INDEL_WEIGHT;
  
  for (j = 1; j <= len1; ++j)
    for (i = 1; i <= len0; ++i)
      (*dist)[i][j] = min((*dist)[i - 1][j] + INDEL_WEIGHT,
                          (*dist)[i][j - 1] + INDEL_WEIGHT,
                          (*dist)[i - 1][j - 1] + (cstr0[i] == cstr1[j] ? 0 : SUBSTITUTION_WEIGHT));
  
  int result = (*dist)[len0][len1];
  free(_dist);
  return result;
}

@end
