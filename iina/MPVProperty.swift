import Foundation

struct MPVProperty {
  /** file-size */
  static let fileSize = "file-size"
  /** path */
  static let path = "path"
  /** media-title */
  static let mediaTitle = "media-title"
  /** file-format */
  static let fileFormat = "file-format"
  /** duration */
  static let duration = "duration"
  /** avsync */
  static let avsync = "avsync"
  /** total-avsync-change */
  static let totalAvsyncChange = "total-avsync-change"
  /** frame-drop-count */
  static let frameDropCount = "frame-drop-count"
  /** mistimed-frame-count */
  static let mistimedFrameCount = "mistimed-frame-count"
  /** time-pos */
  static let timePos = "time-pos"
  /** chapter */
  static let chapter = "chapter"
  /** chapters */
  static let chapters = "chapters"
  /** editions */
  static let editions = "editions"
  /** idle-active */
  static let idleActive = "idle-active"
  /** core-idle */
  static let coreIdle = "core-idle"
  /** cache-speed */
  static let cacheSpeed = "cache-speed"
  /** demuxer-cache-time */
  static let demuxerCacheTime = "demuxer-cache-time"
  /** demuxer-cache-state */
  static let demuxerCacheState = "demuxer-cache-state"
  /** paused-for-cache */
  static let pausedForCache = "paused-for-cache"
  /** cache-buffering-state */
  static let cacheBufferingState = "cache-buffering-state"
  /** eof-reached */
  static let eofReached = "eof-reached"
  /** audio-codec */
  static let audioCodec = "audio-codec"
  /** audio-params/format */
  static let audioParamsFormat = "audio-params/format"
  /** audio-params/samplerate */
  static let audioParamsSamplerate = "audio-params/samplerate"
  /** audio-params/channels */
  static let audioParamsChannels = "audio-params/channels"
  /** audio-params/channel-count */
  static let audioParamsChannelCount = "audio-params/channel-count"
  /** hwdec */
  static let hwdec = "hwdec"
  /** hwdec-current */
  static let hwdecCurrent = "hwdec-current"
  /** video-format */
  static let videoFormat = "video-format"
  /** video-codec */
  static let videoCodec = "video-codec"
  /** width */
  static let width = "width"
  /** height */
  static let height = "height"
  /** video-params */
  static let videoParams = "video-params"
  /** video-params/pixelformat */
  static let videoParamsPixelformat = "video-params/pixelformat"
  /** video-params/hw-pixelformat */
  static let videoParamsHwPixelformat = "video-params/hw-pixelformat"
  /** video-params/primaries */
  static let videoParamsPrimaries = "video-params/primaries"
  /** video-params/gamma */
  static let videoParamsGamma = "video-params/gamma"
  /** video-params/sig-peak */
  static let videoParamsSigPeak = "video-params/sig-peak"
  /** video-params/rotate */
  static let videoParamsRotate = "video-params/rotate"
  /** dwidth */
  static let dwidth = "dwidth"
  /** dheight */
  static let dheight = "dheight"
  /** container-fps */
  static let containerFps = "container-fps"
  /** estimated-vf-fps */
  static let estimatedVfFps = "estimated-vf-fps"
  /** window-scale */
  static let windowScale = "window-scale"
  /** display-fps */
  static let displayFps = "display-fps"
  /** estimated-display-fps */
  static let estimatedDisplayFps = "estimated-display-fps"
  /** video-aspect */
  static let videoAspect = "video-aspect"
  /** playlist-pos */
  static let playlistPos = "playlist-pos"
  /** playlist-count */
  static let playlistCount = "playlist-count"
  /** playlist/N/filename */
  static func playlistNFilename(_ n: Int) -> String {
    return "playlist/\(n)/filename"
  }
  /** playlist/N/playing */
  static func playlistNPlaying(_ n: Int) -> String {
    return "playlist/\(n)/playing"
  }
  /** playlist/N/current */
  static func playlistNCurrent(_ n: Int) -> String {
    return "playlist/\(n)/current"
  }
  /** playlist/N/title */
  static func playlistNTitle(_ n: Int) -> String {
    return "playlist/\(n)/title"
  }
  /** track-list */
  static let trackList = "track-list"
  /** track-list/count */
  static let trackListCount = "track-list/count"
  /** track-list/N/id */
  static func trackListNId(_ n: Int) -> String {
    return "track-list/\(n)/id"
  }
  /** track-list/N/type */
  static func trackListNType(_ n: Int) -> String {
    return "track-list/\(n)/type"
  }
  /** track-list/N/src-id */
  static func trackListNSrcId(_ n: Int) -> String {
    return "track-list/\(n)/src-id"
  }
  /** track-list/N/title */
  static func trackListNTitle(_ n: Int) -> String {
    return "track-list/\(n)/title"
  }
  /** track-list/N/lang */
  static func trackListNLang(_ n: Int) -> String {
    return "track-list/\(n)/lang"
  }
  /** track-list/N/albumart */
  static func trackListNAlbumart(_ n: Int) -> String {
    return "track-list/\(n)/albumart"
  }
  /** track-list/N/default */
  static func trackListNDefault(_ n: Int) -> String {
    return "track-list/\(n)/default"
  }
  /** track-list/N/forced */
  static func trackListNForced(_ n: Int) -> String {
    return "track-list/\(n)/forced"
  }
  /** track-list/N/codec */
  static func trackListNCodec(_ n: Int) -> String {
    return "track-list/\(n)/codec"
  }
  /** track-list/N/external */
  static func trackListNExternal(_ n: Int) -> String {
    return "track-list/\(n)/external"
  }
  /** track-list/N/external-filename */
  static func trackListNExternalFilename(_ n: Int) -> String {
    return "track-list/\(n)/external-filename"
  }
  /** track-list/N/selected */
  static func trackListNSelected(_ n: Int) -> String {
    return "track-list/\(n)/selected"
  }
  /** track-list/N/decoder-desc */
  static func trackListNDecoderDesc(_ n: Int) -> String {
    return "track-list/\(n)/decoder-desc"
  }
  /** track-list/N/demux-w */
  static func trackListNDemuxW(_ n: Int) -> String {
    return "track-list/\(n)/demux-w"
  }
  /** track-list/N/demux-h */
  static func trackListNDemuxH(_ n: Int) -> String {
    return "track-list/\(n)/demux-h"
  }
  /** track-list/N/demux-channel-count */
  static func trackListNDemuxChannelCount(_ n: Int) -> String {
    return "track-list/\(n)/demux-channel-count"
  }
  /** track-list/N/demux-channels */
  static func trackListNDemuxChannels(_ n: Int) -> String {
    return "track-list/\(n)/demux-channels"
  }
  /** track-list/N/demux-samplerate */
  static func trackListNDemuxSamplerate(_ n: Int) -> String {
    return "track-list/\(n)/demux-samplerate"
  }
  /** track-list/N/demux-fps */
  static func trackListNDemuxFps(_ n: Int) -> String {
    return "track-list/\(n)/demux-fps"
  }
  /** current-tracks/...  As per mpv docs, scripts etc. should not use this. */
  /** chapter-list/count */
  static let chapterListCount = "chapter-list/count"
  /** chapter-list/N/title */
  static func chapterListNTitle(_ n: Int) -> String {
    return "chapter-list/\(n)/title"
  }
  /** chapter-list/N/time */
  static func chapterListNTime(_ n: Int) -> String {
    return "chapter-list/\(n)/time"
  }
  /** af */
  static let af = "af"
  /** vf */
  static let vf = "vf"
  /** video-bitrate */
  static let videoBitrate = "video-bitrate"
  /** audio-bitrate */
  static let audioBitrate = "audio-bitrate"
  /** audio-device-list */
  static let audioDeviceList = "audio-device-list"
  /** audio-device */
  static let audioDevice = "audio-device"
  /** current-vo */
  static let currentVo = "current-vo"
  /** current-ao */
  static let currentAo = "current-ao"
  /** mpv-version */
  static let mpvVersion = "mpv-version"
}
