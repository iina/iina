// Compile the complete production controller, interposing only its direct FFmpeg calls.
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <libavcodec/avcodec.h>
#import <libavformat/avformat.h>
#import <libswscale/swscale.h>
#import <libavutil/imgutils.h>
#import "IINA-Swift.h"

@implementation FFmpegLogger
+ (void)debug:(NSString *)message {}
+ (void)error:(NSString *)message {}
+ (void)warn:(NSString *)message {}
@end

static const char *failure;
static BOOL injected;
static int formats, codecs, frames, buffers, scalers, packets, dictionaries;
static int frameCalls, seekCalls;

static BOOL fail(const char *name) {
  if (strcmp(failure, name) != 0) return NO;
  injected = YES;
  return YES;
}
static void check(BOOL condition, const char *message) {
  if (!condition) {
    fprintf(stderr, "FAIL [%s]: %s (format=%d codec=%d frame=%d buffer=%d scaler=%d packet=%d dictionary=%d)\n",
            failure, message, formats, codecs, frames, buffers, scalers, packets, dictionaries);
    exit(1);
  }
}
static int openInput(AVFormatContext **context, const char *path, const AVInputFormat *format, AVDictionary **options) {
  int result = avformat_open_input(context, path, format, options);
  if (*context) formats++;
  return result;
}
static void closeInput(AVFormatContext **context) {
  if (*context) formats--;
  avformat_close_input(context);
}
static int streamInfo(AVFormatContext *context, AVDictionary **options) {
  if (fail("stream-info")) return AVERROR_INVALIDDATA;
  int result = avformat_find_stream_info(context, options);
  if (result >= 0) {
    if (fail("no-video")) context->streams[0]->codecpar->codec_type = AVMEDIA_TYPE_AUDIO;
    if (fail("zero-rate")) context->streams[0]->avg_frame_rate = (AVRational){0, 1};
    if (fail("zero-denominator")) context->streams[0]->avg_frame_rate = (AVRational){1, 0};
  }
  return result;
}
static const AVCodec *decoder(enum AVCodecID id) {
  return fail("decoder") ? NULL : avcodec_find_decoder(id);
}
static AVCodecContext *allocateCodec(const AVCodec *codec) {
  if (fail("codec-allocation")) return NULL;
  AVCodecContext *context = avcodec_alloc_context3(codec);
  if (context) codecs++;
  return context;
}
static void freeCodec(AVCodecContext **context) {
  if (*context) codecs--;
  avcodec_free_context(context);
}
static int parameters(AVCodecContext *context, const AVCodecParameters *parameters) {
  if (fail("parameters")) return AVERROR(ENOMEM);
  int result = avcodec_parameters_to_context(context, parameters);
  if (fail("pixel-format")) context->pix_fmt = AV_PIX_FMT_NONE;
  return result;
}
static int openCodec(AVCodecContext *context, const AVCodec *codec, AVDictionary **options) {
  int result = fail("codec-open") ? AVERROR_INVALIDDATA : avcodec_open2(context, codec, options);
  // Unconsumed options belong to the caller on success and failure alike.
  if (options) {
    av_dict_set(options, "iina-test-unused", "1", 0);
    dictionaries++;
  }
  return result;
}
static void freeDictionary(AVDictionary **dictionary) {
  if (*dictionary) dictionaries--;
  av_dict_free(dictionary);
}
static AVFrame *allocateFrame(void) {
  frameCalls++;
  if ((frameCalls == 1 && fail("video-frame")) || (frameCalls == 2 && fail("rgb-frame"))) return NULL;
  AVFrame *frame = av_frame_alloc();
  if (frame) frames++;
  return frame;
}
static void freeFrame(AVFrame **frame) {
  if (*frame) frames--;
  av_frame_free(frame);
}
static int bufferSize(enum AVPixelFormat format, int width, int height, int align) {
  return fail("buffer-size") ? AVERROR(EINVAL) : av_image_get_buffer_size(format, width, height, align);
}
static void *allocateBuffer(size_t size) {
  if (fail("buffer-allocation")) return NULL;
  void *buffer = av_malloc(size);
  if (buffer) buffers++;
  return buffer;
}
static void freeBuffer(void *buffer) {
  if (buffer) buffers--;
  av_free(buffer);
}
static int fillImage(uint8_t *data[4], int lines[4], const uint8_t *buffer, enum AVPixelFormat format, int width, int height, int align) {
  return fail("fill-image") ? AVERROR(EINVAL) : av_image_fill_arrays(data, lines, buffer, format, width, height, align);
}
static struct SwsContext *scaler(int sourceWidth, int sourceHeight, enum AVPixelFormat sourceFormat,
                               int targetWidth, int targetHeight, enum AVPixelFormat targetFormat,
                               int flags, SwsFilter *sourceFilter, SwsFilter *targetFilter, const double *parameters) {
  if (fail("scaler")) return NULL;
  struct SwsContext *context = sws_getContext(sourceWidth, sourceHeight, sourceFormat, targetWidth, targetHeight,
                                            targetFormat, flags, sourceFilter, targetFilter, parameters);
  if (context) scalers++;
  return context;
}
static void freeScaler(struct SwsContext *context) {
  if (context) scalers--;
  sws_freeContext(context);
}
static int seekFrame(AVFormatContext *context, int stream, int64_t timestamp, int flags) {
  seekCalls++;
  if (fail("seek") || (seekCalls == 2 && fail("late-seek"))) return AVERROR(EIO);
  return av_seek_frame(context, stream, timestamp, flags);
}
static int readFrame(AVFormatContext *context, AVPacket *packet) {
  int result = av_read_frame(context, packet);
  if (result >= 0) packets++;
  return result;
}
static void unrefPacket(AVPacket *packet) {
  packets--;
  av_packet_unref(packet);
}
static int scaleFrame(struct SwsContext *context, const uint8_t * const source[], const int strides[],
                      int start, int height, uint8_t * const target[], const int targetStrides[]) {
  return fail("scale") ? AVERROR(EINVAL) : sws_scale(context, source, strides, start, height, target, targetStrides);
}

#define avformat_open_input openInput
#define avformat_close_input closeInput
#define avformat_find_stream_info streamInfo
#define avcodec_find_decoder decoder
#define avcodec_alloc_context3 allocateCodec
#define avcodec_free_context freeCodec
#define avcodec_parameters_to_context parameters
#define avcodec_open2 openCodec
#define av_dict_free freeDictionary
#define av_frame_alloc allocateFrame
#define av_frame_free freeFrame
#define av_image_get_buffer_size bufferSize
#define av_malloc allocateBuffer
#define av_free freeBuffer
#define av_image_fill_arrays fillImage
#define sws_getContext scaler
#define sws_freeContext freeScaler
#define av_seek_frame seekFrame
#define av_read_frame readFrame
#define av_packet_unref unrefPacket
#define sws_scale scaleFrame
#import "FFmpegController.m"

@interface ThrowingController: FFmpegController
@end
@implementation ThrowingController
- (void)saveThumbnail:(AVFrame *)frame width:(int)width height:(int)height index:(int)index realTime:(int)second forFile:(NSString *)file {
  injected = YES;
  @throw [NSException exceptionWithName:@"CleanupTest" reason:@"Injected callback exception" userInfo:nil];
}
@end

static void run(const char *stage, NSString *file, BOOL expectFailure) {
  failure = stage;
  injected = NO;
  frameCalls = seekCalls = 0;
  @autoreleasepool {
    FFmpegController *controller = strcmp(stage, "exception") == 0 ? [[ThrowingController alloc] init] : [[FFmpegController alloc] init];
    controller.thumbnailCount = 2;
    @try {
      int result = [controller getPeeksForFile:file thumbnailsWidth:16];
      check(expectFailure ? result < 0 : result == 0, "unexpected return status");
      if (!expectFailure) {
        NSArray<FFThumbnail *> *thumbnails = [controller valueForKey:@"thumbnails"];
        check(thumbnails.count >= 2, "successful generation must produce real images");
        for (FFThumbnail *thumbnail in thumbnails) {
          check(thumbnail.image != nil && thumbnail.image.size.width == 16, "thumbnail image and dimensions");
        }
      }
    } @catch (NSException *exception) {
      check(strcmp(stage, "exception") == 0 && [exception.name isEqualToString:@"CleanupTest"], "unexpected exception");
    }
    check(formats == 0 && codecs == 0 && frames == 0 && buffers == 0 && scalers == 0 && packets == 0 && dictionaries == 0, "all acquired native resources must be released");
    if (strcmp(stage, "success") && strcmp(stage, "invalid") && strcmp(stage, "missing")) {
      check(injected, "failure point must be reached");
    }
  }
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    av_log_set_level(AV_LOG_QUIET);
    NSString *video = [NSString stringWithUTF8String:argv[1]];
    run("stream-info", video, YES);
    const char *stages[] = {"no-video", "zero-rate", "zero-denominator", "decoder", "codec-allocation", "parameters",
                            "pixel-format", "codec-open", "video-frame", "rgb-frame", "buffer-size", "buffer-allocation",
                            "fill-image", "scaler", "seek", "late-seek", "scale", "exception"};
    for (int repeat = 0; repeat < 5; repeat++) {
      for (size_t i = 0; i < sizeof(stages) / sizeof(stages[0]); i++) run(stages[i], video, YES);
      run("success", video, NO);
    }
    run("invalid", [NSString stringWithUTF8String:argv[2]], YES);
    run("missing", [video stringByAppendingString:@".missing"], YES);
    puts("PASS: real FFmpeg thumbnail generation, 19 injected failure/exception paths, repeated recovery, packet/option cleanup and invalid/missing files");
  }
  return 0;
}
