//
//  FFmpegController.mm
//  iina
//
//  Created by Saagar Jha on 2/16/19.
//  Copyright © 2019 lhc. All rights reserved.
//

#import "FFmpegController.h"

// Perhaps this will work someday? Until then, we need to keep around our dummy
// interface in the header file.
//#import "IINA-Swift.h"

#import <algorithm>
#import <memory>

extern "C" {
#import <libavcodec/avcodec.h>
#import <libavformat/avformat.h>
#import <libavutil/avutil.h>
#import <libavutil/imgutils.h>
#import <libswscale/swscale.h>
}

#define DEFAULT_THUMBNAIL_COUNT 100
#define DEFAULT_THUMBNAIL_WIDTH 240.0

#define __ACTUALLY_CONCATENATE(a, b) a##b
#define __CONCATENATE(a, b) __ACTUALLY_CONCATENATE(a, b)
#define DEFER(cleanup) std::shared_ptr<void> __CONCATENATE(__defer_, __LINE__)(nullptr, [&](...) cleanup)
#define GUARD(condition)    \
  do {                    \
    if (!(condition)) {  \
      return NO;      \
    }                   \
  } while (0)

@implementation FFmpegController (Bridge)

- (BOOL)synchronouslyGenerateThumbnailsForFileAtPath:(NSString *)path {
  AVFormatContext *formatContext = NULL;
  GUARD(avformat_open_input(&formatContext, path.fileSystemRepresentation, nullptr, nullptr) >= 0);
  DEFER({
    avformat_close_input(&formatContext);
  });

  GUARD(avformat_find_stream_info(formatContext, nullptr) >= 0);
  auto videoStreamIndex = std::find_if(formatContext->streams, formatContext->streams + formatContext->nb_streams, [](const AVStream *stream) {
    return stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO;
  });
  GUARD(videoStreamIndex < formatContext->streams + formatContext->nb_streams);
  auto videoStream = *videoStreamIndex;

  GUARD(av_q2d(videoStream->avg_frame_rate) >= 0);

  auto codec = avcodec_find_decoder(videoStream->codecpar->codec_id);

  AVCodecContext *codecContext = avcodec_alloc_context3(codec);
  DEFER({
    avcodec_free_context(&codecContext);
  });
  GUARD(codecContext /* != nullptr */);

  GUARD(avcodec_parameters_to_context(codecContext, videoStream->codecpar) >= 0);
  codecContext->time_base = videoStream->time_base;

  GUARD(avcodec_open2(codecContext, codec, nullptr) >= 0);
  DEFER({
    avcodec_close(codecContext);
  });

  AVFrame *frame = av_frame_alloc();
  GUARD(frame /* != nullptr */);
  DEFER({
    av_frame_free(&frame);
  });
  AVFrame *frameRGB = av_frame_alloc();
  GUARD(frameRGB /* != nullptr */);
  DEFER({
    av_frame_free(&frameRGB);
  });

  frameRGB->width = DEFAULT_THUMBNAIL_WIDTH;
  frameRGB->height = DEFAULT_THUMBNAIL_WIDTH * codecContext->height / codecContext->width;
  frameRGB->format = AV_PIX_FMT_RGBA;

  auto size = av_image_get_buffer_size(
      AV_PIX_FMT_RGBA,
      frameRGB->width,
      frameRGB->height,
      1);
  GUARD(size >= 0);
  uint8_t *frameRGBBuffer = static_cast<uint8_t *>(av_malloc(size));
  DEFER({
    av_free(frameRGBBuffer);
  });
  GUARD(av_image_fill_arrays(
            frameRGB->data,
            frameRGB->linesize,
            frameRGBBuffer,
            AV_PIX_FMT_RGBA,
            frameRGB->width,
            frameRGB->height,
            1) >= 0);

  SwsContext *swsContext = sws_getContext(
      codecContext->width,
      codecContext->height,
      codecContext->pix_fmt,
      frameRGB->width,
      frameRGB->height,
      AV_PIX_FMT_RGBA, SWS_BILINEAR,
      nullptr,
      nullptr,
      nullptr);
  GUARD(swsContext /* != nullptr */);
  DEFER({
    sws_freeContext(swsContext);
  });

  auto interval = 1.0 * av_rescale_q(formatContext->duration, AV_TIME_BASE_Q, videoStream->time_base) / DEFAULT_THUMBNAIL_COUNT;

  for (auto progress = 0; progress < DEFAULT_THUMBNAIL_COUNT; ++progress) {
    avcodec_flush_buffers(codecContext);
    av_seek_frame(
        formatContext,
        static_cast<int>(videoStreamIndex - formatContext->streams),
        videoStream->start_time + interval * progress,
        AVSEEK_FLAG_BACKWARD);
    AVPacket packet;
    while (!av_read_frame(formatContext, &packet)) {
      DEFER({
        av_packet_unref(&packet);
      });
      if (packet.stream_index == videoStreamIndex - formatContext->streams) {
        if (avcodec_send_packet(codecContext, &packet) != 0) {
          break;
        }
      }

      auto result = avcodec_receive_frame(codecContext, frame);
      if (result == AVERROR(EAGAIN)) {
        continue;
      } else if (result < 0) {
        break;
      }

      if (![self handleNewTimestamp:frame->best_effort_timestamp progress:progress forFileAtPath:path]) {
        break;
      }

      GUARD(sws_scale(
                swsContext,
                frame->data,
                frame->linesize,
                0,
                codecContext->height,
                frameRGB->data,
                frameRGB->linesize) >= 0);

      [self saveWithThumbnail:*frameRGB->data width:frameRGB->width height:frameRGB->height index:progress timestamp:frame->best_effort_timestamp * av_q2d(videoStream->time_base) forFileAtPath:path];
      break;
    }
  }
  return YES;
}

+ (double)videoDurationForFileAtPath:(NSString *)path {
  AVFormatContext *formatContext;
  if (avformat_open_input(&formatContext, path.fileSystemRepresentation, nullptr, nullptr) < 0) {
    return -1;
  }
  DEFER({
    avformat_close_input(&formatContext);
  });
  if (formatContext->duration < 0) {
    if (avformat_find_stream_info(formatContext, nullptr) < 0) {
      return -1;
    }
  }
  return 1.0 * formatContext->duration / AV_TIME_BASE;
}

@end
