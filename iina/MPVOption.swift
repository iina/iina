import Foundation

struct MPVOption {
  struct TrackSelection {
    /** --alang=<languagecode[ */
    static let alang = "alang"
    /** --slang=<languagecode[ */
    static let slang = "slang"
    /** --aid=<ID|auto|no> */
    static let aid = "aid"
    /** --sid=<ID|auto|no> */
    static let sid = "sid"
    /** --vid=<ID|auto|no> */
    static let vid = "vid"
  }

  struct PlaybackControl {
    /** --speed=<0.01-100> */
    static let speed = "speed"
    /** --pause */
    static let pause = "pause"
    /** --loop-playlist=<N|inf|force|no> */
    static let loopPlaylist = "loop-playlist"
    /** --loop-file=<N|inf|no> */
    static let loopFile = "loop-file"
    /** --ab-loop-a=<time> */
    static let abLoopA = "ab-loop-a"
    /** --ab-loop-b=<time> */
    static let abLoopB = "ab-loop-b"
  }

  struct ProgramBehavior {
    /** --log-file=<path> */
    static let logFile = "log-file"
    /** --config-dir=<path> */
    static let configDir = "config-dir"
    /** --reset-on-next-file=<all|option1 */
    static let resetOnNextFile = "reset-on-next-file"
    /** --ytdl */
    static let ytdl = "ytdl"
    /** --ytdl-raw-options=<key>=<value>[ */
    static let ytdlRawOptions = "ytdl-raw-options"
  }

  struct WatchLater {
    /** --save-position-on-quit */
    static let savePositionOnQuit = "save-position-on-quit"
  }

  struct Video {
    /** --vo=<driver> */
    static let vo = "vo"
    /** --override-display-fps=<fps> */
    static let overrideDisplayFps = "override-display-fps"
    /** --hwdec=<api> */
    static let hwdec = "hwdec"
    /** --gpu-hwdec-interop=<auto|all|no|name> */
    static let gpuHwdecInterop = "gpu-hwdec-interop"
    /** --video-rotate=<0-359|no> */
    static let videoRotate = "video-rotate"
    /** --deinterlace=<yes|no> */
    static let deinterlace = "deinterlace"
    /** --vd-lavc-threads=<N> */
    static let vdLavcThreads = "vd-lavc-threads"
  }

  struct Audio {
    /** --audio-device=<name> */
    static let audioDevice = "audio-device"
    /** --audio-spdif=<codecs> */
    static let audioSpdif = "audio-spdif"
    /** --volume=<value> */
    static let volume = "volume"
    /** --audio-delay=<sec> */
    static let audioDelay = "audio-delay"
    /** --mute=<yes|no|auto> */
    static let mute = "mute"
    /** --ad-lavc-threads=<0-16> */
    static let adLavcThreads = "ad-lavc-threads"
    /** --volume-max=<100.0-1000.0> */
    static let volumeMax = "volume-max"
  }

  struct Subtitles {
    /** --sub-delay=<sec> */
    static let subDelay = "sub-delay"
    /** --secondary-sid=<ID|auto|no> */
    static let secondarySid = "secondary-sid"
    /** --sub-scale=<0-100> */
    static let subScale = "sub-scale"
    /** --sub-scale-by-window=<yes|no> */
    static let subScaleByWindow = "sub-scale-by-window"
    /** --sub-pos=<0-150> */
    static let subPos = "sub-pos"
    /** --sub-ass-override=<yes|no|force|scale|strip> */
    static let subAssOverride = "sub-ass-override"
    /** --sub-ass-force-margins */
    static let subAssForceMargins = "sub-ass-force-margins"
    /** --sub-use-margins */
    static let subUseMargins = "sub-use-margins"
    /** --sub-auto=<no|exact|fuzzy|all> */
    static let subAuto = "sub-auto"
    /** --sub-codepage=<codepage> */
    static let subCodepage = "sub-codepage"
    /** --sub-font=<name> */
    static let subFont = "sub-font"
    /** --sub-font-size=<size> */
    static let subFontSize = "sub-font-size"
    /** --sub-back-color=<color> */
    static let subBackColor = "sub-back-color"
    /** --sub-blur=<0..20.0> */
    static let subBlur = "sub-blur"
    /** --sub-bold=<yes|no> */
    static let subBold = "sub-bold"
    /** --sub-italic=<yes|no> */
    static let subItalic = "sub-italic"
    /** --sub-border-color=<color> */
    static let subBorderColor = "sub-border-color"
    /** --sub-border-size=<size> */
    static let subBorderSize = "sub-border-size"
    /** --sub-color=<color> */
    static let subColor = "sub-color"
    /** --sub-margin-x=<size> */
    static let subMarginX = "sub-margin-x"
    /** --sub-margin-y=<size> */
    static let subMarginY = "sub-margin-y"
    /** --sub-align-x=<left|center|right> */
    static let subAlignX = "sub-align-x"
    /** --sub-align-y=<top|center|bottom> */
    static let subAlignY = "sub-align-y"
    /** --sub-shadow-color=<color> */
    static let subShadowColor = "sub-shadow-color"
    /** --sub-shadow-offset=<size> */
    static let subShadowOffset = "sub-shadow-offset"
    /** --sub-spacing=<size> */
    static let subSpacing = "sub-spacing"
  }

  struct Window {
    /** --fullscreen */
    static let fullscreen = "fullscreen"
    /** --keep-open=<yes|no|always> */
    static let keepOpen = "keep-open"
    /** --ontop */
    static let ontop = "ontop"
    /** --geometry=<[W[xH]][+-x+-y][/WS]> */
    static let geometry = "geometry"
    /** --window-scale=<factor> */
    static let windowScale = "window-scale"
    /** --keepaspect */
    static let keepaspect = "keepaspect"
  }

  struct Equalizer {
    /** --brightness=<-100-100> */
    static let brightness = "brightness"
    /** --contrast=<-100-100> */
    static let contrast = "contrast"
    /** --saturation=<-100-100> */
    static let saturation = "saturation"
    /** --gamma=<-100-100> */
    static let gamma = "gamma"
    /** --hue=<-100-100> */
    static let hue = "hue"
  }

  struct Demuxer {
    /** --demuxer-max-bytes=<bytesize> */
    static let demuxerMaxBytes = "demuxer-max-bytes"
  }

  struct Input {
    /** --input-conf=<filename> */
    static let inputConf = "input-conf"
    /** --input-media-keys=<yes|no> */
    static let inputMediaKeys = "input-media-keys"
  }

  struct OSD {
    /** --osd-level=<0-3> */
    static let osdLevel = "osd-level"
  }

  struct Screenshot {
    /** --screenshot-format=<type> */
    static let screenshotFormat = "screenshot-format"
    /** --screenshot-tag-colorspace=<yes|no> */
    static let screenshotTagColorspace = "screenshot-tag-colorspace"
    /** --screenshot-template=<template> */
    static let screenshotTemplate = "screenshot-template"
    /** --screenshot-directory=<path> */
    static let screenshotDirectory = "screenshot-directory"
  }

  struct Cache {
    /** --cache=<yes|no|auto> */
    static let cache = "cache"
    /** --cache-secs=<seconds> */
    static let cacheSecs = "cache-secs"
  }

  struct Network {
    /** --user-agent=<string> */
    static let userAgent = "user-agent"
    /** --rtsp-transport=<lavf|udp|udp_multicast|tcp|http> */
    static let rtspTransport = "rtsp-transport"
  }

  struct GPURendererOptions {
    /** --target-prim=<value> */
    static let targetPrim = "target-prim"
    /** --target-trc=<value> */
    static let targetTrc = "target-trc"
    /** --target-peak=<auto|nits> */
    static let targetPeak = "target-peak"
    /** --tone-mapping=<value> */
    static let toneMapping = "tone-mapping"
    /** --tone-mapping-param=<value> */
    static let toneMappingParam = "tone-mapping-param"
    /** --icc-profile=<file> */
    static let iccProfile = "icc-profile"
  }
}
