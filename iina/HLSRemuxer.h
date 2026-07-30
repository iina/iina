//
//  HLSRemuxer.h
//  iina
//
//  Remuxes a media file to fMP4 HLS in-process using libavformat (the libav* libs IINA
//  already links) — no bundled ffmpeg CLI. Used by the AirPlay feature.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HLSRemuxer : NSObject

/// - Parameters:
///   - inputPath: source media file.
///   - outputDir: directory to write `out.m3u8`, `init.mp4`, `seg_%03d.m4s` into.
///   - audioIndex: 0-based index among the file's audio streams.
///   - subtitleIndex: 0-based index among the file's subtitle streams, or -1 for none.
/// - Parameters:
///   - startSeconds: remux from this position (seeks to the keyframe at/just before it),
///     keeping original timestamps so the HLS timeline equals the movie time.
- (instancetype)initWithInput:(NSString *)inputPath
                    outputDir:(NSString *)outputDir
                 startSeconds:(double)startSeconds
                   audioIndex:(int)audioIndex
                subtitleIndex:(int)subtitleIndex;

/// Called on the main queue once the remux has finished writing the complete playlist
/// (#EXT-X-ENDLIST present) — i.e. the output is now a full, seekable VOD.
@property (nonatomic, copy, nullable) void (^onFinished)(void);

/// Begins remuxing on a background queue (returns immediately).
- (void)start;

/// Stops pacing the remux to real time — the remainder is written as fast as possible to
/// fill the receiver's buffer (prevents underrun stalls and makes forward seeking available).
/// Call only after the receiver has started playing near the beginning.
- (void)releasePacing;

/// Signals the remux to stop as soon as possible.
- (void)stop;

@end

NS_ASSUME_NONNULL_END
