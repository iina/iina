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

OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options);
void CancelPreviewGeneration(void *thisInterface, QLPreviewRequestRef preview);

/* -----------------------------------------------------------------------------
   Generate a preview for file

   This function's job is to create preview for designated file
   ----------------------------------------------------------------------------- */

OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options)
{
    NSURL *nsurl = (__bridge NSURL *)url;
    AVAsset *asset = [AVAsset assetWithURL:nsurl];
    if (asset) {
        NSArray<AVAssetTrack *> *videos, *audios;
        // with video
        if ((videos = [asset tracksWithMediaType:AVMediaTypeVideo]) && videos.firstObject.playable) {
            QLPreviewRequestSetURLRepresentation(preview, url, kUTTypeMovie, (__bridge CFDictionaryRef)([[NSDictionary alloc] init]));
            return noErr;
        } else if ((audios = [asset tracksWithMediaType:AVMediaTypeAudio]) && audios.firstObject.playable){
            QLPreviewRequestSetURLRepresentation(preview, url, kUTTypeAudio, (__bridge CFDictionaryRef)([[NSDictionary alloc] init]));
            return noErr;
        }
    }
    av_register_all();
    avcodec_register_all();
    AVFormatContext *format_ctx = NULL;
    if (avformat_open_input(&format_ctx, [[nsurl path] cStringUsingEncoding:NSUTF8StringEncoding], NULL, NULL)) goto END0;
    if (avformat_find_stream_info(format_ctx, NULL)) goto END0;
    int video_stream_id = -1;
    for (int i = 0; i < format_ctx->nb_streams; i++) {
        if (format_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            video_stream_id = i;
            break;
        }
    }
    if (video_stream_id == -1) {
        // encode audio and preview?
        return noErr;
    } else {
        // show preview of video, ref FFmpegController
        AVStream *video_stream = format_ctx->streams[video_stream_id];
        if (av_q2d(video_stream->avg_frame_rate) == 0) goto END;
        AVCodec *video_codec = avcodec_find_decoder(video_stream->codecpar->codec_id);
        if (video_codec == NULL) goto END;
        AVCodecContext *video_codec_ctx = avcodec_alloc_context3(video_codec); // FREE
        if (video_codec_ctx == NULL) goto END1;
        if (avcodec_parameters_to_context(video_codec_ctx, video_stream->codecpar)) goto END1;
        video_codec_ctx->time_base = video_stream->time_base;
        if (avcodec_open2(video_codec_ctx, video_codec, NULL)) goto END1;
        AVFrame *frame = av_frame_alloc(), *frame_orig = av_frame_alloc(); // FREE
        if (frame == NULL || frame_orig == NULL) goto END2;
        frame->width = video_codec_ctx->width;
        frame->height = video_codec_ctx->height;
        frame->format = AV_PIX_FMT_RGBA;
        int size = av_image_get_buffer_size(frame->format, frame->width, frame->height, 1);
        if (size < 0) goto END2;
        uint8_t *frame_buffer = (uint8_t *)av_malloc(size);
        if (av_image_fill_arrays(frame->data, frame->linesize, frame_buffer, frame->format, frame->width, frame->height, 1) < 0) goto END3;
        struct SwsContext *sws_ctx = sws_getContext(video_codec_ctx->width, video_codec_ctx->height, video_codec_ctx->pix_fmt, frame->width, frame->height, frame->format, SWS_LANCZOS, NULL, NULL, NULL);
        int64_t duration = video_stream->duration * av_q2d(video_stream->time_base);
        int64_t preview_time;
        if (duration < 10) {
//            preview_time = format_ctx->duration * 0.1;
            preview_time = duration * 0.1;
        } else {
            preview_time = 10 / av_q2d(video_stream->time_base); //  / video_stream->duration * format_ctx->duration;
        }
        avcodec_flush_buffers(video_codec_ctx);
        if (av_seek_frame(format_ctx, video_stream_id, preview_time, AVSEEK_FLAG_BACKWARD)) goto END3;
        avcodec_flush_buffers(video_codec_ctx);
        AVPacket packet;
        while (!av_read_frame(format_ctx, &packet)) {
            if (packet.stream_index == video_stream_id) {
                if (avcodec_send_packet(video_codec_ctx, &packet)) break;
                int ret = avcodec_receive_frame(video_codec_ctx, frame_orig);
                if (ret) {
                    if (ret == AVERROR(EAGAIN))
                        continue;
                    else
                        break;
                }
                if (sws_scale(sws_ctx, (const uint8_t *const *)frame_orig->data, frame_orig->linesize, 0, video_codec_ctx->height, frame->data, frame->linesize) < 0) goto NEXT;
                CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
                CGContextRef cg_ctx = CGBitmapContextCreate(frame->data[0], frame->width, frame->height, 8, frame->width * 4, rgb, kCGImageAlphaPremultipliedLast);
                CGImageRef cgimage = CGBitmapContextCreateImage(cg_ctx);
//                CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
//                CGImageDestinationRef dest = CGImageDestinationCreateWithData(data, kUTTypePNG, 1, NULL);
//                CGImageDestinationAddImage(dest, cgimage, NULL);
//                CGImageDestinationFinalize(dest);
                CGContextRef qlcg = QLPreviewRequestCreateContext(preview, CGSizeMake(frame->width, frame->height), true, NULL);
                CGContextDrawImage(qlcg, CGRectMake(0, 0, frame->width, frame->height), cgimage);
                QLPreviewRequestFlushContext(preview, qlcg);
                CGContextRelease(qlcg);
                CFRelease(cgimage);
                CGContextRelease(cg_ctx);
                CFRelease(rgb);
//                QLPreviewRequestSetDataRepresentation(preview, data, kUTTypePNG, (__bridge CFDictionaryRef)([[NSDictionary alloc] init]));
//                CFRelease(dest);
//                CFRelease(data);
            NEXT:
                av_packet_unref(&packet);
                break;
            }
        }


        av_free(frame_buffer);
        av_frame_free(&frame);
        av_frame_free(&frame_orig);
        avcodec_free_context(&video_codec_ctx);
        avformat_close_input(&format_ctx);
        return noErr;
    END3:
        av_free(frame_buffer);
    END2:
        av_frame_free(&frame);
        av_frame_free(&frame_orig);
    END1:
        avcodec_free_context(&video_codec_ctx);
    END0:
        avformat_close_input(&format_ctx);
    END:
        return -1;
    }
    // To complete your generator please implement the function GeneratePreviewForURL in GeneratePreviewForURL.c


}

void CancelPreviewGeneration(void *thisInterface, QLPreviewRequestRef preview)
{
    // Implement only if supported
}
