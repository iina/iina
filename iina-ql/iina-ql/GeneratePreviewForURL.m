#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

#import <libavcodec/avcodec.h>
#import <libavformat/avformat.h>
#import <libavutil/imgutils.h>
#import <libswscale/swscale.h>

#include <sys/socket.h>
#include <sys/un.h>

NS_ASSUME_NONNULL_BEGIN

OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options);
void CancelPreviewGeneration(void *thisInterface, QLPreviewRequestRef preview);

/* -----------------------------------------------------------------------------
   Generate a preview for file

   This function's job is to create preview for designated file
   ----------------------------------------------------------------------------- */

OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options)
{
    NSURL *nsurl = (__bridge NSURL *)url;
    const char *c_str = [[nsurl absoluteString] cStringUsingEncoding:NSUTF8StringEncoding];

    dispatch_fd_t socket_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    const char *socket_path = "/private/tmp/.webdavUDS.iina";
    struct sockaddr_un address = {};
    address.sun_family = AF_UNIX;
    strncpy(address.sun_path, socket_path, sizeof(address.sun_path) - 1);
    connect(socket_fd, (struct sockaddr *)&address, sizeof(struct sockaddr_un));
    write(socket_fd, c_str, strlen(c_str));

    NSString *htmlPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/QuickLook/IINA.qlgenerator/Contents/Resources/template.html"];
    NSData *html = [[NSData alloc] initWithContentsOfFile:htmlPath];
    NSDictionary *properties = @{ // properties for the HTML data
                                 (__bridge NSString *)kQLPreviewPropertyTextEncodingNameKey : @"UTF-8",
                                 (__bridge NSString *)kQLPreviewPropertyMIMETypeKey : @"text/html",
                                 };
    QLPreviewRequestSetDataRepresentation(preview,
                                         (__bridge CFDataRef)html,
                                         kUTTypeHTML,
                                         (__bridge CFDictionaryRef)properties);
    return noErr;
}

void CancelPreviewGeneration(void *thisInterface, QLPreviewRequestRef preview)
{
    // Implement only if supported
}

NS_ASSUME_NONNULL_END
