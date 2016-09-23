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
    /** --ff-aid=<ID|auto|no> */
    static let ffAid = "ff-aid"
    /** --ff-sid=<ID|auto|no> */
    static let ffSid = "ff-sid"
    /** --ff-vid=<ID|auto|no> */
    static let ffVid = "ff-vid"
    /** --edition=<ID|auto> */
    static let edition = "edition"
  }

  struct PlaybackControl {
    /** --start=<relative time> */
    static let start = "start"
    /** --end=<time> */
    static let end = "end"
    /** --length=<relative time> */
    static let length = "length"
    /** --rebase-start-time=<yes|no> */
    static let rebaseStartTime = "rebase-start-time"
    /** --speed=<0.01-100> */
    static let speed = "speed"
    /** --loop=<N|inf|force|no> */
    static let loop = "loop"
    /** --pause */
    static let pause = "pause"
    /** --shuffle */
    static let shuffle = "shuffle"
    /** --chapter=<start[-end]> */
    static let chapter = "chapter"
    /** --playlist-start=<auto|index> */
    static let playlistStart = "playlist-start"
    /** --playlist=<filename> */
    static let playlist = "playlist"
    /** --chapter-merge-threshold=<number> */
    static let chapterMergeThreshold = "chapter-merge-threshold"
    /** --chapter-seek-threshold=<seconds> */
    static let chapterSeekThreshold = "chapter-seek-threshold"
    /** --hr-seek=<no|absolute|yes> */
    static let hrSeek = "hr-seek"
    /** --hr-seek-demuxer-offset=<seconds> */
    static let hrSeekDemuxerOffset = "hr-seek-demuxer-offset"
    /** --hr-seek-framedrop=<yes|no> */
    static let hrSeekFramedrop = "hr-seek-framedrop"
    /** --index=<mode> */
    static let index = "index"
    /** --load-unsafe-playlists */
    static let loadUnsafePlaylists = "load-unsafe-playlists"
    /** --loop-file=<N|inf|no> */
    static let loopFile = "loop-file"
    /** --ab-loop-a=<time> */
    static let abLoopA = "ab-loop-a"
    /** --ab-loop-b=<time> */
    static let abLoopB = "ab-loop-b"
    /** --ordered-chapters */
    static let orderedChapters = "ordered-chapters"
    /** --no-ordered-chapters */
    static let noOrderedChapters = "no-ordered-chapters"
    /** --ordered-chapters-files=<playlist-file> */
    static let orderedChaptersFiles = "ordered-chapters-files"
    /** --chapters-file=<filename> */
    static let chaptersFile = "chapters-file"
    /** --sstep=<sec> */
    static let sstep = "sstep"
    /** --stop-playback-on-init-failure=<yes|no> */
    static let stopPlaybackOnInitFailure = "stop-playback-on-init-failure"
  }

  struct ProgramBehavior {
    /** --help */
    static let help = "help"
    /** --h */
    static let h = "h"
    /** --version */
    static let version = "version"
    /** --no-config */
    static let noConfig = "no-config"
    /** --list-options */
    static let listOptions = "list-options"
    /** --list-properties */
    static let listProperties = "list-properties"
    /** --list-protocols */
    static let listProtocols = "list-protocols"
    /** --log-file=<path> */
    static let logFile = "log-file"
    /** --config-dir=<path> */
    static let configDir = "config-dir"
    /** --save-position-on-quit */
    static let savePositionOnQuit = "save-position-on-quit"
    /** --dump-stats=<filename> */
    static let dumpStats = "dump-stats"
    /** --idle=<no|yes|once> */
    static let idle = "idle"
    /** --include=<configuration-file> */
    static let include = "include"
    /** --load-scripts=<yes|no> */
    static let loadScripts = "load-scripts"
    /** --script=<filename> */
    static let script = "script"
    /** --script-opts=key1=value1 */
    static let scriptOpts = "script-opts"
    /** --merge-files */
    static let mergeFiles = "merge-files"
    /** --no-resume-playback */
    static let noResumePlayback = "no-resume-playback"
    /** --profile=<profile1 */
    static let profile = "profile"
    /** --reset-on-next-file=<all|option1 */
    static let resetOnNextFile = "reset-on-next-file"
    /** --write-filename-in-watch-later-config */
    static let writeFilenameInWatchLaterConfig = "write-filename-in-watch-later-config"
    /** --ignore-path-in-watch-later-config */
    static let ignorePathInWatchLaterConfig = "ignore-path-in-watch-later-config"
    /** --show-profile=<profile> */
    static let showProfile = "show-profile"
    /** --use-filedir-conf */
    static let useFiledirConf = "use-filedir-conf"
    /** --ytdl */
    static let ytdl = "ytdl"
    /** --no-ytdl */
    static let noYtdl = "no-ytdl"
    /** --ytdl-format=<best|worst|mp4|webm|...> */
    static let ytdlFormat = "ytdl-format"
    /** --ytdl-raw-options=<key>=<value>[ */
    static let ytdlRawOptions = "ytdl-raw-options"
  }

  struct Video {
    /** --vo=<driver> */
    static let vo = "vo"
    /** --vd=<[+|-]family1:(*|decoder1) */
    static let vd = "vd"
    /** --vf=<filter1[=parameter1:parameter2:...] */
    static let vf = "vf"
    /** --untimed */
    static let untimed = "untimed"
    /** --framedrop=<mode> */
    static let framedrop = "framedrop"
    /** --display-fps=<fps> */
    static let displayFps = "display-fps"
    /** --hwdec=<api> */
    static let hwdec = "hwdec"
    /** --hwdec-preload=<api> */
    static let hwdecPreload = "hwdec-preload"
    /** --videotoolbox-format=<name> */
    static let videotoolboxFormat = "videotoolbox-format"
    /** --panscan=<0.0-1.0> */
    static let panscan = "panscan"
    /** --video-aspect=<ratio|no> */
    static let videoAspect = "video-aspect"
    /** --video-aspect-method=<hybrid|bitstream|container> */
    static let videoAspectMethod = "video-aspect-method"
    /** --video-unscaled=<no|yes|downscale-big> */
    static let videoUnscaled = "video-unscaled"
    /** --video-pan-x=<value> */
    static let videoPanX = "video-pan-x"
    /** --video-pan-y=<value> */
    static let videoPanY = "video-pan-y"
    /** --video-rotate=<0-359|no> */
    static let videoRotate = "video-rotate"
    /** --video-stereo-mode=<no|mode> */
    static let videoStereoMode = "video-stereo-mode"
    /** --video-zoom=<value> */
    static let videoZoom = "video-zoom"
    /** --video-align-x=<-1-1> */
    static let videoAlignX = "video-align-x"
    /** --video-align-y=<-1-1> */
    static let videoAlignY = "video-align-y"
    /** --correct-pts */
    static let correctPts = "correct-pts"
    /** --no-correct-pts */
    static let noCorrectPts = "no-correct-pts"
    /** --fps=<float> */
    static let fps = "fps"
    /** --deinterlace=<yes|no|auto> */
    static let deinterlace = "deinterlace"
    /** --field-dominance=<auto|top|bottom> */
    static let fieldDominance = "field-dominance"
    /** --frames=<number> */
    static let frames = "frames"
    /** --video-output-levels=<outputlevels> */
    static let videoOutputLevels = "video-output-levels"
    /** --hwdec-codecs=<codec1 */
    static let hwdecCodecs = "hwdec-codecs"
    /** --vd-lavc-check-hw-profile=<yes|no> */
    static let vdLavcCheckHwProfile = "vd-lavc-check-hw-profile"
    /** --vd-lavc-software-fallback=<yes|no|N> */
    static let vdLavcSoftwareFallback = "vd-lavc-software-fallback"
    /** --vd-lavc-bitexact */
    static let vdLavcBitexact = "vd-lavc-bitexact"
    /** --vd-lavc-fast */
    static let vdLavcFast = "vd-lavc-fast"
    /** --vd-lavc-o=<key>=<value>[ */
    static let vdLavcO = "vd-lavc-o"
    /** --vd-lavc-show-all=<yes|no> */
    static let vdLavcShowAll = "vd-lavc-show-all"
    /** --vd-lavc-skiploopfilter=<skipvalue> (H.264 only) */
    static let vdLavcSkiploopfilter = "vd-lavc-skiploopfilter"
    /** --vd-lavc-skipidct=<skipvalue> (MPEG-1/2 only) */
    static let vdLavcSkipidct = "vd-lavc-skipidct"
    /** --vd-lavc-skipframe=<skipvalue> */
    static let vdLavcSkipframe = "vd-lavc-skipframe"
    /** --vd-lavc-framedrop=<skipvalue> */
    static let vdLavcFramedrop = "vd-lavc-framedrop"
    /** --vd-lavc-threads=<N> */
    static let vdLavcThreads = "vd-lavc-threads"
  }

  struct Audio {
    /** --audio-pitch-correction=<yes|no> */
    static let audioPitchCorrection = "audio-pitch-correction"
    /** --audio-device=<name> */
    static let audioDevice = "audio-device"
    /** --audio-exclusive=<yes|no> */
    static let audioExclusive = "audio-exclusive"
    /** --audio-fallback-to-null=<yes|no> */
    static let audioFallbackToNull = "audio-fallback-to-null"
    /** --ao=<driver> */
    static let ao = "ao"
    /** --af=<filter1[=parameter1:parameter2:...] */
    static let af = "af"
    /** --audio-spdif=<codecs> */
    static let audioSpdif = "audio-spdif"
    /** --ad=<[+|-]family1:(*|decoder1) */
    static let ad = "ad"
    /** --volume=<value> */
    static let volume = "volume"
    /** --balance=<value> */
    static let balance = "balance"
    /** --audio-delay=<sec> */
    static let audioDelay = "audio-delay"
    /** --mute=<yes|no|auto> */
    static let mute = "mute"
    /** --softvol=<no|yes|auto> */
    static let softvol = "softvol"
    /** --audio-demuxer=<[+]name> */
    static let audioDemuxer = "audio-demuxer"
    /** --ad-lavc-ac3drc=<level> */
    static let adLavcAc3drc = "ad-lavc-ac3drc"
    /** --ad-lavc-downmix=<yes|no> */
    static let adLavcDownmix = "ad-lavc-downmix"
    /** --ad-lavc-threads=<0-16> */
    static let adLavcThreads = "ad-lavc-threads"
    /** --ad-lavc-o=<key>=<value>[ */
    static let adLavcO = "ad-lavc-o"
    /** --ad-spdif-dtshd=<yes|no> */
    static let adSpdifDtshd = "ad-spdif-dtshd"
    /** --dtshd */
    static let dtshd = "dtshd"
    /** --no-dtshd */
    static let noDtshd = "no-dtshd"
    /** --audio-channels=<auto-safe|auto|layouts> */
    static let audioChannels = "audio-channels"
    /** --audio-normalize-downmix=<yes|no> */
    static let audioNormalizeDownmix = "audio-normalize-downmix"
    /** --audio-display=<no|attachment> */
    static let audioDisplay = "audio-display"
    /** --audio-file=<filename> */
    static let audioFile = "audio-file"
    /** --audio-format=<format> */
    static let audioFormat = "audio-format"
    /** --audio-samplerate=<Hz> */
    static let audioSamplerate = "audio-samplerate"
    /** --gapless-audio=<no|yes|weak> */
    static let gaplessAudio = "gapless-audio"
    /** --initial-audio-sync */
    static let initialAudioSync = "initial-audio-sync"
    /** --no-initial-audio-sync */
    static let noInitialAudioSync = "no-initial-audio-sync"
    /** --volume-max=<100.0-1000.0> */
    static let volumeMax = "volume-max"
    /** --softvol-max=<...> */
    static let softvolMax = "softvol-max"
    /** --audio-file-auto=<no|exact|fuzzy|all> */
    static let audioFileAuto = "audio-file-auto"
    /** --no-audio-file-auto */
    static let noAudioFileAuto = "no-audio-file-auto"
    /** --audio-file-paths=<path1:path2:...> */
    static let audioFilePaths = "audio-file-paths"
    /** --audio-client-name=<name> */
    static let audioClientName = "audio-client-name"
    /** --volume-restore-data=<string> */
    static let volumeRestoreData = "volume-restore-data"
    /** --audio-buffer=<seconds> */
    static let audioBuffer = "audio-buffer"
    /** --audio-stream-silence=<yes|no> */
    static let audioStreamSilence = "audio-stream-silence"
    /** --audio-wait-open=<secs> */
    static let audioWaitOpen = "audio-wait-open"
  }

  struct Subtitles {
    /** --sub-demuxer=<[+]name> */
    static let subDemuxer = "sub-demuxer"
    /** --sub-delay=<sec> */
    static let subDelay = "sub-delay"
    /** --sub-file=subtitlefile */
    static let subFile = "sub-file"
    /** --secondary-sid=<ID|auto|no> */
    static let secondarySid = "secondary-sid"
    /** --sub-scale=<0-100> */
    static let subScale = "sub-scale"
    /** --sub-scale-by-window=<yes|no> */
    static let subScaleByWindow = "sub-scale-by-window"
    /** --sub-scale-with-window=<yes|no> */
    static let subScaleWithWindow = "sub-scale-with-window"
    /** --ass-scale-with-window=<yes|no> */
    static let assScaleWithWindow = "ass-scale-with-window"
    /** --embeddedfonts */
    static let embeddedfonts = "embeddedfonts"
    /** --no-embeddedfonts */
    static let noEmbeddedfonts = "no-embeddedfonts"
    /** --sub-pos=<0-100> */
    static let subPos = "sub-pos"
    /** --sub-speed=<0.1-10.0> */
    static let subSpeed = "sub-speed"
    /** --ass-force-style=<[Style.]Param=Value[ */
    static let assForceStyle = "ass-force-style"
    /** --ass-hinting=<none|light|normal|native> */
    static let assHinting = "ass-hinting"
    /** --ass-line-spacing=<value> */
    static let assLineSpacing = "ass-line-spacing"
    /** --ass-shaper=<simple|complex> */
    static let assShaper = "ass-shaper"
    /** --ass-styles=<filename> */
    static let assStyles = "ass-styles"
    /** --ass-style-override=<yes|no|force|signfs|strip> */
    static let assStyleOverride = "ass-style-override"
    /** --ass-force-margins */
    static let assForceMargins = "ass-force-margins"
    /** --sub-use-margins */
    static let subUseMargins = "sub-use-margins"
    /** --ass-vsfilter-aspect-compat=<yes|no> */
    static let assVsfilterAspectCompat = "ass-vsfilter-aspect-compat"
    /** --ass-vsfilter-blur-compat=<yes|no> */
    static let assVsfilterBlurCompat = "ass-vsfilter-blur-compat"
    /** --ass-vsfilter-color-compat=<basic|full|force-601|no> */
    static let assVsfilterColorCompat = "ass-vsfilter-color-compat"
    /** --stretch-dvd-subs=<yes|no> */
    static let stretchDvdSubs = "stretch-dvd-subs"
    /** --stretch-image-subs-to-screen=<yes|no> */
    static let stretchImageSubsToScreen = "stretch-image-subs-to-screen"
    /** --sub-ass */
    static let subAss = "sub-ass"
    /** --no-sub-ass */
    static let noSubAss = "no-sub-ass"
    /** --sub-auto=<no|exact|fuzzy|all> */
    static let subAuto = "sub-auto"
    /** --no-sub-auto */
    static let noSubAuto = "no-sub-auto"
    /** --sub-codepage=<codepage> */
    static let subCodepage = "sub-codepage"
    /** --sub-fix-timing */
    static let subFixTiming = "sub-fix-timing"
    /** --no-sub-fix-timing */
    static let noSubFixTiming = "no-sub-fix-timing"
    /** --sub-forced-only */
    static let subForcedOnly = "sub-forced-only"
    /** --sub-fps=<rate> */
    static let subFps = "sub-fps"
    /** --sub-gauss=<0.0-3.0> */
    static let subGauss = "sub-gauss"
    /** --sub-gray */
    static let subGray = "sub-gray"
    /** --sub-paths=<path1:path2:...> */
    static let subPaths = "sub-paths"
    /** --sub-visibility */
    static let subVisibility = "sub-visibility"
    /** --no-sub-visibility */
    static let noSubVisibility = "no-sub-visibility"
    /** --sub-clear-on-seek */
    static let subClearOnSeek = "sub-clear-on-seek"
    /** --teletext-page=<1-999> */
    static let teletextPage = "teletext-page"
  }

  struct Window {
    /** --title=<string> */
    static let title = "title"
    /** --screen=<default|0-32> */
    static let screen = "screen"
    /** --fullscreen */
    static let fullscreen = "fullscreen"
    /** --fs */
    static let fs = "fs"
    /** --fs-screen=<all|current|0-32> */
    static let fsScreen = "fs-screen"
    /** --keep-open=<yes|no|always> */
    static let keepOpen = "keep-open"
    /** --image-display-duration=<seconds|inf> */
    static let imageDisplayDuration = "image-display-duration"
    /** --force-window=<yes|no|immediate> */
    static let forceWindow = "force-window"
    /** --taskbar-progress */
    static let taskbarProgress = "taskbar-progress"
    /** --no-taskbar-progress */
    static let noTaskbarProgress = "no-taskbar-progress"
    /** --ontop */
    static let ontop = "ontop"
    /** --border */
    static let border = "border"
    /** --no-border */
    static let noBorder = "no-border"
    /** --fit-border */
    static let fitBorder = "fit-border"
    /** --no-fit-border */
    static let noFitBorder = "no-fit-border"
    /** --on-all-workspaces */
    static let onAllWorkspaces = "on-all-workspaces"
    /** --geometry=<[W[xH]][+-x+-y]> */
    static let geometry = "geometry"
    /** --autofit=<[W[xH]]> */
    static let autofit = "autofit"
    /** --autofit-larger=<[W[xH]]> */
    static let autofitLarger = "autofit-larger"
    /** --autofit-smaller=<[W[xH]]> */
    static let autofitSmaller = "autofit-smaller"
    /** --window-scale=<factor> */
    static let windowScale = "window-scale"
    /** --cursor-autohide=<number|no|always> */
    static let cursorAutohide = "cursor-autohide"
    /** --cursor-autohide-fs-only */
    static let cursorAutohideFsOnly = "cursor-autohide-fs-only"
    /** --no-fixed-vo */
    static let noFixedVo = "no-fixed-vo"
    /** --fixed-vo */
    static let fixedVo = "fixed-vo"
    /** --force-rgba-osd-rendering */
    static let forceRgbaOsdRendering = "force-rgba-osd-rendering"
    /** --force-window-position */
    static let forceWindowPosition = "force-window-position"
    /** --heartbeat-interval=<sec> */
    static let heartbeatInterval = "heartbeat-interval"
    /** --no-keepaspect */
    static let noKeepaspect = "no-keepaspect"
    /** --keepaspect */
    static let keepaspect = "keepaspect"
    /** --no-keepaspect-window */
    static let noKeepaspectWindow = "no-keepaspect-window"
    /** --keepaspect-window */
    static let keepaspectWindow = "keepaspect-window"
    /** --monitoraspect=<ratio> */
    static let monitoraspect = "monitoraspect"
    /** --monitorpixelaspect=<ratio> */
    static let monitorpixelaspect = "monitorpixelaspect"
    /** --stop-screensaver */
    static let stopScreensaver = "stop-screensaver"
    /** --no-stop-screensaver */
    static let noStopScreensaver = "no-stop-screensaver"
    /** --wid=<ID> */
    static let wid = "wid"
    /** --no-window-dragging */
    static let noWindowDragging = "no-window-dragging"
    /** --x11-name */
    static let x11Name = "x11-name"
    /** --x11-netwm=<yes|no|auto> */
    static let x11Netwm = "x11-netwm"
    /** --x11-bypass-compositor=<yes|no|fs-only|never> */
    static let x11BypassCompositor = "x11-bypass-compositor"
  }

  struct DiscDevices {
    /** --cdrom-device=<path> */
    static let cdromDevice = "cdrom-device"
    /** --dvd-device=<path> */
    static let dvdDevice = "dvd-device"
    /** --bluray-device=<path> */
    static let blurayDevice = "bluray-device"
    /** --cdda-speed=<value> */
    static let cddaSpeed = "cdda-speed"
    /** --cdda-paranoia=<0-2> */
    static let cddaParanoia = "cdda-paranoia"
    /** --cdda-sector-size=<value> */
    static let cddaSectorSize = "cdda-sector-size"
    /** --cdda-overlap=<value> */
    static let cddaOverlap = "cdda-overlap"
    /** --cdda-toc-bias */
    static let cddaTocBias = "cdda-toc-bias"
    /** --cdda-toc-offset=<value> */
    static let cddaTocOffset = "cdda-toc-offset"
    /** --cdda-skip=<yes|no> */
    static let cddaSkip = "cdda-skip"
    /** --cdda-cdtext=<yes|no> */
    static let cddaCdtext = "cdda-cdtext"
    /** --dvd-speed=<speed> */
    static let dvdSpeed = "dvd-speed"
    /** --dvd-angle=<ID> */
    static let dvdAngle = "dvd-angle"
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
    /** --demuxer=<[+]name> */
    static let demuxer = "demuxer"
    /** --demuxer-lavf-analyzeduration=<value> */
    static let demuxerLavfAnalyzeduration = "demuxer-lavf-analyzeduration"
    /** --demuxer-lavf-probescore=<1-100> */
    static let demuxerLavfProbescore = "demuxer-lavf-probescore"
    /** --demuxer-lavf-allow-mimetype=<yes|no> */
    static let demuxerLavfAllowMimetype = "demuxer-lavf-allow-mimetype"
    /** --demuxer-lavf-format=<name> */
    static let demuxerLavfFormat = "demuxer-lavf-format"
    /** --demuxer-lavf-hacks=<yes|no> */
    static let demuxerLavfHacks = "demuxer-lavf-hacks"
    /** --demuxer-lavf-genpts-mode=<no|lavf> */
    static let demuxerLavfGenptsMode = "demuxer-lavf-genpts-mode"
    /** --demuxer-lavf-o=<key>=<value>[ */
    static let demuxerLavfO = "demuxer-lavf-o"
    /** --demuxer-lavf-probesize=<value> */
    static let demuxerLavfProbesize = "demuxer-lavf-probesize"
    /** --demuxer-lavf-buffersize=<value> */
    static let demuxerLavfBuffersize = "demuxer-lavf-buffersize"
    /** --demuxer-lavf-cryptokey=<hexstring> */
    static let demuxerLavfCryptokey = "demuxer-lavf-cryptokey"
    /** --demuxer-mkv-subtitle-preroll=<yes|index|no> */
    static let demuxerMkvSubtitlePreroll = "demuxer-mkv-subtitle-preroll"
    /** --mkv-subtitle-preroll */
    static let mkvSubtitlePreroll = "mkv-subtitle-preroll"
    /** --demuxer-mkv-subtitle-preroll-secs=<value> */
    static let demuxerMkvSubtitlePrerollSecs = "demuxer-mkv-subtitle-preroll-secs"
    /** --demuxer-mkv-subtitle-preroll-secs-index=<value> */
    static let demuxerMkvSubtitlePrerollSecsIndex = "demuxer-mkv-subtitle-preroll-secs-index"
    /** --demuxer-mkv-probe-video-duration=<yes|no|full> */
    static let demuxerMkvProbeVideoDuration = "demuxer-mkv-probe-video-duration"
    /** --demuxer-rawaudio-channels=<value> */
    static let demuxerRawaudioChannels = "demuxer-rawaudio-channels"
    /** --demuxer-rawaudio-format=<value> */
    static let demuxerRawaudioFormat = "demuxer-rawaudio-format"
    /** --demuxer-rawaudio-rate=<value> */
    static let demuxerRawaudioRate = "demuxer-rawaudio-rate"
    /** --demuxer-rawvideo-fps=<value> */
    static let demuxerRawvideoFps = "demuxer-rawvideo-fps"
    /** --demuxer-rawvideo-w=<value> */
    static let demuxerRawvideoW = "demuxer-rawvideo-w"
    /** --demuxer-rawvideo-h=<value> */
    static let demuxerRawvideoH = "demuxer-rawvideo-h"
    /** --demuxer-rawvideo-format=<value> */
    static let demuxerRawvideoFormat = "demuxer-rawvideo-format"
    /** --demuxer-rawvideo-mp-format=<value> */
    static let demuxerRawvideoMpFormat = "demuxer-rawvideo-mp-format"
    /** --demuxer-rawvideo-codec=<value> */
    static let demuxerRawvideoCodec = "demuxer-rawvideo-codec"
    /** --demuxer-rawvideo-size=<value> */
    static let demuxerRawvideoSize = "demuxer-rawvideo-size"
    /** --demuxer-max-packets=<packets> */
    static let demuxerMaxPackets = "demuxer-max-packets"
    /** --demuxer-max-bytes=<bytes> */
    static let demuxerMaxBytes = "demuxer-max-bytes"
    /** --demuxer-thread=<yes|no> */
    static let demuxerThread = "demuxer-thread"
    /** --demuxer-readahead-secs=<seconds> */
    static let demuxerReadaheadSecs = "demuxer-readahead-secs"
    /** --force-seekable=<yes|no> */
    static let forceSeekable = "force-seekable"
  }

  struct Input {
    /** --native-keyrepeat */
    static let nativeKeyrepeat = "native-keyrepeat"
    /** --input-ar-delay */
    static let inputArDelay = "input-ar-delay"
    /** --input-ar-rate */
    static let inputArRate = "input-ar-rate"
    /** --input-conf=<filename> */
    static let inputConf = "input-conf"
    /** --no-input-default-bindings */
    static let noInputDefaultBindings = "no-input-default-bindings"
    /** --input-cmdlist */
    static let inputCmdlist = "input-cmdlist"
    /** --input-doubleclick-time=<milliseconds> */
    static let inputDoubleclickTime = "input-doubleclick-time"
    /** --input-keylist */
    static let inputKeylist = "input-keylist"
    /** --input-key-fifo-size=<2-65000> */
    static let inputKeyFifoSize = "input-key-fifo-size"
    /** --input-test */
    static let inputTest = "input-test"
    /** --input-file=<filename> */
    static let inputFile = "input-file"
    /** --input-terminal */
    static let inputTerminal = "input-terminal"
    /** --no-input-terminal */
    static let noInputTerminal = "no-input-terminal"
    /** --input-ipc-server=<filename> */
    static let inputIpcServer = "input-ipc-server"
    /** --input-appleremote=<yes|no> */
    static let inputAppleremote = "input-appleremote"
    /** --input-cursor */
    static let inputCursor = "input-cursor"
    /** --no-input-cursor */
    static let noInputCursor = "no-input-cursor"
    /** --input-media-keys=<yes|no> */
    static let inputMediaKeys = "input-media-keys"
    /** --input-right-alt-gr */
    static let inputRightAltGr = "input-right-alt-gr"
    /** --no-input-right-alt-gr */
    static let noInputRightAltGr = "no-input-right-alt-gr"
    /** --input-vo-keyboard=<yes|no> */
    static let inputVoKeyboard = "input-vo-keyboard"
    /** --input-app-events=<yes|no> */
    static let inputAppEvents = "input-app-events"
  }

  struct OSD {
    /** --osc */
    static let osc = "osc"
    /** --no-osc */
    static let noOsc = "no-osc"
    /** --no-osd-bar */
    static let noOsdBar = "no-osd-bar"
    /** --osd-bar */
    static let osdBar = "osd-bar"
    /** --osd-duration=<time> */
    static let osdDuration = "osd-duration"
    /** --osd-font=<name> */
    static let osdFont = "osd-font"
    /** --sub-text-font=<name> */
    static let subTextFont = "sub-text-font"
    /** --osd-font-size=<size> */
    static let osdFontSize = "osd-font-size"
    /** --sub-text-font-size=<size> */
    static let subTextFontSize = "sub-text-font-size"
    /** --osd-msg1=<string> */
    static let osdMsg1 = "osd-msg1"
    /** --osd-msg2=<string> */
    static let osdMsg2 = "osd-msg2"
    /** --osd-msg3=<string> */
    static let osdMsg3 = "osd-msg3"
    /** --osd-status-msg=<string> */
    static let osdStatusMsg = "osd-status-msg"
    /** --osd-playing-msg=<string> */
    static let osdPlayingMsg = "osd-playing-msg"
    /** --osd-bar-align-x=<-1-1> */
    static let osdBarAlignX = "osd-bar-align-x"
    /** --osd-bar-align-y=<-1-1> */
    static let osdBarAlignY = "osd-bar-align-y"
    /** --osd-bar-w=<1-100> */
    static let osdBarW = "osd-bar-w"
    /** --osd-bar-h=<0.1-50> */
    static let osdBarH = "osd-bar-h"
    /** --osd-back-color=<color> */
    static let osdBackColor = "osd-back-color"
    /** --sub-text-back-color=<color> */
    static let subTextBackColor = "sub-text-back-color"
    /** --osd-blur=<0..20.0> */
    static let osdBlur = "osd-blur"
    /** --sub-text-blur=<0..20.0> */
    static let subTextBlur = "sub-text-blur"
    /** --osd-bold=<yes|no> */
    static let osdBold = "osd-bold"
    /** --sub-text-bold=<yes|no> */
    static let subTextBold = "sub-text-bold"
    /** --osd-italic=<yes|no> */
    static let osdItalic = "osd-italic"
    /** --sub-text-italic=<yes|no> */
    static let subTextItalic = "sub-text-italic"
    /** --osd-border-color=<color> */
    static let osdBorderColor = "osd-border-color"
    /** --sub-text-border-color=<color> */
    static let subTextBorderColor = "sub-text-border-color"
    /** --osd-border-size=<size> */
    static let osdBorderSize = "osd-border-size"
    /** --sub-text-border-size=<size> */
    static let subTextBorderSize = "sub-text-border-size"
    /** --osd-color=<color> */
    static let osdColor = "osd-color"
    /** --sub-text-color=<color> */
    static let subTextColor = "sub-text-color"
    /** --osd-fractions */
    static let osdFractions = "osd-fractions"
    /** --osd-level=<0-3> */
    static let osdLevel = "osd-level"
    /** --osd-margin-x=<size> */
    static let osdMarginX = "osd-margin-x"
    /**  --sub-text-margin-x=<size> */
    static let subTextMarginX = "sub-text-margin-x"
    /** --osd-margin-y=<size> */
    static let osdMarginY = "osd-margin-y"
    /**  --sub-text-margin-y=<size> */
    static let subTextMarginY = "sub-text-margin-y"
    /** --osd-align-x=<left|center|right> */
    static let osdAlignX = "osd-align-x"
    /** --sub-text-align-x=... */
    static let subTextAlignX = "sub-text-align-x"
    /** --osd-align-y=<top|center|bottom> */
    static let osdAlignY = "osd-align-y"
    /** --sub-text-align-y=... */
    static let subTextAlignY = "sub-text-align-y"
    /** --osd-scale=<factor> */
    static let osdScale = "osd-scale"
    /** --osd-scale-by-window=<yes|no> */
    static let osdScaleByWindow = "osd-scale-by-window"
    /** --osd-shadow-color=<color> */
    static let osdShadowColor = "osd-shadow-color"
    /**  --sub-text-shadow-color=<color> */
    static let subTextShadowColor = "sub-text-shadow-color"
    /** --osd-shadow-offset=<size> */
    static let osdShadowOffset = "osd-shadow-offset"
    /**  --sub-text-shadow-offset=<size> */
    static let subTextShadowOffset = "sub-text-shadow-offset"
    /** --osd-spacing=<size> */
    static let osdSpacing = "osd-spacing"
    /**  --sub-text-spacing=<size> */
    static let subTextSpacing = "sub-text-spacing"
    /** --video-osd=<yes|no> */
    static let videoOsd = "video-osd"
  }

  struct Screenshot {
    /** --screenshot-format=<type> */
    static let screenshotFormat = "screenshot-format"
    /** --screenshot-tag-colorspace=<yes|no> */
    static let screenshotTagColorspace = "screenshot-tag-colorspace"
    /** --screenshot-high-bit-depth=<yes|no> */
    static let screenshotHighBitDepth = "screenshot-high-bit-depth"
    /** --screenshot-template=<template> */
    static let screenshotTemplate = "screenshot-template"
    /** --screenshot-directory=<path> */
    static let screenshotDirectory = "screenshot-directory"
    /** --screenshot-jpeg-quality=<0-100> */
    static let screenshotJpegQuality = "screenshot-jpeg-quality"
    /** --screenshot-jpeg-source-chroma=<yes|no> */
    static let screenshotJpegSourceChroma = "screenshot-jpeg-source-chroma"
    /** --screenshot-png-compression=<0-9> */
    static let screenshotPngCompression = "screenshot-png-compression"
    /** --screenshot-png-filter=<0-5> */
    static let screenshotPngFilter = "screenshot-png-filter"
  }

  struct SoftwareScaler {
    /** --sws-scaler=<name> */
    static let swsScaler = "sws-scaler"
    /** --sws-lgb=<0-100> */
    static let swsLgb = "sws-lgb"
    /** --sws-cgb=<0-100> */
    static let swsCgb = "sws-cgb"
    /** --sws-ls=<-100-100> */
    static let swsLs = "sws-ls"
    /** --sws-cs=<-100-100> */
    static let swsCs = "sws-cs"
    /** --sws-chs=<h> */
    static let swsChs = "sws-chs"
    /** --sws-cvs=<v> */
    static let swsCvs = "sws-cvs"
  }

  struct Terminal {
    /** --quiet */
    static let quiet = "quiet"
    /** --really-quiet */
    static let reallyQuiet = "really-quiet"
    /** --no-terminal */
    static let noTerminal = "no-terminal"
    /** --terminal */
    static let terminal = "terminal"
    /** --no-msg-color */
    static let noMsgColor = "no-msg-color"
    /** --msg-level=<module1=level1 */
    static let msgLevel = "msg-level"
    /** --term-osd=<auto|no|force> */
    static let termOsd = "term-osd"
    /** --term-osd-bar */
    static let termOsdBar = "term-osd-bar"
    /** --no-term-osd-bar */
    static let noTermOsdBar = "no-term-osd-bar"
    /** --term-osd-bar-chars=<string> */
    static let termOsdBarChars = "term-osd-bar-chars"
    /** --term-playing-msg=<string> */
    static let termPlayingMsg = "term-playing-msg"
    /** --term-status-msg=<string> */
    static let termStatusMsg = "term-status-msg"
    /** --msg-module */
    static let msgModule = "msg-module"
    /** --msg-time */
    static let msgTime = "msg-time"
  }

  struct Cache {
    /** --cache=<kBytes|yes|no|auto> */
    static let cache = "cache"
    /** --cache-default=<kBytes|no> */
    static let cacheDefault = "cache-default"
    /** --cache-initial=<kBytes> */
    static let cacheInitial = "cache-initial"
    /** --cache-seek-min=<kBytes> */
    static let cacheSeekMin = "cache-seek-min"
    /** --cache-backbuffer=<kBytes> */
    static let cacheBackbuffer = "cache-backbuffer"
    /** --cache-file=<TMP|path> */
    static let cacheFile = "cache-file"
    /** --cache-file-size=<kBytes> */
    static let cacheFileSize = "cache-file-size"
    /** --no-cache */
    static let noCache = "no-cache"
    /** --cache-secs=<seconds> */
    static let cacheSecs = "cache-secs"
    /** --cache-pause */
    static let cachePause = "cache-pause"
    /** --no-cache-pause */
    static let noCachePause = "no-cache-pause"
  }

  struct Network {
    /** --user-agent=<string> */
    static let userAgent = "user-agent"
    /** --cookies */
    static let cookies = "cookies"
    /** --no-cookies */
    static let noCookies = "no-cookies"
    /** --cookies-file=<filename> */
    static let cookiesFile = "cookies-file"
    /** --http-header-fields=<field1 */
    static let httpHeaderFields = "http-header-fields"
    /** --tls-ca-file=<filename> */
    static let tlsCaFile = "tls-ca-file"
    /** --tls-verify */
    static let tlsVerify = "tls-verify"
    /** --tls-cert-file */
    static let tlsCertFile = "tls-cert-file"
    /** --tls-key-file */
    static let tlsKeyFile = "tls-key-file"
    /** --referrer=<string> */
    static let referrer = "referrer"
    /** --network-timeout=<seconds> */
    static let networkTimeout = "network-timeout"
    /** --rtsp-transport=<lavf|udp|tcp|http> */
    static let rtspTransport = "rtsp-transport"
    /** --hls-bitrate=<no|min|max|<rate>> */
    static let hlsBitrate = "hls-bitrate"
  }

  struct DVB {
    /** --dvbin-card=<1-4> */
    static let dvbinCard = "dvbin-card"
    /** --dvbin-file=<filename> */
    static let dvbinFile = "dvbin-file"
    /** --dvbin-timeout=<1-30> */
    static let dvbinTimeout = "dvbin-timeout"
    /** --dvbin-full-transponder=<yes|no> */
    static let dvbinFullTransponder = "dvbin-full-transponder"
  }

  struct ALSAAudioOutputOptions {
    /** --alsa-device=<device> */
    static let alsaDevice = "alsa-device"
    /** --alsa-resample=yes */
    static let alsaResample = "alsa-resample"
    /** --alsa-mixer-device=<device> */
    static let alsaMixerDevice = "alsa-mixer-device"
    /** --alsa-mixer-name=<name> */
    static let alsaMixerName = "alsa-mixer-name"
    /** --alsa-mixer-index=<number> */
    static let alsaMixerIndex = "alsa-mixer-index"
    /** --alsa-non-interleaved */
    static let alsaNonInterleaved = "alsa-non-interleaved"
    /** --alsa-ignore-chmap */
    static let alsaIgnoreChmap = "alsa-ignore-chmap"
  }

  struct OpenGLRendererOptions {
    /** --opengl-dumb-mode=<yes|no> */
    static let openglDumbMode = "opengl-dumb-mode"
    /** --scale-param1=<value> */
    static let scaleParam1 = "scale-param1"
    /** --scale-param2=<value> */
    static let scaleParam2 = "scale-param2"
    /** --scale-blur=<value> */
    static let scaleBlur = "scale-blur"
    /** --scale-radius=<value> */
    static let scaleRadius = "scale-radius"
    /** --scale-antiring=<value> */
    static let scaleAntiring = "scale-antiring"
    /** --scale-window=<window> */
    static let scaleWindow = "scale-window"
    /** --scale-wparam=<window> */
    static let scaleWparam = "scale-wparam"
    /** --scaler-lut-size=<4..10> */
    static let scalerLutSize = "scaler-lut-size"
    /** --scaler-resizes-only */
    static let scalerResizesOnly = "scaler-resizes-only"
    /** --opengl-pbo */
    static let openglPbo = "opengl-pbo"
    /** --dither-depth=<N|no|auto> */
    static let ditherDepth = "dither-depth"
    /** --dither-size-fruit=<2-8> */
    static let ditherSizeFruit = "dither-size-fruit"
    /** --dither=<fruit|ordered|no> */
    static let dither = "dither"
    /** --temporal-dither */
    static let temporalDither = "temporal-dither"
    /** --temporal-dither-period=<1-128> */
    static let temporalDitherPeriod = "temporal-dither-period"
    /** --opengl-debug */
    static let openglDebug = "opengl-debug"
    /** --interpolation */
    static let interpolation = "interpolation"
    /** --opengl-swapinterval=<n> */
    static let openglSwapinterval = "opengl-swapinterval"
    /** --dscale=<filter> */
    static let dscale = "dscale"
    /** --cscale=<filter> */
    static let cscale = "cscale"
    /** --tscale=<filter> */
    static let tscale = "tscale"
    /** --tscale-clamp */
    static let tscaleClamp = "tscale-clamp"
    /** --interpolation-threshold=<0..1 */
    static let interpolationThreshold = "interpolation-threshold"
    /** --dscale-radius */
    static let dscaleRadius = "dscale-radius"
    /** --cscale-radius */
    static let cscaleRadius = "cscale-radius"
    /** --tscale-radius */
    static let tscaleRadius = "tscale-radius"
    /** --linear-scaling */
    static let linearScaling = "linear-scaling"
    /** --correct-downscaling */
    static let correctDownscaling = "correct-downscaling"
    /** --opengl-shaders=<files> */
    static let openglShaders = "opengl-shaders"
    /** --deband */
    static let deband = "deband"
    /** --deband-iterations=<1..16> */
    static let debandIterations = "deband-iterations"
    /** --deband-threshold=<0..4096> */
    static let debandThreshold = "deband-threshold"
    /** --deband-range=<1..64> */
    static let debandRange = "deband-range"
    /** --deband-grain=<0..4096> */
    static let debandGrain = "deband-grain"
    /** --sigmoid-upscaling */
    static let sigmoidUpscaling = "sigmoid-upscaling"
    /** --sigmoid-center */
    static let sigmoidCenter = "sigmoid-center"
    /** --sigmoid-slope */
    static let sigmoidSlope = "sigmoid-slope"
    /** --sharpen=<value> */
    static let sharpen = "sharpen"
    /** --opengl-glfinish */
    static let openglGlfinish = "opengl-glfinish"
    /** --opengl-waitvsync */
    static let openglWaitvsync = "opengl-waitvsync"
    /** --opengl-vsync-fences=<N> */
    static let openglVsyncFences = "opengl-vsync-fences"
    /** --opengl-dwmflush=<no|windowed|yes|auto> */
    static let openglDwmflush = "opengl-dwmflush"
    /** --opengl-dcomposition=<yes|no> */
    static let openglDcomposition = "opengl-dcomposition"
    /** --opengl-sw */
    static let openglSw = "opengl-sw"
    /** --opengl-backend=<sys> */
    static let openglBackend = "opengl-backend"
    /** --opengl-es=<mode> */
    static let openglEs = "opengl-es"
    /** --opengl-fbo-format=<fmt> */
    static let openglFboFormat = "opengl-fbo-format"
    /** --opengl-gamma=<0.1..2.0> */
    static let openglGamma = "opengl-gamma"
    /** --gamma-auto */
    static let gammaAuto = "gamma-auto"
    /** --target-prim=<value> */
    static let targetPrim = "target-prim"
    /** --target-trc=<value> */
    static let targetTrc = "target-trc"
    /** --target-brightness=<1..100000> */
    static let targetBrightness = "target-brightness"
    /** --hdr-tone-mapping=<value> */
    static let hdrToneMapping = "hdr-tone-mapping"
    /** --tone-mapping-param=<value> */
    static let toneMappingParam = "tone-mapping-param"
    /** --icc-profile=<file> */
    static let iccProfile = "icc-profile"
    /** --icc-profile-auto */
    static let iccProfileAuto = "icc-profile-auto"
    /** --icc-cache-dir=<dirname> */
    static let iccCacheDir = "icc-cache-dir"
    /** --icc-intent=<value> */
    static let iccIntent = "icc-intent"
    /** --icc-3dlut-size=<r>x<g>x<b> */
    static let icc3dlutSize = "icc-3dlut-size"
    /** --icc-contrast=<0-100000> */
    static let iccContrast = "icc-contrast"
    /** --blend-subtitles=<yes|video|no> */
    static let blendSubtitles = "blend-subtitles"
    /** --alpha=<blend-tiles|blend|yes|no> */
    static let alpha = "alpha"
    /** --opengl-rectangle-textures */
    static let openglRectangleTextures = "opengl-rectangle-textures"
    /** --background=<color> */
    static let background = "background"
  }

  struct Miscellaneous {
    /** --display-tags=tag1 */
    static let displayTags = "display-tags"
    /** --mc=<seconds/frame> */
    static let mc = "mc"
    /** --autosync=<factor> */
    static let autosync = "autosync"
    /** --video-sync=<audio|...> */
    static let videoSync = "video-sync"
    /** --video-sync-max-video-change=<value> */
    static let videoSyncMaxVideoChange = "video-sync-max-video-change"
    /** --video-sync-max-audio-change=<value> */
    static let videoSyncMaxAudioChange = "video-sync-max-audio-change"
    /** --video-sync-adrop-size=<value> */
    static let videoSyncAdropSize = "video-sync-adrop-size"
    /** --mf-fps=<value> */
    static let mfFps = "mf-fps"
    /** --mf-type=<value> */
    static let mfType = "mf-type"
    /** --stream-capture=<filename> */
    static let streamCapture = "stream-capture"
    /** --stream-dump=<filename> */
    static let streamDump = "stream-dump"
    /** --stream-lavf-o=opt1=value1 */
    static let streamLavfO = "stream-lavf-o"
    /** --vo-mmcss-profile=<name> */
    static let voMmcssProfile = "vo-mmcss-profile"
    /** --priority=<prio> */
    static let priority = "priority"
    /** --force-media-title=<string> */
    static let forceMediaTitle = "force-media-title"
    /** --external-file=<filename> */
    static let externalFile = "external-file"
    /** --autoload-files=<yes|no> */
    static let autoloadFiles = "autoload-files"
    /** --lavfi-complex=<string> */
    static let lavfiComplex = "lavfi-complex"
  }

}
