//
//  HLSRemuxer.m
//  iina
//

#import "HLSRemuxer.h"
#import <libavformat/avformat.h>
#import <libavcodec/avcodec.h>
#import <libavutil/avutil.h>
#import <libavutil/channel_layout.h>
#import <libavutil/samplefmt.h>
#import <sys/time.h>
#import <unistd.h>

// AVAudioFifo lives in libavutil but its header isn't in the bundled include set; declare the
// handful of functions we use (audio transcode buffers samples to the encoder's frame size).
typedef struct AVAudioFifo AVAudioFifo;
extern AVAudioFifo *av_audio_fifo_alloc(enum AVSampleFormat sample_fmt, int channels, int nb_samples);
extern int av_audio_fifo_write(AVAudioFifo *af, void **data, int nb_samples);
extern int av_audio_fifo_read(AVAudioFifo *af, void **data, int nb_samples);
extern int av_audio_fifo_size(AVAudioFifo *af);
extern void av_audio_fifo_free(AVAudioFifo *af);

@interface HLSRemuxer ()
@property(nonatomic, copy) NSString *inputPath;
@property(nonatomic, copy) NSString *outputDir;
@property(nonatomic) double startSeconds;
@property(nonatomic) int audioIndex;
@property(nonatomic) int subtitleIndex;
@property(atomic) BOOL stopped;
@property(atomic) BOOL pacingOff;
@end

@implementation HLSRemuxer

- (instancetype)initWithInput:(NSString *)inputPath
                    outputDir:(NSString *)outputDir
                 startSeconds:(double)startSeconds
                   audioIndex:(int)audioIndex
                subtitleIndex:(int)subtitleIndex {
  self = [super init];
  if (self) {
    _inputPath = [inputPath copy];
    _outputDir = [outputDir copy];
    _startSeconds = startSeconds;
    _audioIndex = audioIndex;
    _subtitleIndex = subtitleIndex;
    _stopped = NO;
  }
  return self;
}

- (void)stop {
  self.stopped = YES;
}

- (void)releasePacing {
  self.pacingOff = YES;
}

- (void)start {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [self runRemux];
  });
}

- (void)runRemux {
  const char *inPath = self.inputPath.fileSystemRepresentation;

  // All locals declared up front so `goto cleanup` never bypasses an initialization.
  AVFormatContext *ic = NULL;
  AVFormatContext *oc = NULL;
  AVDictionary *opts = NULL;
  AVPacket *pkt = NULL;
  AVCodecContext *subDecCtx = NULL;
  AVCodecContext *subEncCtx = NULL;
  const AVCodec *subDec = NULL;
  const AVCodec *subEnc = NULL;
  AVCodecContext *audDecCtx = NULL;
  AVCodecContext *audEncCtx = NULL;
  const AVCodec *audDec = NULL;
  const AVCodec *audEnc = NULL;
  AVAudioFifo *audFifo = NULL;
  AVFrame *audDecFrame = NULL;
  AVPacket *audEncPkt = NULL;
  BOOL transcodeAudio = NO;
  int64_t audioNextPts = 0;
  BOOL haveAudioPts = NO;
  int outIndexOf[64];
  int inVideo = -1, inAudio = -1, inSub = -1, audioSeen = 0, subSeen = 0;
  int outSubIndex = -1;
  int ret = 0;
  // Subtitle mode: emit a master playlist + a WebVTT subtitle rendition (transcoded from the
  // text subtitle). Without subtitles, emit the simple single media playlist (out.m3u8).
  BOOL wantSub = (self.subtitleIndex >= 0);
  NSString *outName = wantSub ? @"out_%v.m3u8" : @"out.m3u8";
  NSString *segName = wantSub ? @"seg_%v_%03d.m4s" : @"seg_%03d.m4s";
  NSString *outFile = [self.outputDir stringByAppendingPathComponent:outName];
  NSString *segPattern = [self.outputDir stringByAppendingPathComponent:segName];
  for (int i = 0; i < 64; i++) outIndexOf[i] = -1;

  ret = avformat_open_input(&ic, inPath, NULL, NULL);
  if (ret < 0) { NSLog(@"HLSRemuxer: open_input failed (%d)", ret); goto cleanup; }
  if ((ret = avformat_find_stream_info(ic, NULL)) < 0) {
    NSLog(@"HLSRemuxer: find_stream_info failed (%d)", ret); goto cleanup;
  }

  if (self.startSeconds > 0.5) {
    int64_t ts = (int64_t)(self.startSeconds * AV_TIME_BASE);
    if (av_seek_frame(ic, -1, ts, AVSEEK_FLAG_BACKWARD) < 0) {
      NSLog(@"HLSRemuxer: seek to %.1fs failed; starting from 0", self.startSeconds);
    }
  }

  for (unsigned i = 0; i < ic->nb_streams; i++) {
    enum AVMediaType t = ic->streams[i]->codecpar->codec_type;
    if (t == AVMEDIA_TYPE_VIDEO && inVideo < 0) {
      inVideo = (int)i;
    } else if (t == AVMEDIA_TYPE_AUDIO) {
      if (audioSeen == self.audioIndex) inAudio = (int)i;
      audioSeen++;
    } else if (t == AVMEDIA_TYPE_SUBTITLE) {
      if (wantSub && subSeen == self.subtitleIndex) inSub = (int)i;
      subSeen++;
    }
  }
  if (inVideo < 0 || inAudio < 0) {
    NSLog(@"HLSRemuxer: no video(%d)/audio(%d)", inVideo, inAudio); goto cleanup;
  }
  // Requested subtitle missing → abort so the caller can retry without subtitles.
  if (wantSub && inSub < 0) { NSLog(@"HLSRemuxer: subtitle %d not found", self.subtitleIndex); goto cleanup; }

  // Set up the subtitle transcode (text subrip → WebVTT). Text subtitles round-trip through
  // ASS, so the encoder needs the decoder's ASS subtitle_header.
  if (wantSub) {
    subDec = avcodec_find_decoder(ic->streams[inSub]->codecpar->codec_id);
    if (subDec) subDecCtx = avcodec_alloc_context3(subDec);
    if (!subDecCtx || avcodec_parameters_to_context(subDecCtx, ic->streams[inSub]->codecpar) < 0
        || avcodec_open2(subDecCtx, subDec, NULL) < 0) {
      NSLog(@"HLSRemuxer: subtitle decoder setup failed"); goto cleanup;
    }
    subEnc = avcodec_find_encoder(AV_CODEC_ID_WEBVTT);
    if (subEnc) subEncCtx = avcodec_alloc_context3(subEnc);
    if (!subEncCtx) { NSLog(@"HLSRemuxer: no webvtt encoder"); goto cleanup; }
    subEncCtx->time_base = (AVRational){1, 1000};
    if (subDecCtx->subtitle_header_size > 0) {
      subEncCtx->subtitle_header = av_malloc(subDecCtx->subtitle_header_size + 1);
      memcpy(subEncCtx->subtitle_header, subDecCtx->subtitle_header, subDecCtx->subtitle_header_size);
      subEncCtx->subtitle_header[subDecCtx->subtitle_header_size] = 0;
      subEncCtx->subtitle_header_size = subDecCtx->subtitle_header_size;
    }
    if (avcodec_open2(subEncCtx, subEnc, NULL) < 0) {
      NSLog(@"HLSRemuxer: subtitle encoder setup failed"); goto cleanup;
    }
  }

  // Audio: stream-copy AAC and AC-3 (both play in sync over AirPlay); transcode anything else
  // (E-AC3, DTS, TrueHD…) to AAC, since e.g. E-AC3 desyncs on the receiver. On any setup
  // failure, fall back to stream-copy so the cast still works.
  {
    enum AVCodecID acodec = ic->streams[inAudio]->codecpar->codec_id;
    transcodeAudio = (acodec != AV_CODEC_ID_AAC && acodec != AV_CODEC_ID_AC3);
  }
  if (transcodeAudio) {
    audDec = avcodec_find_decoder(ic->streams[inAudio]->codecpar->codec_id);
    if (audDec) audDecCtx = avcodec_alloc_context3(audDec);
    if (audDecCtx && avcodec_parameters_to_context(audDecCtx, ic->streams[inAudio]->codecpar) >= 0) {
      audDecCtx->pkt_timebase = ic->streams[inAudio]->time_base;
    }
    audEnc = avcodec_find_encoder(AV_CODEC_ID_AAC);
    if (audEnc && audDecCtx && avcodec_open2(audDecCtx, audDec, NULL) >= 0) {
      audEncCtx = avcodec_alloc_context3(audEnc);
    }
    if (audEncCtx) {
      audEncCtx->sample_rate = audDecCtx->sample_rate;
      // Use a STANDARD channel layout (matching channel count → just a relabel, no downmix):
      // Apple's AAC decoder rejects PCE-based layouts like "5.1(side)".
      int nch = audDecCtx->ch_layout.nb_channels;
      if (nch == 6) { AVChannelLayout l = AV_CHANNEL_LAYOUT_5POINT1_BACK; av_channel_layout_copy(&audEncCtx->ch_layout, &l); }
      else if (nch == 2) { AVChannelLayout l = AV_CHANNEL_LAYOUT_STEREO; av_channel_layout_copy(&audEncCtx->ch_layout, &l); }
      else if (nch == 1) { AVChannelLayout l = AV_CHANNEL_LAYOUT_MONO; av_channel_layout_copy(&audEncCtx->ch_layout, &l); }
      else av_channel_layout_copy(&audEncCtx->ch_layout, &audDecCtx->ch_layout);
      audEncCtx->sample_fmt = AV_SAMPLE_FMT_FLTP;
      audEncCtx->bit_rate = 96000LL * audEncCtx->ch_layout.nb_channels;
      audEncCtx->time_base = (AVRational){1, audEncCtx->sample_rate};
      audEncCtx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;   // fMP4 wants the AAC ASC in the init segment
    }
    AVDictionary *encOpts = NULL;
    av_dict_set(&encOpts, "aac_coder", "fast", 0);   // faster encode → the buffer fills quicker
    int aacOpen = audEncCtx ? avcodec_open2(audEncCtx, audEnc, &encOpts) : -1;
    av_dict_free(&encOpts);
    if (aacOpen < 0) {
      NSLog(@"HLSRemuxer: audio transcode setup failed; streaming audio as-is");
      transcodeAudio = NO;
      if (audDecCtx) avcodec_free_context(&audDecCtx);
      if (audEncCtx) avcodec_free_context(&audEncCtx);
    } else {
      audFifo = av_audio_fifo_alloc(AV_SAMPLE_FMT_FLTP, audEncCtx->ch_layout.nb_channels, 1);
      audDecFrame = av_frame_alloc();
      audEncPkt = av_packet_alloc();
      if (!audFifo || !audDecFrame || !audEncPkt) { NSLog(@"HLSRemuxer: audio transcode alloc failed"); transcodeAudio = NO; }
      NSLog(@"HLSRemuxer: transcoding audio %s → aac", avcodec_get_name(ic->streams[inAudio]->codecpar->codec_id));
    }
  }

  if ((ret = avformat_alloc_output_context2(&oc, NULL, "hls", outFile.fileSystemRepresentation)) < 0) {
    NSLog(@"HLSRemuxer: alloc_output(hls) failed (%d)", ret); goto cleanup;
  }
  // Normalize the timeline to start at zero, shifting all streams equally so A/V stay in sync
  // (prevents the fMP4 segments from starting at odd/negative timestamps).
  oc->avoid_negative_ts = AVFMT_AVOID_NEG_TS_MAKE_ZERO;

  // Output stream 0 = video (stream copy).
  {
    AVStream *out = avformat_new_stream(oc, NULL);
    if (!out || avcodec_parameters_copy(out->codecpar, ic->streams[inVideo]->codecpar) < 0) {
      NSLog(@"HLSRemuxer: video stream setup failed"); goto cleanup;
    }
    out->codecpar->codec_tag = 0;
    if (inVideo < 64) outIndexOf[inVideo] = 0;
  }
  // Output stream 1 = audio (transcoded to AAC, or stream copy).
  {
    AVStream *out = avformat_new_stream(oc, NULL);
    int ok = out != NULL;
    if (ok && transcodeAudio) { ok = avcodec_parameters_from_context(out->codecpar, audEncCtx) >= 0; out->time_base = audEncCtx->time_base; }
    else if (ok) { ok = avcodec_parameters_copy(out->codecpar, ic->streams[inAudio]->codecpar) >= 0; }
    if (!ok) { NSLog(@"HLSRemuxer: audio stream setup failed"); goto cleanup; }
    out->codecpar->codec_tag = 0;
    if (inAudio < 64) outIndexOf[inAudio] = 1;
  }
  // Output stream 2 = subtitle (WebVTT), when requested.
  if (wantSub) {
    AVStream *out = avformat_new_stream(oc, NULL);
    if (!out || avcodec_parameters_from_context(out->codecpar, subEncCtx) < 0) {
      NSLog(@"HLSRemuxer: subtitle stream setup failed"); goto cleanup;
    }
    out->codecpar->codec_tag = 0;
    out->time_base = (AVRational){1, 1000};
    AVDictionaryEntry *lang = av_dict_get(ic->streams[inSub]->metadata, "language", NULL, 0);
    if (lang) av_dict_set(&out->metadata, "language", lang->value, 0);
    outSubIndex = 2;
    if (inSub < 64) outIndexOf[inSub] = 2;
  }

  av_dict_set(&opts, "hls_time", "6", 0);
  av_dict_set(&opts, "hls_playlist_type", "event", 0);
  av_dict_set(&opts, "hls_segment_type", "fmp4", 0);
  av_dict_set(&opts, "hls_fmp4_init_filename", "init.mp4", 0);
  av_dict_set(&opts, "hls_segment_filename", segPattern.fileSystemRepresentation, 0);
  if (wantSub) {
    av_dict_set(&opts, "master_pl_name", "master.m3u8", 0);
    av_dict_set(&opts, "var_stream_map", "v:0,a:0,s:0,sgroup:subs", 0);
  }

  if (!(oc->oformat->flags & AVFMT_NOFILE)) {
    if ((ret = avio_open(&oc->pb, outFile.fileSystemRepresentation, AVIO_FLAG_WRITE)) < 0) {
      NSLog(@"HLSRemuxer: avio_open failed (%d)", ret); goto cleanup;
    }
  }
  if ((ret = avformat_write_header(oc, &opts)) < 0) {
    NSLog(@"HLSRemuxer: write_header failed (%d)", ret); goto cleanup;
  }

  pkt = av_packet_alloc();
  long written = 0;
  double firstPtsSec = -1;
  struct timeval startTv;
  gettimeofday(&startTv, NULL);
  const double LOOKAHEAD = 30.0;   // initial buffer depth ahead of real time (avoids early underrun)
  while (!self.stopped && av_read_frame(ic, pkt) >= 0) {
    int oi = (pkt->stream_index < 64) ? outIndexOf[pkt->stream_index] : -1;
    if (oi < 0) { av_packet_unref(pkt); continue; }
    AVStream *in = ic->streams[pkt->stream_index];
    AVStream *out = oc->streams[oi];

    // Subtitle: decode the text subtitle and re-encode as WebVTT.
    if (oi == outSubIndex && wantSub) {
      AVSubtitle sub;
      int got = 0;
      if (avcodec_decode_subtitle2(subDecCtx, &sub, &got, pkt) >= 0 && got) {
        uint8_t buf[16384];
        int n = avcodec_encode_subtitle(subEncCtx, buf, sizeof(buf), &sub);
        if (n > 0) {
          AVPacket *op = av_packet_alloc();
          if (op && av_new_packet(op, n) == 0) {
            memcpy(op->data, buf, n);
            op->stream_index = outSubIndex;
            op->pts = av_rescale_q(pkt->pts, in->time_base, out->time_base);
            op->dts = op->pts;
            op->duration = av_rescale_q(pkt->duration, in->time_base, out->time_base);
            av_interleaved_write_frame(oc, op);
          }
          if (op) av_packet_free(&op);
        }
        avsubtitle_free(&sub);
      }
      av_packet_unref(pkt);
      continue;
    }

    // Audio transcode: decode → buffer to the encoder frame size → AAC-encode. The output PTS
    // is anchored to the first audio packet's timeline so it stays aligned with the video.
    if (oi == 1 && transcodeAudio) {
      if (avcodec_send_packet(audDecCtx, pkt) >= 0) {
        while (avcodec_receive_frame(audDecCtx, audDecFrame) >= 0) {
          if (!haveAudioPts && audDecFrame->pts != AV_NOPTS_VALUE) {
            // The track may have an A/V offset (e.g. this E-AC3 track starts at +1.008s).
            // Prepend that much silence so the audio aligns with the video and the real audio
            // lands at its offset — receivers otherwise mis-handle the initial gap (~1s desync).
            // Reference is the remux start (startSeconds), so this also holds when re-remuxing
            // from a seek position (audio timeline starts at the same movie time as the video).
            int64_t startSamples = (int64_t)(self.startSeconds * audEncCtx->sample_rate);
            int64_t audioFirst = av_rescale_q(audDecFrame->pts, in->time_base, audEncCtx->time_base);
            int64_t offset = audioFirst - startSamples;
            audioNextPts = startSamples;
            if (offset > 0 && offset < 10LL * audEncCtx->sample_rate) {
              AVFrame *sil = av_frame_alloc();
              sil->nb_samples = (int)offset;
              sil->format = AV_SAMPLE_FMT_FLTP;
              av_channel_layout_copy(&sil->ch_layout, &audEncCtx->ch_layout);
              sil->sample_rate = audEncCtx->sample_rate;
              if (av_frame_get_buffer(sil, 0) == 0) {
                av_samples_set_silence(sil->data, 0, (int)offset,
                                       audEncCtx->ch_layout.nb_channels, AV_SAMPLE_FMT_FLTP);
                av_audio_fifo_write(audFifo, (void **)sil->data, (int)offset);
              }
              av_frame_free(&sil);
            }
            haveAudioPts = YES;
          }
          av_audio_fifo_write(audFifo, (void **)audDecFrame->data, audDecFrame->nb_samples);
          av_frame_unref(audDecFrame);
        }
        while (av_audio_fifo_size(audFifo) >= audEncCtx->frame_size) {
          AVFrame *f = av_frame_alloc();
          f->nb_samples = audEncCtx->frame_size;
          f->format = AV_SAMPLE_FMT_FLTP;
          av_channel_layout_copy(&f->ch_layout, &audEncCtx->ch_layout);
          f->sample_rate = audEncCtx->sample_rate;
          if (av_frame_get_buffer(f, 0) == 0) {
            av_audio_fifo_read(audFifo, (void **)f->data, audEncCtx->frame_size);
            f->pts = audioNextPts; audioNextPts += audEncCtx->frame_size;
            if (avcodec_send_frame(audEncCtx, f) >= 0) {
              while (avcodec_receive_packet(audEncCtx, audEncPkt) >= 0) {
                av_packet_rescale_ts(audEncPkt, audEncCtx->time_base, out->time_base);
                audEncPkt->stream_index = 1;
                av_interleaved_write_frame(oc, audEncPkt);
                av_packet_unref(audEncPkt);
              }
            }
          }
          av_frame_free(&f);
        }
      }
      av_packet_unref(pkt);
      continue;
    }

    // Pace to ~real time (a live-stream cadence): a full-speed stream-copy races the playlist
    // to the end of the movie in seconds, so the AirPlay receiver rides a "live edge" that is
    // nowhere near the start. Throttling on the video PTS keeps the edge near real playback,
    // so the TV plays from near the beginning. stop() breaks the sleep promptly.
    if (!self.pacingOff && oi == 0 && pkt->pts != AV_NOPTS_VALUE) {
      double ptsSec = pkt->pts * av_q2d(in->time_base);
      if (firstPtsSec < 0) firstPtsSec = ptsSec;
      struct timeval now;
      gettimeofday(&now, NULL);
      double wall = (now.tv_sec - startTv.tv_sec) + (now.tv_usec - startTv.tv_usec) / 1e6;
      double ahead = (ptsSec - firstPtsSec) - wall - LOOKAHEAD;
      while (ahead > 0 && !self.stopped && !self.pacingOff) {
        double chunk = ahead > 0.2 ? 0.2 : ahead;
        usleep((useconds_t)(chunk * 1e6));
        ahead -= chunk;
      }
    }
    av_packet_rescale_ts(pkt, in->time_base, out->time_base);
    pkt->stream_index = oi;
    pkt->pos = -1;
    if (av_interleaved_write_frame(oc, pkt) < 0) { av_packet_unref(pkt); break; }
    written++;
    av_packet_unref(pkt);
  }
  // Flush the audio transcoder (decoder → FIFO → encoder) so the tail isn't dropped.
  if (transcodeAudio && !self.stopped && audDecCtx && audEncCtx) {
    avcodec_send_packet(audDecCtx, NULL);
    while (avcodec_receive_frame(audDecCtx, audDecFrame) >= 0) {
      av_audio_fifo_write(audFifo, (void **)audDecFrame->data, audDecFrame->nb_samples);
      av_frame_unref(audDecFrame);
    }
    while (av_audio_fifo_size(audFifo) > 0) {
      int n = av_audio_fifo_size(audFifo);
      if (n > audEncCtx->frame_size) n = audEncCtx->frame_size;
      AVFrame *f = av_frame_alloc();
      f->nb_samples = n; f->format = AV_SAMPLE_FMT_FLTP;
      av_channel_layout_copy(&f->ch_layout, &audEncCtx->ch_layout);
      f->sample_rate = audEncCtx->sample_rate;
      if (av_frame_get_buffer(f, 0) == 0) {
        av_audio_fifo_read(audFifo, (void **)f->data, n);
        f->pts = audioNextPts; audioNextPts += n;
        avcodec_send_frame(audEncCtx, f);
      }
      av_frame_free(&f);
    }
    avcodec_send_frame(audEncCtx, NULL);
    while (avcodec_receive_packet(audEncCtx, audEncPkt) >= 0) {
      av_packet_rescale_ts(audEncPkt, audEncCtx->time_base, oc->streams[1]->time_base);
      audEncPkt->stream_index = 1;
      av_interleaved_write_frame(oc, audEncPkt);
      av_packet_unref(audEncPkt);
    }
  }
  if (oc->pb) av_write_trailer(oc);
  if (!self.stopped && self.onFinished) {
    void (^cb)(void) = self.onFinished;
    dispatch_async(dispatch_get_main_queue(), ^{ cb(); });
  }

cleanup:
  av_dict_free(&opts);
  if (pkt) av_packet_free(&pkt);
  if (subDecCtx) avcodec_free_context(&subDecCtx);
  if (subEncCtx) avcodec_free_context(&subEncCtx);
  if (audDecCtx) avcodec_free_context(&audDecCtx);
  if (audEncCtx) avcodec_free_context(&audEncCtx);
  if (audFifo) av_audio_fifo_free(audFifo);
  if (audDecFrame) av_frame_free(&audDecFrame);
  if (audEncPkt) av_packet_free(&audEncPkt);
  if (oc && !(oc->oformat->flags & AVFMT_NOFILE) && oc->pb) avio_closep(&oc->pb);
  if (oc) avformat_free_context(oc);
  if (ic) avformat_close_input(&ic);
}

@end
