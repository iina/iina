import Foundation

struct MPVProperty {
  /** audio-speed-correction */
  static let audioSpeedCorrection = "audio-speed-correction"
  /** video-speed-correction */
  static let videoSpeedCorrection = "video-speed-correction"
  /** display-sync-active */
  static let displaySyncActive = "display-sync-active"
  /** filename */
  static let filename = "filename"
  /** filename/no-ext */
  static let filenameNoExt = "filename/no-ext"
  /** file-size */
  static let fileSize = "file-size"
  /** estimated-frame-count */
  static let estimatedFrameCount = "estimated-frame-count"
  /** estimated-frame-number */
  static let estimatedFrameNumber = "estimated-frame-number"
  /** path */
  static let path = "path"
  /** stream-open-filename */
  static let streamOpenFilename = "stream-open-filename"
  /** media-title */
  static let mediaTitle = "media-title"
  /** file-format */
  static let fileFormat = "file-format"
  /** current-demuxer */
  static let currentDemuxer = "current-demuxer"
  /** stream-path */
  static let streamPath = "stream-path"
  /** stream-pos */
  static let streamPos = "stream-pos"
  /** stream-end */
  static let streamEnd = "stream-end"
  /** duration */
  static let duration = "duration"
  /** avsync */
  static let avsync = "avsync"
  /** total-avsync-change */
  static let totalAvsyncChange = "total-avsync-change"
  /** decoder-frame-drop-count */
  static let decoderFrameDropCount = "decoder-frame-drop-count"
  /** frame-drop-count */
  static let frameDropCount = "frame-drop-count"
  /** mistimed-frame-count */
  static let mistimedFrameCount = "mistimed-frame-count"
  /** vsync-ratio */
  static let vsyncRatio = "vsync-ratio"
  /** vo-delayed-frame-count */
  static let voDelayedFrameCount = "vo-delayed-frame-count"
  /** percent-pos */
  static let percentPos = "percent-pos"
  /** time-pos */
  static let timePos = "time-pos"
  /** time-start */
  static let timeStart = "time-start"
  /** time-remaining */
  static let timeRemaining = "time-remaining"
  /** audio-pts */
  static let audioPts = "audio-pts"
  /** playtime-remaining */
  static let playtimeRemaining = "playtime-remaining"
  /** playback-time */
  static let playbackTime = "playback-time"
  /** chapter */
  static let chapter = "chapter"
  /** edition */
  static let edition = "edition"
  /** current-edition */
  static let currentEdition = "current-edition"
  /** chapters */
  static let chapters = "chapters"
  /** editions */
  static let editions = "editions"
  /** edition-list */
  static let editionList = "edition-list"
  /** edition-list/count */
  static let editionListCount = "edition-list/count"
  /** edition-list/N/id */
  static func editionListNId(_ n: Int) -> String {
    return "edition-list/\(n)/id"
  }
  /** edition-list/N/default */
  static func editionListNDefault(_ n: Int) -> String {
    return "edition-list/\(n)/default"
  }
  /** edition-list/N/title */
  static func editionListNTitle(_ n: Int) -> String {
    return "edition-list/\(n)/title"
  }
  /** metadata */
  static let metadata = "metadata"
  /** metadata/list/count */
  static let metadataListCount = "metadata/list/count"
  /** metadata/list/N/key */
  static func metadataListNKey(_ n: Int) -> String {
    return "metadata/list/\(n)/key"
  }
  /** metadata/list/N/value */
  static func metadataListNValue(_ n: Int) -> String {
    return "metadata/list/\(n)/value"
  }
  /** filtered-metadata */
  static let filteredMetadata = "filtered-metadata"
  /** chapter-metadata */
  static let chapterMetadata = "chapter-metadata"
  /** idle-active */
  static let idleActive = "idle-active"
  /** core-idle */
  static let coreIdle = "core-idle"
  /** cache-speed */
  static let cacheSpeed = "cache-speed"
  /** demuxer-cache-duration */
  static let demuxerCacheDuration = "demuxer-cache-duration"
  /** demuxer-cache-time */
  static let demuxerCacheTime = "demuxer-cache-time"
  /** demuxer-cache-idle */
  static let demuxerCacheIdle = "demuxer-cache-idle"
  /** demuxer-cache-state */
  static let demuxerCacheState = "demuxer-cache-state"
  /** demuxer-via-network */
  static let demuxerViaNetwork = "demuxer-via-network"
  /** demuxer-start-time */
  static let demuxerStartTime = "demuxer-start-time"
  /** paused-for-cache */
  static let pausedForCache = "paused-for-cache"
  /** cache-buffering-state */
  static let cacheBufferingState = "cache-buffering-state"
  /** eof-reached */
  static let eofReached = "eof-reached"
  /** seeking */
  static let seeking = "seeking"
  /** mixer-active */
  static let mixerActive = "mixer-active"
  /** ao-volume */
  static let aoVolume = "ao-volume"
  /** ao-mute */
  static let aoMute = "ao-mute"
  /** audio-codec */
  static let audioCodec = "audio-codec"
  /** audio-codec-name */
  static let audioCodecName = "audio-codec-name"
  /** audio-params */
  static let audioParams = "audio-params"
  /** audio-params/format */
  static let audioParamsFormat = "audio-params/format"
  /** audio-params/samplerate */
  static let audioParamsSamplerate = "audio-params/samplerate"
  /** audio-params/channels */
  static let audioParamsChannels = "audio-params/channels"
  /** audio-params/hr-channels */
  static let audioParamsHrChannels = "audio-params/hr-channels"
  /** audio-params/channel-count */
  static let audioParamsChannelCount = "audio-params/channel-count"
  /** audio-out-params */
  static let audioOutParams = "audio-out-params"
  /** colormatrix */
  static let colormatrix = "colormatrix"
  /** colormatrix-input-range */
  static let colormatrixInputRange = "colormatrix-input-range"
  /** colormatrix-primaries */
  static let colormatrixPrimaries = "colormatrix-primaries"
  /** hwdec */
  static let hwdec = "hwdec"
  /** hwdec-current */
  static let hwdecCurrent = "hwdec-current"
  /** hwdec-interop */
  static let hwdecInterop = "hwdec-interop"
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
  /** video-params/average-bpp */
  static let videoParamsAverageBpp = "video-params/average-bpp"
  /** video-params/plane-depth */
  static let videoParamsPlaneDepth = "video-params/plane-depth"
  /** video-params/w */
  static let videoParamsW = "video-params/w"
  /** video-params/h */
  static let videoParamsH = "video-params/h"
  /** video-params/dw */
  static let videoParamsDw = "video-params/dw"
  /** video-params/dh */
  static let videoParamsDh = "video-params/dh"
  /** video-params/aspect */
  static let videoParamsAspect = "video-params/aspect"
  /** video-params/par */
  static let videoParamsPar = "video-params/par"
  /** video-params/colormatrix */
  static let videoParamsColormatrix = "video-params/colormatrix"
  /** video-params/colorlevels */
  static let videoParamsColorlevels = "video-params/colorlevels"
  /** video-params/primaries */
  static let videoParamsPrimaries = "video-params/primaries"
  /** video-params/gamma */
  static let videoParamsGamma = "video-params/gamma"
  /** video-params/sig-peak */
  static let videoParamsSigPeak = "video-params/sig-peak"
  /** video-params/light */
  static let videoParamsLight = "video-params/light"
  /** video-params/chroma-location */
  static let videoParamsChromaLocation = "video-params/chroma-location"
  /** video-params/rotate */
  static let videoParamsRotate = "video-params/rotate"
  /** video-params/stereo-in */
  static let videoParamsStereoIn = "video-params/stereo-in"
  /** dwidth */
  static let dwidth = "dwidth"
  /** dheight */
  static let dheight = "dheight"
  /** video-dec-params */
  static let videoDecParams = "video-dec-params"
  /** video-out-params */
  static let videoOutParams = "video-out-params"
  /** video-frame-info */
  static let videoFrameInfo = "video-frame-info"
  /** container-fps */
  static let containerFps = "container-fps"
  /** estimated-vf-fps */
  static let estimatedVfFps = "estimated-vf-fps"
  /** window-scale */
  static let windowScale = "window-scale"
  /** current-window-scale */
  static let currentWindowScale = "current-window-scale"
  /** display-names */
  static let displayNames = "display-names"
  /** display-fps */
  static let displayFps = "display-fps"
  /** estimated-display-fps */
  static let estimatedDisplayFps = "estimated-display-fps"
  /** vsync-jitter */
  static let vsyncJitter = "vsync-jitter"
  /** display-hidpi-scale */
  static let displayHidpiScale = "display-hidpi-scale"
  /** video-aspect */
  static let videoAspect = "video-aspect"
  /** osd-width */
  static let osdWidth = "osd-width"
  /** osd-height */
  static let osdHeight = "osd-height"
  /** osd-par */
  static let osdPar = "osd-par"
  /** osd-dimensions */
  static let osdDimensions = "osd-dimensions"
  /** sub-text */
  static let subText = "sub-text"
  /** sub-start */
  static let subStart = "sub-start"
  /** sub-end */
  static let subEnd = "sub-end"
  /** playlist-pos */
  static let playlistPos = "playlist-pos"
  /** playlist-pos-1 */
  static let playlistPos1 = "playlist-pos-1"
  /** playlist-count */
  static let playlistCount = "playlist-count"
  /** playlist */
  static let playlist = "playlist"
  /** playlistCount1 */
  static let playlistCount1 = "playlistCount1"
  /** playlist/N/filename */
  static func playlistNFilename(_ n: Int) -> String {
    return "playlist/\(n)/filename"
  }
  /** playlist/N/current */
  static func playlistNCurrent(_ n: Int) -> String {
    return "playlist/\(n)/current"
  }
  /** playlist/N/playing */
  static func playlistNPlaying(_ n: Int) -> String {
    return "playlist/\(n)/playing"
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
  /** track-list/N/ff-index */
  static func trackListNFfIndex(_ n: Int) -> String {
    return "track-list/\(n)/ff-index"
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
  /** track-list/N/demux-bitrate */
  static func trackListNDemuxBitrate(_ n: Int) -> String {
    return "track-list/\(n)/demux-bitrate"
  }
  /** track-list/N/demux-rotation */
  static func trackListNDemuxRotation(_ n: Int) -> String {
    return "track-list/\(n)/demux-rotation"
  }
  /** track-list/N/demux-par */
  static func trackListNDemuxPar(_ n: Int) -> String {
    return "track-list/\(n)/demux-par"
  }
  /** track-list/N/audio-channels */
  static func trackListNAudioChannels(_ n: Int) -> String {
    return "track-list/\(n)/audio-channels"
  }
  /** track-list/N/replaygain-track-peak */
  static func trackListNReplaygainTrackPeak(_ n: Int) -> String {
    return "track-list/\(n)/replaygain-track-peak"
  }
  /** track-list/N/replaygain-track-gain */
  static func trackListNReplaygainTrackGain(_ n: Int) -> String {
    return "track-list/\(n)/replaygain-track-gain"
  }
  /** track-list/N/replaygain-album-peak */
  static func trackListNReplaygainAlbumPeak(_ n: Int) -> String {
    return "track-list/\(n)/replaygain-album-peak"
  }
  /** track-list/N/replaygain-album-gain */
  static func trackListNReplaygainAlbumGain(_ n: Int) -> String {
    return "track-list/\(n)/replaygain-album-gain"
  }
  /** chapter-list */
  static let chapterList = "chapter-list"
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
  /** seekable */
  static let seekable = "seekable"
  /** partially-seekable */
  static let partiallySeekable = "partially-seekable"
  /** playback-abort */
  static let playbackAbort = "playback-abort"
  /** cursor-autohide */
  static let cursorAutohide = "cursor-autohide"
  /** osd-sym-cc */
  static let osdSymCc = "osd-sym-cc"
  /** osd-ass-cc */
  static let osdAssCc = "osd-ass-cc"
  /** vo-configured */
  static let voConfigured = "vo-configured"
  /** vo-passes */
  static let voPasses = "vo-passes"
  /** vo-passes/TYPE/count */
  static let voPassesTYPECount = "vo-passes/TYPE/count"
  /** vo-passes/TYPE/N/desc */
  static func voPassesTYPENDesc(_ n: Int) -> String {
    return "vo-passes/TYPE/\(n)/desc"
  }
  /** vo-passes/TYPE/N/last */
  static func voPassesTYPENLast(_ n: Int) -> String {
    return "vo-passes/TYPE/\(n)/last"
  }
  /** vo-passes/TYPE/N/avg */
  static func voPassesTYPENAvg(_ n: Int) -> String {
    return "vo-passes/TYPE/\(n)/avg"
  }
  /** vo-passes/TYPE/N/peak */
  static func voPassesTYPENPeak(_ n: Int) -> String {
    return "vo-passes/TYPE/\(n)/peak"
  }
  /** vo-passes/TYPE/N/count */
  static func voPassesTYPENCount(_ n: Int) -> String {
    return "vo-passes/TYPE/\(n)/count"
  }
  /** vo-passes/TYPE/N/samples/M */
  static func voPassesTYPENSamplesM(_ n: Int) -> String {
    return "vo-passes/TYPE/\(n)/samples/M"
  }
  /** video-bitrate */
  static let videoBitrate = "video-bitrate"
  /** audio-bitrate */
  static let audioBitrate = "audio-bitrate"
  /** sub-bitrate */
  static let subBitrate = "sub-bitrate"
  /** packet-video-bitrate */
  static let packetVideoBitrate = "packet-video-bitrate"
  /** packet-audio-bitrate */
  static let packetAudioBitrate = "packet-audio-bitrate"
  /** packet-sub-bitrate */
  static let packetSubBitrate = "packet-sub-bitrate"
  /** audio-device-list */
  static let audioDeviceList = "audio-device-list"
  /** audio-device */
  static let audioDevice = "audio-device"
  /** current-vo */
  static let currentVo = "current-vo"
  /** current-ao */
  static let currentAo = "current-ao"
  /** shared-script-properties */
  static let sharedScriptProperties = "shared-script-properties"
  /** working-directory */
  static let workingDirectory = "working-directory"
  /** protocol-list */
  static let protocolList = "protocol-list"
  /** decoder-list */
  static let decoderList = "decoder-list"
  /** encoder-list */
  static let encoderList = "encoder-list"
  /** demuxer-lavf-list */
  static let demuxerLavfList = "demuxer-lavf-list"
  /** mpv-version */
  static let mpvVersion = "mpv-version"
  /** mpv-configuration */
  static let mpvConfiguration = "mpv-configuration"
  /** ffmpeg-version */
  static let ffmpegVersion = "ffmpeg-version"
  /** options/<name> */
  static func options(_ name: String) -> String {
    return "options/\(name)"
  }
  /** file-local-options/<name> */
  static func fileLocalOptions(_ name: String) -> String {
    return "file-local-options/\(name)"
  }
  /** option-info/<name> */
  static func optionInfo(_ name: String) -> String {
    return "option-info/\(name)"
  }
  /** option-info/<name>/name */
  static func optionInfoName(_ name: String) -> String {
    return "option-info/\(name)/name"
  }
  /** option-info/<name>/type */
  static func optionInfoType(_ name: String) -> String {
    return "option-info/\(name)/type"
  }
  /** option-info/<name>/set-from-commandline */
  static func optionInfoSetFromCommandline(_ name: String) -> String {
    return "option-info/\(name)/set-from-commandline"
  }
  /** option-info/<name>/set-locally */
  static func optionInfoSetLocally(_ name: String) -> String {
    return "option-info/\(name)/set-locally"
  }
  /** option-info/<name>/default-value */
  static func optionInfoDefaultValue(_ name: String) -> String {
    return "option-info/\(name)/default-value"
  }
  /** option-info/<name>/min */
  static func optionInfoMin(_ name: String) -> String {
    return "option-info/\(name)/min"
  }
  /** option-info/<name>/max */
  static func optionInfoMax(_ name: String) -> String {
    return "option-info/\(name)/max"
  }
  /** option-info/<name>/choices */
  static func optionInfoChoices(_ name: String) -> String {
    return "option-info/\(name)/choices"
  }
  /** property-list */
  static let propertyList = "property-list"
  /** profile-list */
  static let profileList = "profile-list"
  /** command-list */
  static let commandList = "command-list"
  /** input-bindings */
  static let inputBindings = "input-bindings"
}
