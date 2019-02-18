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

struct AVFormatContextCloser {
  void operator()(AVFormatContext *formatContext) {
    avformat_close_input(&formatContext);
  }
};

struct AVCodecContextDeleter {
  virtual void operator()(AVCodecContext *codecContext) {
    avcodec_free_context(&codecContext);
  }
};

struct AVCodecContextDeleterCloser : AVCodecContextDeleter {
  void operator()(AVCodecContext *codecContext) override {
    AVCodecContextDeleter()(codecContext);
    avcodec_close(codecContext);
  }
};

struct AVFrameDeleter {
  void operator()(AVFrame *frame) {
    av_frame_free(&frame);
  }
};

struct AVDeleter {
  void operator()(uint8_t *pointer) {
    av_free(pointer);
  }
};

struct SwsContextDeleter {
  void operator()(SwsContext *swsContext) {
    sws_freeContext(swsContext);
  }
};

struct AVPacketUnrefer {
  void operator()(AVPacket *packet) {
    av_packet_unref(packet);
  }
};

@implementation FFmpegController (Bridge)

- (BOOL)synchronouslyGenerateThumbnailsForFileAtPath:(NSString *)path {
  std::unique_ptr<AVFormatContext, AVFormatContextCloser> formatContext;
  auto raw_formatContext = formatContext.release();
  if (avformat_open_input(&raw_formatContext, path.fileSystemRepresentation, nullptr, nullptr) < 0) {
    return NO;
  }
  formatContext.reset(raw_formatContext);

  if (avformat_find_stream_info(formatContext.get(), nullptr) < 0) {
    return NO;
  }
  auto videoStreamIndex = std::find_if(formatContext->streams, formatContext->streams + formatContext->nb_streams, [](const AVStream *stream) {
    return stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO;
  });
  if (videoStreamIndex >= formatContext->streams + formatContext->nb_streams) {
    return NO;
  }
  auto videoStream = *videoStreamIndex;

  if (av_q2d(videoStream->avg_frame_rate) < 0) {
    return NO;
  }

  auto codec = avcodec_find_decoder(videoStream->codecpar->codec_id);

  std::unique_ptr<AVCodecContext, AVCodecContextDeleter> codecContext(avcodec_alloc_context3(codec));
  if (!codecContext) {
    return NO;
  }

  if (avcodec_parameters_to_context(codecContext.get(), videoStream->codecpar) < 0) {
    return NO;
  }
  codecContext->time_base = videoStream->time_base;

  if (avcodec_open2(codecContext.get(), codec, nullptr) < 0) {
    return NO;
  }
  codecContext = std::unique_ptr<AVCodecContext, AVCodecContextDeleterCloser>(codecContext.release());

  std::unique_ptr<AVFrame, AVFrameDeleter> frame(av_frame_alloc());
  if (!frame) {
    return NO;
  }
  std::unique_ptr<AVFrame, AVFrameDeleter> frameRGB(av_frame_alloc());
  if (!frameRGB) {
    return NO;
  }

  frameRGB->width = DEFAULT_THUMBNAIL_WIDTH;
  frameRGB->height = DEFAULT_THUMBNAIL_WIDTH * codecContext->height / codecContext->width;
  frameRGB->format = AV_PIX_FMT_RGBA;

  auto size = av_image_get_buffer_size(
      AV_PIX_FMT_RGBA,
      frameRGB->width,
      frameRGB->height,
      1);
  if (size < 0) {
    return NO;
  }
  std::unique_ptr<uint8_t, AVDeleter> frameRGBBuffer(static_cast<uint8_t *>(av_malloc(size)));
  if (av_image_fill_arrays(
          frameRGB->data,
          frameRGB->linesize,
          frameRGBBuffer.get(),
          AV_PIX_FMT_RGBA,
          frameRGB->width,
          frameRGB->height,
          1) < 0) {
    return NO;
  }

  std::unique_ptr<SwsContext, SwsContextDeleter> swsContext(sws_getContext(
      codecContext->width,
      codecContext->height,
      codecContext->pix_fmt,
      frameRGB->width,
      frameRGB->height,
      AV_PIX_FMT_RGBA, SWS_BILINEAR,
      nullptr,
      nullptr,
      nullptr));
  if (!swsContext) {
    return NO;
  }

  auto interval = 1.0 * av_rescale_q(formatContext->duration, AV_TIME_BASE_Q, videoStream->time_base) / DEFAULT_THUMBNAIL_COUNT;

  for (auto progress = 0; progress < DEFAULT_THUMBNAIL_COUNT; ++progress) {
    avcodec_flush_buffers(codecContext.get());
    av_seek_frame(
        formatContext.get(),
        static_cast<int>(videoStreamIndex - formatContext->streams),
        videoStream->start_time + interval * progress,
        AVSEEK_FLAG_BACKWARD);
    AVPacket raw_packet;
    while (!av_read_frame(formatContext.get(), &raw_packet)) {
      std::unique_ptr<AVPacket, AVPacketUnrefer> packet(&raw_packet);
      if (packet->stream_index == videoStreamIndex - formatContext->streams) {
        if (avcodec_send_packet(codecContext.get(), packet.get()) != 0) {
          break;
        }
      }

      auto result = avcodec_receive_frame(codecContext.get(), frame.get());
      if (result == AVERROR(EAGAIN)) {
        continue;
      } else if (result < 0) {
        break;
      }

      if (![self handleNewTimestamp:frame->best_effort_timestamp progress:progress forFileAtPath:path]) {
        break;
      }

      if (sws_scale(
              swsContext.get(),
              frame->data,
              frame->linesize,
              0,
              codecContext->height,
              frameRGB->data,
              frameRGB->linesize) < 0) {
        return NO;
      }

      [self saveWithThumbnail:*frameRGB->data width:frameRGB->width height:frameRGB->height index:progress timestamp:frame->best_effort_timestamp * av_q2d(videoStream->time_base) forFileAtPath:path];
      break;
    }
  }
  return YES;
}

+ (double)videoDurationForFileAtPath:(NSString *)path {
  std::unique_ptr<AVFormatContext, AVFormatContextCloser> formatContext;
  auto raw_formatContext = formatContext.release();
  if (avformat_open_input(&raw_formatContext, path.fileSystemRepresentation, nullptr, nullptr) < 0) {
    return -1;
  }
  formatContext.reset(raw_formatContext);
  if (formatContext->duration < 0) {
    if (avformat_find_stream_info(formatContext.get(), nullptr) < 0) {
      return -1;
    }
  }
  return 1.0 * formatContext->duration / AV_TIME_BASE;
}

@end
