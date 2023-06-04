//
//  FFmpegController.m
//  iina
//
//  Created by lhc on 9/6/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

#import "FFmpegController.h"
#import <Cocoa/Cocoa.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#import <libavcodec/avcodec.h>
#import <libavformat/avformat.h>
#import <libswscale/swscale.h>
#import <libavutil/imgutils.h>
#import <libavutil/mastering_display_metadata.h>
#pragma clang diagnostic pop

#import "IINA-Swift.h"

#define LOG_DEBUG(msg, ...) [FFmpegLogger debug:([NSString stringWithFormat:(msg), ##__VA_ARGS__])];
#define LOG_ERROR(msg, ...) [FFmpegLogger error:([NSString stringWithFormat:(msg), ##__VA_ARGS__])];
#define LOG_WARN(msg, ...) [FFmpegLogger warn:([NSString stringWithFormat:(msg), ##__VA_ARGS__])];

#define THUMB_COUNT_DEFAULT 100

#define CHECK_NOTNULL(ptr,msg) if (ptr == NULL) {\
LOG_ERROR(@"Error when getting thumbnails: %@", msg);\
return -1;\
}

#define CHECK_SUCCESS(ret,msg) if (ret < 0) {\
LOG_ERROR(@"Error when getting thumbnails: %@ (%d)", msg, ret);\
return -1;\
}

#define CHECK(ret,msg) if (!(ret)) {\
LOG_ERROR(@"Error when getting thumbnails: %@", msg);\
return -1;\
}

@implementation FFThumbnail

@end


@interface FFmpegController () {
  NSMutableArray<FFThumbnail *> *_thumbnails;
  NSMutableArray<FFThumbnail *> *_thumbnailPartialResult;
  NSMutableSet *_addedTimestamps;
  NSOperationQueue *_queue;
  double _timestamp;
}

- (int)getPeeksForFile:(NSString *)file thumbnailsWidth:(int)thumbnailsWidth;
- (void)saveThumbnail:(AVFrame *)pFrame width:(int)width height:(int)height index:(int)index realTime:(int)second forFile:(NSString *)file;

@end


@implementation FFmpegController

- (instancetype)init
{
  self = [super init];
  if (self) {
    self.thumbnailCount = THUMB_COUNT_DEFAULT;
    _thumbnails = [[NSMutableArray alloc] init];
    _thumbnailPartialResult = [[NSMutableArray alloc] init];
    _addedTimestamps = [[NSMutableSet alloc] init];
    _queue = [[NSOperationQueue alloc] init];
    _queue.maxConcurrentOperationCount = 1;
  }
  return self;
}

// MARK: - Generating Thumbnails

- (void)generateThumbnailForFile:(NSString *)file
                      thumbWidth:(int)thumbWidth
{
  [_queue cancelAllOperations];
  NSBlockOperation *op = [[NSBlockOperation alloc] init];
  __weak NSBlockOperation *weakOp = op;
  [op addExecutionBlock:^(){
    if ([weakOp isCancelled]) {
      return;
    }
    self->_timestamp = CACurrentMediaTime();
    int success = [self getPeeksForFile:file thumbnailsWidth:thumbWidth];
    if (self.delegate) {
      [self.delegate didGenerateThumbnails:[NSArray arrayWithArray:self->_thumbnails]
                                   forFile: file
                                 succeeded:(success < 0 ? NO : YES)];
    }
  }];
  [_queue addOperation:op];
}

- (int)getPeeksForFile:(NSString *)file
       thumbnailsWidth:(int)thumbnailsWidth
{
  int i, ret;

  char *cFilename = strdup(file.fileSystemRepresentation);
  [_thumbnails removeAllObjects];
  [_thumbnailPartialResult removeAllObjects];
  [_addedTimestamps removeAllObjects];

  // Register all formats and codecs. mpv should have already called it.
  // av_register_all();

  // Open video file
  AVFormatContext *pFormatCtx = NULL;
  ret = avformat_open_input(&pFormatCtx, cFilename, NULL, NULL);
  free(cFilename);
  CHECK_SUCCESS(ret, @"Cannot open video")

  // Find stream information
  ret = avformat_find_stream_info(pFormatCtx, NULL);
  CHECK_SUCCESS(ret, @"Cannot get stream info")

  // Find the first video stream
  int videoStream = -1;
  for (i = 0; i < pFormatCtx->nb_streams; i++)
    if (pFormatCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
      videoStream = i;
      break;
    }
  CHECK_SUCCESS(videoStream, @"No video stream")

  // Get the codec context for the video stream
  AVStream *pVideoStream = pFormatCtx->streams[videoStream];

  AVRational videoAvgFrameRate = pVideoStream->avg_frame_rate;

  // Check whether the denominator (AVRational.den) is zero to prevent division-by-zero
  if (videoAvgFrameRate.den == 0 || av_q2d(videoAvgFrameRate) == 0) {
    LOG_DEBUG(@"Avg frame rate = 0, ignore");
    return -1;
  }

  // Find the decoder for the video stream
  const AVCodec *pCodec = avcodec_find_decoder(pVideoStream->codecpar->codec_id);
  CHECK_NOTNULL(pCodec, @"Unsupported codec")

  // Open codec
  AVCodecContext *pCodecCtx = avcodec_alloc_context3(pCodec);
  AVDictionary *optionsDict = NULL;

  avcodec_parameters_to_context(pCodecCtx, pVideoStream->codecpar);
  pCodecCtx->time_base = pVideoStream->time_base;

  if (pCodecCtx->pix_fmt < 0 || pCodecCtx->pix_fmt >= AV_PIX_FMT_NB) {
    avcodec_free_context(&pCodecCtx);
    avformat_close_input(&pFormatCtx);
    LOG_ERROR(@"Error when getting thumbnails: Pixel format is null");
    return -1;
  }

  ret = avcodec_open2(pCodecCtx, pCodec, &optionsDict);
  CHECK_SUCCESS(ret, @"Cannot open codec")

  // Allocate video frame
  AVFrame *pFrame = av_frame_alloc();
  CHECK_NOTNULL(pFrame, @"Cannot alloc video frame")

  // Allocate the output frame
  // We need to convert the video frame to RGBA to satisfy CGImage's data format
  int thumbWidth = thumbnailsWidth;
  int thumbHeight = (float)thumbWidth / ((float)pCodecCtx->width / pCodecCtx->height);

  AVFrame *pFrameRGB = av_frame_alloc();
  CHECK_NOTNULL(pFrameRGB, @"Cannot alloc RGBA frame")

  pFrameRGB->width = thumbWidth;
  pFrameRGB->height = thumbHeight;
  pFrameRGB->format = AV_PIX_FMT_RGBA;

  // Determine required buffer size and allocate buffer
  int size = av_image_get_buffer_size(pFrameRGB->format, thumbWidth, thumbHeight, 1);
  uint8_t *pFrameRGBBuffer = (uint8_t *)av_malloc(size);

  // Assign appropriate parts of buffer to image planes in pFrameRGB
  ret = av_image_fill_arrays(pFrameRGB->data,
                             pFrameRGB->linesize,
                             pFrameRGBBuffer,
                             pFrameRGB->format,
                             pFrameRGB->width,
                             pFrameRGB->height, 1);
  CHECK_SUCCESS(ret, @"Cannot fill data for RGBA frame")

  // Create a sws context for converting color space and resizing
  CHECK(pCodecCtx->pix_fmt != AV_PIX_FMT_NONE, @"Pixel format is none")
  struct SwsContext *sws_ctx = sws_getContext(pCodecCtx->width, pCodecCtx->height, pCodecCtx->pix_fmt,
                                              pFrameRGB->width, pFrameRGB->height, pFrameRGB->format,
                                              SWS_BILINEAR,
                                              NULL, NULL, NULL);

  // Get duration and interval
  int64_t duration = av_rescale_q(pFormatCtx->duration, AV_TIME_BASE_Q, pVideoStream->time_base);
  double interval = duration / (double)self.thumbnailCount;
  double timebaseDouble = av_q2d(pVideoStream->time_base);
  AVPacket packet;

  // For each preview point
  for (i = 0; i <= self.thumbnailCount; i++) {
    int64_t seek_pos = interval * i + pVideoStream->start_time;

    avcodec_flush_buffers(pCodecCtx);

    // Seek to time point
    // avformat_seek_file(pFormatCtx, videoStream, seek_pos-interval, seek_pos, seek_pos+interval, 0);
    ret = av_seek_frame(pFormatCtx, videoStream, seek_pos, AVSEEK_FLAG_BACKWARD);
    CHECK_SUCCESS(ret, @"Cannot seek")

    avcodec_flush_buffers(pCodecCtx);

    // Read and decode frame
    while(av_read_frame(pFormatCtx, &packet) >= 0) {
      @try {
        // Make sure it's video stream
        if (packet.stream_index == videoStream) {

          // Decode video frame
          if (avcodec_send_packet(pCodecCtx, &packet) < 0)
            break;

          ret = avcodec_receive_frame(pCodecCtx, pFrame);
          if (ret < 0) {  // something happened
            if (ret == AVERROR(EAGAIN))  // input not ready, retry
              continue;
            else
              break;
          }

          // Check if duplicated
          NSNumber *currentTimeStamp = @(pFrame->best_effort_timestamp);
          if ([_addedTimestamps containsObject:currentTimeStamp]) {
            double currentTime = CACurrentMediaTime();
            if (currentTime - _timestamp > 1) {
              if (self.delegate) {
                [self.delegate didUpdateThumbnails:NULL forFile: file withProgress: i];
                _timestamp = currentTime;
              }
            }
            break;
          } else {
            [_addedTimestamps addObject:currentTimeStamp];
          }

          // Convert the frame to RGBA
          ret = sws_scale(sws_ctx,
                          (const uint8_t* const *)pFrame->data,
                          pFrame->linesize,
                          0,
                          pCodecCtx->height,
                          pFrameRGB->data,
                          pFrameRGB->linesize);
          CHECK_SUCCESS(ret, @"Cannot convert frame")

          // Save the frame to disk
          [self saveThumbnail:pFrameRGB
                        width:pFrameRGB->width
                       height:pFrameRGB->height
                        index:i
                     realTime:(pFrame->best_effort_timestamp * timebaseDouble)
                      forFile:file];
          break;
        }
      } @finally {
        // Free the packet
        av_packet_unref(&packet);
      }
    }
  }
  // Free the scaler
  sws_freeContext(sws_ctx);

  // Free the RGB image
  av_free(pFrameRGBBuffer);
  av_frame_free(&pFrameRGB);
  // Free the YUV frame
  av_frame_free(&pFrame);

  // Free the codec
  avcodec_free_context(&pCodecCtx);
  // Close the video file
  avformat_close_input(&pFormatCtx);

  // LOG_DEBUG(@"Thumbnails generated.");
  return 0;
}


- (void)saveThumbnail:(AVFrame *)pFrame width
                     :(int)width height
                     :(int)height index
                     :(int)index realTime
                     :(int)second forFile
                     :(NSString *)file
{
  // Create CGImage
  CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();

  CGContextRef cgContext = CGBitmapContextCreate(pFrame->data[0],  // it's converted to RGBA so could be used directly
                                                 width, height,
                                                 8,  // 8 bit per component
                                                 width * 4,  // 4 bytes(rgba) per pixel
                                                 rgb,
                                                 kCGImageAlphaPremultipliedLast);
  CGImageRef cgImage = CGBitmapContextCreateImage(cgContext);

  // Create NSImage
  NSImage *image = [[NSImage alloc] initWithCGImage:cgImage size: NSZeroSize];

  // Free resources
  CFRelease(rgb);
  CFRelease(cgContext);
  CFRelease(cgImage);

  // Add to list
  FFThumbnail *tb = [[FFThumbnail alloc] init];
  tb.image = image;
  tb.realTime = second;
  [_thumbnails addObject:tb];
  [_thumbnailPartialResult addObject:tb];
  // Post update notification
  double currentTime = CACurrentMediaTime();
  if (currentTime - _timestamp >= 0.2) {  // min notification interval: 0.2s
    if (_thumbnailPartialResult.count >= 10 || (currentTime - _timestamp >= 1 && _thumbnailPartialResult.count > 0)) {
      if (self.delegate) {
        [self.delegate didUpdateThumbnails:[NSArray arrayWithArray:_thumbnailPartialResult]
                                   forFile: file
                              withProgress: index];
      }
      [_thumbnailPartialResult removeAllObjects];
      _timestamp = currentTime;
    }
  }
}

// MARK: - Probing Video

+ (NSDictionary *)probeVideoInfoForFile:(nonnull NSString *)file
{
  int ret;
  int64_t duration;

  char *cFilename = strdup(file.fileSystemRepresentation);

  AVFormatContext *pFormatCtx = NULL;
  ret = avformat_open_input(&pFormatCtx, cFilename, NULL, NULL);
  free(cFilename);
  if (ret < 0) {
    LOG_ERROR(@"Error when opening file %@ to obtain info: %s (%d)", file, av_err2str(ret), ret);
    return NULL;
  }

  duration = pFormatCtx->duration;
  if (duration <= 0) {
    ret = avformat_find_stream_info(pFormatCtx, NULL);
    if (ret < 0) {
      LOG_ERROR(@"Error when probing %@ to obtain info: %s (%d)", file, av_err2str(ret), ret);
      duration = -1;
    } else
      duration = pFormatCtx->duration;
  }

  NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
  info[@"@iina_duration"] = duration == -1 ? [NSNumber numberWithInt:-1] : [NSNumber numberWithDouble:(double)duration / AV_TIME_BASE];
  AVDictionaryEntry *tag = NULL;
  while ((tag = av_dict_get(pFormatCtx->metadata, "", tag, AV_DICT_IGNORE_SUFFIX)))
    info[[NSString stringWithCString:tag->key encoding:NSUTF8StringEncoding]] = [NSString stringWithCString:tag->value encoding:NSUTF8StringEncoding];

  avformat_close_input(&pFormatCtx);
  avformat_free_context(pFormatCtx);

  return info;
}

// MARK: - Decoding Image

+ (NSImage *)createNSImageWithContentsOfURL:(nonnull NSURL *)url
{
  // Variables holding objects that will need to be freed.
  AVFormatContext *pFormatCtx = NULL;
  AVCodecContext *pCodecCtx = NULL;
  AVPacket *packet = NULL;
  AVFrame *pFrame = NULL;
  AVFrame *pFrameRGB = NULL;
  uint8_t *pFrameRGBBuffer = NULL;
  struct SwsContext *swsContext = NULL;
  CGColorSpaceRef cgColorSpace = NULL;
  CGContextRef cgContext = NULL;
  CGImageRef cgImage = NULL;

  @try {
#if DEBUG
    LOG_DEBUG(@"Creating image with contents of file: %s", url.fileSystemRepresentation)
#endif

    int ret = avformat_open_input(&pFormatCtx, url.fileSystemRepresentation, NULL, NULL);
    if (ret < 0) {
      LOG_ERROR(@"Error when opening file %@ to construct NSImage: %s (%d)", url, av_err2str(ret), ret);
      return NULL;
    }

    ret = avformat_find_stream_info(pFormatCtx, NULL);
    if (ret < 0) {
      LOG_ERROR(@"Cannot get stream info: %s (%d)", av_err2str(ret), ret);
      return NULL;
    }

    // Expecting image files to have one video stream.
    if (pFormatCtx->nb_streams != 1) {
      LOG_ERROR(@"Expected one stream found: %d", pFormatCtx->nb_streams);
      return NULL;
    }
    const AVStream *pVideoStream = pFormatCtx->streams[0];
    const enum AVMediaType codecType = pVideoStream->codecpar->codec_type;
    if (codecType != AVMEDIA_TYPE_VIDEO) {
      LOG_ERROR(@"Unexpected stream type: %s (%d)", av_get_media_type_string(codecType), codecType);
      return NULL;
    }
    // Expecting the number of frames to be unknown (0) or 1.
    if (pVideoStream->nb_frames > 1) {
      LOG_ERROR(@"Expected one frame found: %lld", pVideoStream->nb_frames);
      return NULL;
    }

    const AVCodec *pCodec = avcodec_find_decoder(pVideoStream->codecpar->codec_id);
    if (!pCodec) {
      LOG_ERROR(@"Cannot get decoder codec: %d", pVideoStream->codecpar->codec_id);
      return NULL;
    }

    // This method is only intended to be used for JPEG XL or WebP encoded images. As only these
    // formats have been tested, refuse to process other formats.
    if (pCodec->id != AV_CODEC_ID_JPEGXL && pCodec->id != AV_CODEC_ID_WEBP) {
      LOG_ERROR(@"Unexpected encoding: %s (%d)", pCodec->name, pCodec->id);
      return NULL;
    }

    pCodecCtx = avcodec_alloc_context3(pCodec);
    if (!pCodecCtx) {
      LOG_ERROR(@"Cannot alloc codec context: %s (%d)", pCodec->name, pCodec->id);
      return NULL;
    }
    avcodec_parameters_to_context(pCodecCtx, pVideoStream->codecpar);
    if (pCodecCtx->pix_fmt < 0 || pCodecCtx->pix_fmt >= AV_PIX_FMT_NB) {
      LOG_ERROR(@"Invalid pixel format: %d", pCodecCtx->pix_fmt);
      return NULL;
    }

    // Permit use of multiple threads for decoding. By default thread count is set to one which
    // disables use of multiple threads. Setting it to zero allows the codec to use multiple
    // threads. This is only done if the codec has the capability of using multiple threads for
    // decoding an individual frame as testing showed the WebP codec, which does not have this
    // capability, reacted badly to being given permission to use multiple threads. When this
    // property was set to anything other than one WebP decoding failed with "Resource temporarily
    // unavailable". The JPEG XL codec has this capability and will take advantage of multiple
    // threads. Testing on a MacBook Pro with the M1 Max chip showed a 40% reduction in the time to
    // decode a JPEG XL screenshot of a 4K video when using multiple threads. Normally speed of
    // decoding is not an issue, however mpv provides screenshot options that control the encoding
    // compression and quality. Changing these settings can result in the creation of screenshots
    // that take multiple seconds to decode. The thread count must be set before opening the codec.
    if (pCodec->capabilities & AV_CODEC_CAP_OTHER_THREADS) {
      pCodecCtx->thread_count = 0;
    }

    ret = avcodec_open2(pCodecCtx, pCodec, NULL);
    if (ret < 0) {
      LOG_ERROR(@"Cannot open codec: %s (%d)", av_err2str(ret), ret);
      return NULL;
    }

    packet = av_packet_alloc();
    ret = av_read_frame(pFormatCtx, packet);
    if (ret < 0) {
      LOG_ERROR(@"Cannot read packet: %s (%d)", av_err2str(ret), ret);
      return NULL;
    }
    if (packet->stream_index != 0) {
      LOG_ERROR(@"Unexpected video stream: %d", packet->stream_index);
      return NULL;
    }

    pFrame = av_frame_alloc();
    if (!pFrame) {
      LOG_ERROR(@"Cannot alloc frame");
      return NULL;
    }

    ret = avcodec_send_packet(pCodecCtx, packet);
    if (ret < 0) {
      LOG_ERROR(@"Cannot send packet: %s (%d)", av_err2str(ret), ret);
      return NULL;
    }
    ret = avcodec_receive_frame(pCodecCtx, pFrame);
    if (ret < 0) {
      LOG_ERROR(@"Cannot receive frame: %s (%d)", av_err2str(ret), ret);
      return NULL;
    }

#if DEBUG
    [FFmpegController logFrame:pCodec:pFrame];
#endif

    // CGImage requires the image frame to be converted to RGBA.
    pFrameRGB = av_frame_alloc();
    if (!pFrameRGB) {
      LOG_ERROR(@"Cannot alloc RGBA frame");
      return NULL;
    }
    pFrameRGB->width = pFrame->width;
    pFrameRGB->height = pFrame->height;

    // Determine the appropriate RGBA pixel format to convert to.
    CGBitmapInfo bitmapInfo;
    switch (pFrame->format) {
      default:
        // If this message is logged then the situation needs to be investigated to determine the
        // correct conversion. Fall through and treat this as a SDR image.
        LOG_WARN(@"Unexpected pixel format: %s (%d)", av_get_pix_fmt_name(pFrame->format),
             pFrame->format);
      case AV_PIX_FMT_ARGB: // WebP with screenshot-webp-lossless mpv option enabled.
      case AV_PIX_FMT_RGB24: // JPEG XL SDR video.
      case AV_PIX_FMT_YUV420P: // WebP default.
        pFrameRGB->format = AV_PIX_FMT_RGBA;
        bitmapInfo = (CGBitmapInfo)kCGImageAlphaPremultipliedLast;
        break;
      case AV_PIX_FMT_RGB48LE: // JPEG XL HDR video.
        // Workaround missing FFmpeg 6.0 scalar capabilities. As per Apple EDR requires using 16 bit
        // floating point components in the image bit map. Therefore we want the scalar to convert
        // the frame to the AV_PIX_FMT_RGBAF16LE pixel format. However when that was specified the
        // call to sws_getContext returned NULL. The scalar printed the message "rgbaf16le is not
        // supported as output pixel format" to the console. As a workaround we convert to
        // AV_PIX_FMT_RGBA64LE and then convert the components to floating point.
        pFrameRGB->format = AV_PIX_FMT_RGBA64LE;
        bitmapInfo = kCGImageByteOrder16Little | kCGImageAlphaPremultipliedLast |
            kCGBitmapFloatComponents;
    }

    // Determine required buffer size and allocate the buffer.
    const int size = av_image_get_buffer_size(pFrameRGB->format, pFrame->width, pFrame->height, 1);
    pFrameRGBBuffer = (uint8_t *)av_malloc(size);
    if (!pFrameRGBBuffer) {
      LOG_ERROR(@"Cannot alloc RGBA buffer");
      return NULL;
    }

    // Assign appropriate parts of buffer to image planes in pFrameRGB.
    ret = av_image_fill_arrays(pFrameRGB->data, pFrameRGB->linesize, pFrameRGBBuffer,
        pFrameRGB->format, pFrameRGB->width, pFrameRGB->height, 1);
    if (ret < 0) {
      LOG_ERROR(@"Cannot fill data for RGBA frame: %s (%d)", av_err2str(ret), ret);
      return NULL;
    }

    // Convert the image frame to RGBA using the FFmpeg scaler.
    swsContext = sws_getContext(pFrame->width, pFrame->height, pFrame->format,
        pFrameRGB->width, pFrameRGB->height, pFrameRGB->format, SWS_BILINEAR, NULL, NULL, NULL);
    if (!swsContext) {
      LOG_ERROR(@"Cannot alloc sws context");
      return NULL;
    }
    sws_scale(swsContext, (const uint8_t* const *)pFrame->data, pFrame->linesize, 0, pFrame->height,
        pFrameRGB->data, pFrameRGB->linesize);

    // Obtain information about the pixel format that is needed to create the bitmap image.
    const AVPixFmtDescriptor *pixFmtDesc = av_pix_fmt_desc_get(pFrameRGB->format);
    if (!pixFmtDesc){
      LOG_ERROR(@"Cannot get descriptor for pixel format: %s (%d)",
            av_get_pix_fmt_name(pFrameRGB->format), pFrameRGB->format);
      return NULL;
    }
    const int bitsPerPixel = av_get_bits_per_pixel(pixFmtDesc);
    const int bitsPerComponent = bitsPerPixel / pixFmtDesc->nb_components;
    const int bytesPerPixel = bitsPerPixel / 8;

    if (pFrameRGB->format == AV_PIX_FMT_RGBA64LE) {
      // Apply the second part of the workaround for the FFmpeg scalar not supporting conversion to
      // the pixel format AV_PIX_FMT_RGBAF16LE. Traverse the frame converting the pixel components
      // to short floating point values.
      const int bytesPerComponent = bitsPerComponent / 8;
      const int bytesPerRow = pFrameRGB->width * bytesPerPixel;
      // Each row of pixels in memory may contain extra padding for performance reasons. The
      // linesize gives the actual number of bytes each row consumes in the frame buffer.
      const int strideInBytes = pFrameRGB->linesize[0];
      for (int rowOffset = 0; rowOffset < size; rowOffset += strideInBytes) {
        // Convert each pixel component in the row.
        for (int index = rowOffset; index < rowOffset + bytesPerRow; index += bytesPerComponent) {
          uint16_t componentValue;
          memcpy(&componentValue, &pFrameRGB->data[0][index], sizeof componentValue);
          const _Float16 asFloat = (float)componentValue / USHRT_MAX;
          memcpy(&pFrameRGB->data[0][index], &asFloat, sizeof asFloat);
        }
      }
    }

    // Determine the color space to use for the image.
    switch (pFrame->color_primaries) {
      default:
        // If this message is logged then the situation needs to be investigated to determine the
        // correct color space. Fall through and treat this as a SDR image.
        LOG_WARN(@"Unexpected color primaries: %s (%d)",
             av_color_primaries_name(pFrame->color_primaries), pFrame->color_primaries);
      case AVCOL_PRI_UNSPECIFIED:
      case AVCOL_PRI_BT709:
        cgColorSpace = CGColorSpaceCreateDeviceRGB();
        break;
      case AVCOL_PRI_BT2020:
        if (@available(macOS 11.0, *)) {
          cgColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2100_PQ);
        } else if (@available(macOS 10.15.4, *)) {
            cgColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2020_PQ);
        } else if (@available(macOS 10.14.6, *)) {
            cgColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2020_PQ_EOTF);
        } else {
          cgColorSpace = CGColorSpaceCreateDeviceRGB();
        }
        break;
      case AVCOL_PRI_SMPTE432:
        if (@available(macOS 10.15.4, *)) {
          cgColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3_PQ);
        } else if (@available(macOS 10.14.6, *)) {
          cgColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3_PQ_EOTF);
        } else {
          cgColorSpace = CGColorSpaceCreateDeviceRGB();
        }
    }
    if (!cgColorSpace) {
      LOG_ERROR(@"Cannot create color space");
      return NULL;
    }

#if DEBUG
    LOG_DEBUG(@"Selected %s color space for bitmap image",
        CFStringGetCStringPtr(CGColorSpaceCopyName(cgColorSpace), CFStringGetSystemEncoding()));
    LOG_DEBUG(@"Creating bitmap image with %d bits per component and %d bytes per pixel",
        bitsPerComponent, bytesPerPixel);
#endif

    cgContext = CGBitmapContextCreate(pFrameRGB->data[0], pFrameRGB->width, pFrameRGB->height,
        bitsPerComponent, pFrameRGB->width * bytesPerPixel, cgColorSpace, bitmapInfo);
    if (!cgContext) {
      LOG_ERROR(@"Cannot create bitmap context");
      return NULL;
    }
    cgImage = CGBitmapContextCreateImage(cgContext);
    if (!cgImage) {
      LOG_ERROR(@"Cannot create bitmap image");
      return NULL;
    }

    NSImage *image = [[NSImage alloc] initWithCGImage:cgImage size: NSZeroSize];
    if (!image) {
      LOG_ERROR(@"Cannot create image");
    }
    return image;
  }
  @finally {
    // All of these methods accept null, no need to check if the object was allocated.
    CGImageRelease(cgImage);
    CGContextRelease(cgContext);
    CGColorSpaceRelease(cgColorSpace);
    sws_freeContext(swsContext);
    av_freep(&pFrameRGBBuffer);
    av_frame_free(&pFrameRGB);
    av_frame_free(&pFrame);
    av_packet_free(&packet);
    avcodec_free_context(&pCodecCtx);
    avformat_close_input(&pFormatCtx);
  }
}

// MARK: - Logging

#if DEBUG
/// Log details about the given decoded frame.
/// - Parameters:
///   - pCodec: The codec that decoded the frame.
///   - pFrame: The decoded frame to log.
+ (void)logFrame:(const AVCodec *)pCodec
                :(const AVFrame *)pFrame
{
  LOG_DEBUG(@"Decoded %s frame", pCodec->long_name);
  LOG_DEBUG(@"Pixel format: %s (%d)", av_get_pix_fmt_name(pFrame->format), pFrame->format);
  LOG_DEBUG(@"Color range: %s (%d)", av_color_range_name(pFrame->color_range), pFrame->color_range);
  LOG_DEBUG(@"Color primaries: %s (%d)", av_color_primaries_name(pFrame->color_primaries), pFrame->color_primaries);
  LOG_DEBUG(@"Color transfer: %s (%d)", av_color_transfer_name(pFrame->color_trc), pFrame->color_trc);
  LOG_DEBUG(@"Color space: %s (%d)", av_color_space_name(pFrame->colorspace), pFrame->colorspace);
  LOG_DEBUG(@"Width: %d", pFrame->width);
  LOG_DEBUG(@"Height: %d", pFrame->height);
}
#endif

@end
