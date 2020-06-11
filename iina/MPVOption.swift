import Foundation

struct MPVOption {
  struct TrackSelection {
    /** --alang=<languagecode[ */
    static let alang = "alang"
    /** --slang=<languagecode[ */
    static let slang = "slang"
    /** --vlang=<...> */
    static let vlang = "vlang"
    /** --aid=<ID|auto|no> */
    static let aid = "aid"
    /** --sid=<ID|auto|no> */
    static let sid = "sid"
    /** --vid=<ID|auto|no> */
    static let vid = "vid"
    /** --edition=<ID|auto> */
    static let edition = "edition"
    /** --track-auto-selection=<yes|no> */
    static let trackAutoSelection = "track-auto-selection"
  }

  struct PlaybackControl {
    /** --start=<relative time> */
    static let start = "start"
    /** --end=<relative time> */
    static let end = "end"
    /** --length=<relative time> */
    static let length = "length"
    /** --rebase-start-time=<yes|no> */
    static let rebaseStartTime = "rebase-start-time"
    /** --speed=<0.01-100> */
    static let speed = "speed"
    /** --pause */
    static let pause = "pause"
    /** --shuffle */
    static let shuffle = "shuffle"
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
    /** --access-references=<yes|no> */
    static let accessReferences = "access-references"
    /** --loop-playlist=<N|inf|force|no> */
    static let loopPlaylist = "loop-playlist"
    /** --loop-file=<N|inf|no> */
    static let loopFile = "loop-file"
    /** --loop=<N|inf|no> */
    static let loop = "loop"
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
    /** --play-dir=<forward|+|backward|-> */
    static let playDir = "play-dir"
    /** --video-reversal-buffer=<bytesize> */
    static let videoReversalBuffer = "video-reversal-buffer"
    /** --audio-reversal-buffer=<bytesize> */
    static let audioReversalBuffer = "audio-reversal-buffer"
    /** --video-backward-overlap=<auto|number> */
    static let videoBackwardOverlap = "video-backward-overlap"
    /** --audio-backward-overlap=<auto|number> */
    static let audioBackwardOverlap = "audio-backward-overlap"
    /** --video-backward-batch=<number> */
    static let videoBackwardBatch = "video-backward-batch"
    /** --audio-backward-batch=<number> */
    static let audioBackwardBatch = "audio-backward-batch"
    /** --demuxer-backward-playback-step=<seconds> */
    static let demuxerBackwardPlaybackStep = "demuxer-backward-playback-step"
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
    /** --watch-later-directory=<path> */
    static let watchLaterDirectory = "watch-later-directory"
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
    /** --scripts=file1.lua:file2.lua:... */
    static let scripts = "scripts"
    /** --script-opts=key1=value1 */
    static let scriptOpts = "script-opts"
    /** --merge-files */
    static let mergeFiles = "merge-files"
    /** --no-resume-playback */
    static let noResumePlayback = "no-resume-playback"
    /** --resume-playback-check-mtime */
    static let resumePlaybackCheckMtime = "resume-playback-check-mtime"
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
    /** --load-stats-overlay=<yes|no> */
    static let loadStatsOverlay = "load-stats-overlay"
    /** --load-osd-console=<yes|no> */
    static let loadOsdConsole = "load-osd-console"
    /** --player-operation-mode=<cplayer|pseudo-gui> */
    static let playerOperationMode = "player-operation-mode"
  }

  struct Video {
    /** --vo=<driver> */
    static let vo = "vo"
    /** --vd=<...> */
    static let vd = "vd"
    /** --vf=<filter1[=parameter1:parameter2:...] */
    static let vf = "vf"
    /** --untimed */
    static let untimed = "untimed"
    /** --framedrop=<mode> */
    static let framedrop = "framedrop"
    /** --video-latency-hacks=<yes|no> */
    static let videoLatencyHacks = "video-latency-hacks"
    /** --override-display-fps=<fps> */
    static let overrideDisplayFps = "override-display-fps"
    /** --display-fps=<fps> */
    static let displayFps = "display-fps"
    /** --hwdec=<api> */
    static let hwdec = "hwdec"
    /** --gpu-hwdec-interop=<auto|all|no|name> */
    static let gpuHwdecInterop = "gpu-hwdec-interop"
    /** --hwdec-extra-frames=<N> */
    static let hwdecExtraFrames = "hwdec-extra-frames"
    /** --hwdec-image-format=<name> */
    static let hwdecImageFormat = "hwdec-image-format"
    /** --cuda-decode-device=<auto|0..> */
    static let cudaDecodeDevice = "cuda-decode-device"
    /** --vaapi-device=<device file> */
    static let vaapiDevice = "vaapi-device"
    /** --panscan=<0.0-1.0> */
    static let panscan = "panscan"
    /** --video-aspect-override=<ratio|no> */
    static let videoAspectOverride = "video-aspect-override"
    /** --video-aspect-method=<bitstream|container> */
    static let videoAspectMethod = "video-aspect-method"
    /** --video-unscaled=<no|yes|downscale-big> */
    static let videoUnscaled = "video-unscaled"
    /** --video-pan-x=<value> */
    static let videoPanX = "video-pan-x"
    /** --video-pan-y=<value> */
    static let videoPanY = "video-pan-y"
    /** --video-rotate=<0-359|no> */
    static let videoRotate = "video-rotate"
    /** --video-zoom=<value> */
    static let videoZoom = "video-zoom"
    /** --video-align-x=<-1-1> */
    static let videoAlignX = "video-align-x"
    /** --video-align-y=<-1-1> */
    static let videoAlignY = "video-align-y"
    /** --video-margin-ratio-left=<val> */
    static let videoMarginRatioLeft = "video-margin-ratio-left"
    /** --video-margin-ratio-right=<val> */
    static let videoMarginRatioRight = "video-margin-ratio-right"
    /** --video-margin-ratio-top=<val> */
    static let videoMarginRatioTop = "video-margin-ratio-top"
    /** --video-margin-ratio-bottom=<val> */
    static let videoMarginRatioBottom = "video-margin-ratio-bottom"
    /** --correct-pts */
    static let correctPts = "correct-pts"
    /** --no-correct-pts */
    static let noCorrectPts = "no-correct-pts"
    /** --fps=<float> */
    static let fps = "fps"
    /** --deinterlace=<yes|no> */
    static let deinterlace = "deinterlace"
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
    /** --vd-lavc-dr=<yes|no> */
    static let vdLavcDr = "vd-lavc-dr"
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
    /** --vd-lavc-assume-old-x264=<yes|no> */
    static let vdLavcAssumeOldX264 = "vd-lavc-assume-old-x264"
    /** --swapchain-depth=<N> */
    static let swapchainDepth = "swapchain-depth"
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
    /** --ad=<decoder1 */
    static let ad = "ad"
    /** --volume=<value> */
    static let volume = "volume"
    /** --replaygain=<no|track|album> */
    static let replaygain = "replaygain"
    /** --replaygain-preamp=<db> */
    static let replaygainPreamp = "replaygain-preamp"
    /** --replaygain-clip=<yes|no> */
    static let replaygainClip = "replaygain-clip"
    /** --replaygain-fallback=<db> */
    static let replaygainFallback = "replaygain-fallback"
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
    /** --audio-display=<no|attachment> */
    static let audioDisplay = "audio-display"
    /** --audio-files=<files> */
    static let audioFiles = "audio-files"
    /** --audio-file=<file> */
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
    /** --sub-files=<file-list> */
    static let subFiles = "sub-files"
    /** --sub-file=<filename> */
    static let subFile = "sub-file"
    /** --secondary-sid=<ID|auto|no> */
    static let secondarySid = "secondary-sid"
    /** --sub-scale=<0-100> */
    static let subScale = "sub-scale"
    /** --sub-scale-by-window=<yes|no> */
    static let subScaleByWindow = "sub-scale-by-window"
    /** --sub-scale-with-window=<yes|no> */
    static let subScaleWithWindow = "sub-scale-with-window"
    /** --sub-ass-scale-with-window=<yes|no> */
    static let subAssScaleWithWindow = "sub-ass-scale-with-window"
    /** --embeddedfonts=<yes|no> */
    static let embeddedfonts = "embeddedfonts"
    /** --sub-pos=<0-100> */
    static let subPos = "sub-pos"
    /** --sub-speed=<0.1-10.0> */
    static let subSpeed = "sub-speed"
    /** --sub-ass-force-style=<[Style.]Param=Value[ */
    static let subAssForceStyle = "sub-ass-force-style"
    /** --sub-ass-hinting=<none|light|normal|native> */
    static let subAssHinting = "sub-ass-hinting"
    /** --sub-ass-line-spacing=<value> */
    static let subAssLineSpacing = "sub-ass-line-spacing"
    /** --sub-ass-shaper=<simple|complex> */
    static let subAssShaper = "sub-ass-shaper"
    /** --sub-ass-styles=<filename> */
    static let subAssStyles = "sub-ass-styles"
    /** --sub-ass-override=<yes|no|force|scale|strip> */
    static let subAssOverride = "sub-ass-override"
    /** --sub-ass-force-margins */
    static let subAssForceMargins = "sub-ass-force-margins"
    /** --sub-use-margins */
    static let subUseMargins = "sub-use-margins"
    /** --sub-ass-vsfilter-aspect-compat=<yes|no> */
    static let subAssVsfilterAspectCompat = "sub-ass-vsfilter-aspect-compat"
    /** --sub-ass-vsfilter-blur-compat=<yes|no> */
    static let subAssVsfilterBlurCompat = "sub-ass-vsfilter-blur-compat"
    /** --sub-ass-vsfilter-color-compat=<basic|full|force-601|no> */
    static let subAssVsfilterColorCompat = "sub-ass-vsfilter-color-compat"
    /** --stretch-dvd-subs=<yes|no> */
    static let stretchDvdSubs = "stretch-dvd-subs"
    /** --stretch-image-subs-to-screen=<yes|no> */
    static let stretchImageSubsToScreen = "stretch-image-subs-to-screen"
    /** --image-subs-video-resolution=<yes|no> */
    static let imageSubsVideoResolution = "image-subs-video-resolution"
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
    /** --sub-fix-timing=<yes|no> */
    static let subFixTiming = "sub-fix-timing"
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
    /** --sub-file-paths=<path-list> */
    static let subFilePaths = "sub-file-paths"
    /** --sub-visibility */
    static let subVisibility = "sub-visibility"
    /** --no-sub-visibility */
    static let noSubVisibility = "no-sub-visibility"
    /** --sub-clear-on-seek */
    static let subClearOnSeek = "sub-clear-on-seek"
    /** --teletext-page=<1-999> */
    static let teletextPage = "teletext-page"
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
    /** --sub-justify=<auto|left|center|right> */
    static let subJustify = "sub-justify"
    /** --sub-ass-justify=<yes|no> */
    static let subAssJustify = "sub-ass-justify"
    /** --sub-shadow-color=<color> */
    static let subShadowColor = "sub-shadow-color"
    /** --sub-shadow-offset=<size> */
    static let subShadowOffset = "sub-shadow-offset"
    /** --sub-spacing=<size> */
    static let subSpacing = "sub-spacing"
    /** --sub-filter-sdh=<yes|no> */
    static let subFilterSdh = "sub-filter-sdh"
    /** --sub-filter-sdh-harder=<yes|no> */
    static let subFilterSdhHarder = "sub-filter-sdh-harder"
    /** --sub-create-cc-track=<yes|no> */
    static let subCreateCcTrack = "sub-create-cc-track"
    /** --sub-font-provider=<auto|none|fontconfig> */
    static let subFontProvider = "sub-font-provider"
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
    /** --keep-open-pause=<yes|no> */
    static let keepOpenPause = "keep-open-pause"
    /** --image-display-duration=<seconds|inf> */
    static let imageDisplayDuration = "image-display-duration"
    /** --force-window=<yes|no|immediate> */
    static let forceWindow = "force-window"
    /** --taskbar-progress */
    static let taskbarProgress = "taskbar-progress"
    /** --no-taskbar-progress */
    static let noTaskbarProgress = "no-taskbar-progress"
    /** --snap-window */
    static let snapWindow = "snap-window"
    /** --ontop */
    static let ontop = "ontop"
    /** --ontop-level=<window|system|level> */
    static let ontopLevel = "ontop-level"
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
    /** --window-minimized=<yes|no> */
    static let windowMinimized = "window-minimized"
    /** --window-maximized=<yes|no> */
    static let windowMaximized = "window-maximized"
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
    /** --hidpi-window-scale */
    static let hidpiWindowScale = "hidpi-window-scale"
    /** --no-hidpi-window-scale */
    static let noHidpiWindowScale = "no-hidpi-window-scale"
    /** --native-fs */
    static let nativeFs = "native-fs"
    /** --no-native-fs */
    static let noNativeFs = "no-native-fs"
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
    /** --demuxer-lavf-probe-info=<yes|no|auto|nostreams> */
    static let demuxerLavfProbeInfo = "demuxer-lavf-probe-info"
    /** --demuxer-lavf-probescore=<1-100> */
    static let demuxerLavfProbescore = "demuxer-lavf-probescore"
    /** --demuxer-lavf-allow-mimetype=<yes|no> */
    static let demuxerLavfAllowMimetype = "demuxer-lavf-allow-mimetype"
    /** --demuxer-lavf-format=<name> */
    static let demuxerLavfFormat = "demuxer-lavf-format"
    /** --demuxer-lavf-hacks=<yes|no> */
    static let demuxerLavfHacks = "demuxer-lavf-hacks"
    /** --demuxer-lavf-o=<key>=<value>[ */
    static let demuxerLavfO = "demuxer-lavf-o"
    /** --demuxer-lavf-probesize=<value> */
    static let demuxerLavfProbesize = "demuxer-lavf-probesize"
    /** --demuxer-lavf-buffersize=<value> */
    static let demuxerLavfBuffersize = "demuxer-lavf-buffersize"
    /** --demuxer-lavf-linearize-timestamps=<yes|no|auto> */
    static let demuxerLavfLinearizeTimestamps = "demuxer-lavf-linearize-timestamps"
    /** --demuxer-lavf-propagate-opts=<yes|no> */
    static let demuxerLavfPropagateOpts = "demuxer-lavf-propagate-opts"
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
    /** --demuxer-cue-codepage=<codepage> */
    static let demuxerCueCodepage = "demuxer-cue-codepage"
    /** --demuxer-max-bytes=<bytesize> */
    static let demuxerMaxBytes = "demuxer-max-bytes"
    /** --demuxer-max-back-bytes=<bytesize> */
    static let demuxerMaxBackBytes = "demuxer-max-back-bytes"
    /** --demuxer-seekable-cache=<yes|no|auto> */
    static let demuxerSeekableCache = "demuxer-seekable-cache"
    /** --demuxer-thread=<yes|no> */
    static let demuxerThread = "demuxer-thread"
    /** --demuxer-termination-timeout=<seconds> */
    static let demuxerTerminationTimeout = "demuxer-termination-timeout"
    /** --demuxer-readahead-secs=<seconds> */
    static let demuxerReadaheadSecs = "demuxer-readahead-secs"
    /** --prefetch-playlist=<yes|no> */
    static let prefetchPlaylist = "prefetch-playlist"
    /** --force-seekable=<yes|no> */
    static let forceSeekable = "force-seekable"
    /** --demuxer-cache-wait=<yes|no> */
    static let demuxerCacheWait = "demuxer-cache-wait"
    /** --rar-list-all-volumes=<yes|no> */
    static let rarListAllVolumes = "rar-list-all-volumes"
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
    /** --input-gamepad=<yes|no> */
    static let inputGamepad = "input-gamepad"
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
    /** --osd-on-seek=<no */
    static let osdOnSeek = "osd-on-seek"
    /** --osd-duration=<time> */
    static let osdDuration = "osd-duration"
    /** --osd-font=<name> */
    static let osdFont = "osd-font"
    /** --osd-font-size=<size> */
    static let osdFontSize = "osd-font-size"
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
    /** --osd-blur=<0..20.0> */
    static let osdBlur = "osd-blur"
    /** --osd-bold=<yes|no> */
    static let osdBold = "osd-bold"
    /** --osd-italic=<yes|no> */
    static let osdItalic = "osd-italic"
    /** --osd-border-color=<color> */
    static let osdBorderColor = "osd-border-color"
    /** --osd-border-size=<size> */
    static let osdBorderSize = "osd-border-size"
    /** --osd-color=<color> */
    static let osdColor = "osd-color"
    /** --osd-fractions */
    static let osdFractions = "osd-fractions"
    /** --osd-level=<0-3> */
    static let osdLevel = "osd-level"
    /** --osd-margin-x=<size> */
    static let osdMarginX = "osd-margin-x"
    /** --osd-margin-y=<size> */
    static let osdMarginY = "osd-margin-y"
    /** --osd-align-x=<left|center|right> */
    static let osdAlignX = "osd-align-x"
    /** --osd-align-y=<top|center|bottom> */
    static let osdAlignY = "osd-align-y"
    /** --osd-scale=<factor> */
    static let osdScale = "osd-scale"
    /** --osd-scale-by-window=<yes|no> */
    static let osdScaleByWindow = "osd-scale-by-window"
    /** --osd-shadow-color=<color> */
    static let osdShadowColor = "osd-shadow-color"
    /** --osd-shadow-offset=<size> */
    static let osdShadowOffset = "osd-shadow-offset"
    /** --osd-spacing=<size> */
    static let osdSpacing = "osd-spacing"
    /** --video-osd=<yes|no> */
    static let videoOsd = "video-osd"
    /** --osd-font-provider=<...> */
    static let osdFontProvider = "osd-font-provider"
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
    /** --screenshot-webp-lossless=<yes|no> */
    static let screenshotWebpLossless = "screenshot-webp-lossless"
    /** --screenshot-webp-quality=<0-100> */
    static let screenshotWebpQuality = "screenshot-webp-quality"
    /** --screenshot-webp-compression=<0-6> */
    static let screenshotWebpCompression = "screenshot-webp-compression"
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
    /** --sws-bitexact=<yes|no> */
    static let swsBitexact = "sws-bitexact"
    /** --sws-fast=<yes|no> */
    static let swsFast = "sws-fast"
    /** --sws-allow-zimg=<yes|no> */
    static let swsAllowZimg = "sws-allow-zimg"
    /** --zimg-scaler=<point|bilinear|bicubic|spline16|spline36|lanczos> */
    static let zimgScaler = "zimg-scaler"
    /** --zimg-scaler-param-a=<default|float> */
    static let zimgScalerParamA = "zimg-scaler-param-a"
    /** --zimg-scaler-param-b=<default|float> */
    static let zimgScalerParamB = "zimg-scaler-param-b"
    /** --zimg-scaler-chroma=... */
    static let zimgScalerChroma = "zimg-scaler-chroma"
    /** --zimg-scaler-chroma-param-a */
    static let zimgScalerChromaParamA = "zimg-scaler-chroma-param-a"
    /** --zimg-scaler-chroma-param-b */
    static let zimgScalerChromaParamB = "zimg-scaler-chroma-param-b"
    /** --zimg-dither=<no|ordered|random|error-diffusion> */
    static let zimgDither = "zimg-dither"
    /** --zimg-fast=<yes|no> */
    static let zimgFast = "zimg-fast"
  }

  struct AudioResampler {
    /** --audio-resample-filter-size=<length> */
    static let audioResampleFilterSize = "audio-resample-filter-size"
    /** --audio-resample-phase-shift=<count> */
    static let audioResamplePhaseShift = "audio-resample-phase-shift"
    /** --audio-resample-cutoff=<cutoff> */
    static let audioResampleCutoff = "audio-resample-cutoff"
    /** --audio-resample-linear=<yes|no> */
    static let audioResampleLinear = "audio-resample-linear"
    /** --audio-normalize-downmix=<yes|no> */
    static let audioNormalizeDownmix = "audio-normalize-downmix"
    /** --audio-resample-max-output-size=<length> */
    static let audioResampleMaxOutputSize = "audio-resample-max-output-size"
    /** --audio-swresample-o=<string> */
    static let audioSwresampleO = "audio-swresample-o"
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
    /** --cache=<yes|no|auto> */
    static let cache = "cache"
    /** --no-cache */
    static let noCache = "no-cache"
    /** --cache-secs=<seconds> */
    static let cacheSecs = "cache-secs"
    /** --cache-on-disk=<yes|no> */
    static let cacheOnDisk = "cache-on-disk"
    /** --cache-dir=<path> */
    static let cacheDir = "cache-dir"
    /** --cache-pause=<yes|no> */
    static let cachePause = "cache-pause"
    /** --cache-pause-wait=<seconds> */
    static let cachePauseWait = "cache-pause-wait"
    /** --cache-pause-initial=<yes|no> */
    static let cachePauseInitial = "cache-pause-initial"
    /** --cache-unlink-files=<immediate|whendone|no> */
    static let cacheUnlinkFiles = "cache-unlink-files"
    /** --stream-buffer-size=<bytesize> */
    static let streamBufferSize = "stream-buffer-size"
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
    /** --http-proxy=<proxy> */
    static let httpProxy = "http-proxy"
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
    /** --dvbin-prog=<string> */
    static let dvbinProg = "dvbin-prog"
    /** --dvbin-card=<0-15> */
    static let dvbinCard = "dvbin-card"
    /** --dvbin-file=<filename> */
    static let dvbinFile = "dvbin-file"
    /** --dvbin-timeout=<1-30> */
    static let dvbinTimeout = "dvbin-timeout"
    /** --dvbin-full-transponder=<yes|no> */
    static let dvbinFullTransponder = "dvbin-full-transponder"
    /** --dvbin-channel-switch-offset=<integer> */
    static let dvbinChannelSwitchOffset = "dvbin-channel-switch-offset"
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
    /** --alsa-buffer-time=<microseconds> */
    static let alsaBufferTime = "alsa-buffer-time"
    /** --alsa-periods=<number> */
    static let alsaPeriods = "alsa-periods"
  }

  struct GPURendererOptions {
    /** --scale=<filter> */
    static let scale = "scale"
    /** --cscale=<filter> */
    static let cscale = "cscale"
    /** --dscale=<filter> */
    static let dscale = "dscale"
    /** --tscale=<filter> */
    static let tscale = "tscale"
    /** --scale-param1=<value> */
    static let scaleParam1 = "scale-param1"
    /** --scale-param2=<value> */
    static let scaleParam2 = "scale-param2"
    /** --cscale-param1=<value> */
    static let cscaleParam1 = "cscale-param1"
    /** --cscale-param2=<value> */
    static let cscaleParam2 = "cscale-param2"
    /** --dscale-param1=<value> */
    static let dscaleParam1 = "dscale-param1"
    /** --dscale-param2=<value> */
    static let dscaleParam2 = "dscale-param2"
    /** --tscale-param1=<value> */
    static let tscaleParam1 = "tscale-param1"
    /** --tscale-param2=<value> */
    static let tscaleParam2 = "tscale-param2"
    /** --scale-blur=<value> */
    static let scaleBlur = "scale-blur"
    /** --scale-wblur=<value> */
    static let scaleWblur = "scale-wblur"
    /** --cscale-blur=<value> */
    static let cscaleBlur = "cscale-blur"
    /** --cscale-wblur=<value> */
    static let cscaleWblur = "cscale-wblur"
    /** --dscale-blur=<value> */
    static let dscaleBlur = "dscale-blur"
    /** --dscale-wblur=<value> */
    static let dscaleWblur = "dscale-wblur"
    /** --tscale-blur=<value> */
    static let tscaleBlur = "tscale-blur"
    /** --tscale-wblur=<value> */
    static let tscaleWblur = "tscale-wblur"
    /** --scale-clamp=<0.0-1.0> */
    static let scaleClamp = "scale-clamp"
    /** --cscale-clamp */
    static let cscaleClamp = "cscale-clamp"
    /** --dscale-clamp */
    static let dscaleClamp = "dscale-clamp"
    /** --tscale-clamp */
    static let tscaleClamp = "tscale-clamp"
    /** --scale-cutoff=<value> */
    static let scaleCutoff = "scale-cutoff"
    /** --cscale-cutoff=<value> */
    static let cscaleCutoff = "cscale-cutoff"
    /** --dscale-cutoff=<value> */
    static let dscaleCutoff = "dscale-cutoff"
    /** --scale-taper=<value> */
    static let scaleTaper = "scale-taper"
    /** --scale-wtaper=<value> */
    static let scaleWtaper = "scale-wtaper"
    /** --dscale-taper=<value> */
    static let dscaleTaper = "dscale-taper"
    /** --dscale-wtaper=<value> */
    static let dscaleWtaper = "dscale-wtaper"
    /** --cscale-taper=<value> */
    static let cscaleTaper = "cscale-taper"
    /** --cscale-wtaper=<value> */
    static let cscaleWtaper = "cscale-wtaper"
    /** --tscale-taper=<value> */
    static let tscaleTaper = "tscale-taper"
    /** --tscale-wtaper=<value> */
    static let tscaleWtaper = "tscale-wtaper"
    /** --scale-radius=<value> */
    static let scaleRadius = "scale-radius"
    /** --cscale-radius=<value> */
    static let cscaleRadius = "cscale-radius"
    /** --dscale-radius=<value> */
    static let dscaleRadius = "dscale-radius"
    /** --tscale-radius=<value> */
    static let tscaleRadius = "tscale-radius"
    /** --scale-antiring=<value> */
    static let scaleAntiring = "scale-antiring"
    /** --cscale-antiring=<value> */
    static let cscaleAntiring = "cscale-antiring"
    /** --dscale-antiring=<value> */
    static let dscaleAntiring = "dscale-antiring"
    /** --tscale-antiring=<value> */
    static let tscaleAntiring = "tscale-antiring"
    /** --scale-window=<window> */
    static let scaleWindow = "scale-window"
    /** --cscale-window=<window> */
    static let cscaleWindow = "cscale-window"
    /** --dscale-window=<window> */
    static let dscaleWindow = "dscale-window"
    /** --tscale-window=<window> */
    static let tscaleWindow = "tscale-window"
    /** --scale-wparam=<window> */
    static let scaleWparam = "scale-wparam"
    /** --cscale-wparam=<window> */
    static let cscaleWparam = "cscale-wparam"
    /** --tscale-wparam=<window> */
    static let tscaleWparam = "tscale-wparam"
    /** --scaler-lut-size=<4..10> */
    static let scalerLutSize = "scaler-lut-size"
    /** --scaler-resizes-only */
    static let scalerResizesOnly = "scaler-resizes-only"
    /** --correct-downscaling */
    static let correctDownscaling = "correct-downscaling"
    /** --linear-downscaling */
    static let linearDownscaling = "linear-downscaling"
    /** --linear-upscaling */
    static let linearUpscaling = "linear-upscaling"
    /** --sigmoid-upscaling */
    static let sigmoidUpscaling = "sigmoid-upscaling"
    /** --sigmoid-center */
    static let sigmoidCenter = "sigmoid-center"
    /** --sigmoid-slope */
    static let sigmoidSlope = "sigmoid-slope"
    /** --interpolation */
    static let interpolation = "interpolation"
    /** --interpolation-threshold=<0..1 */
    static let interpolationThreshold = "interpolation-threshold"
    /** --opengl-pbo */
    static let openglPbo = "opengl-pbo"
    /** --dither-depth=<N|no|auto> */
    static let ditherDepth = "dither-depth"
    /** --dither-size-fruit=<2-8> */
    static let ditherSizeFruit = "dither-size-fruit"
    /** --dither=<fruit|ordered|error-diffusion|no> */
    static let dither = "dither"
    /** --temporal-dither */
    static let temporalDither = "temporal-dither"
    /** --temporal-dither-period=<1-128> */
    static let temporalDitherPeriod = "temporal-dither-period"
    /** --error-diffusion=<kernel> */
    static let errorDiffusion = "error-diffusion"
    /** --gpu-debug */
    static let gpuDebug = "gpu-debug"
    /** --opengl-swapinterval=<n> */
    static let openglSwapinterval = "opengl-swapinterval"
    /** --vulkan-swap-mode=<mode> */
    static let vulkanSwapMode = "vulkan-swap-mode"
    /** --vulkan-queue-count=<1..8> */
    static let vulkanQueueCount = "vulkan-queue-count"
    /** --vulkan-async-transfer */
    static let vulkanAsyncTransfer = "vulkan-async-transfer"
    /** --vulkan-async-compute */
    static let vulkanAsyncCompute = "vulkan-async-compute"
    /** --d3d11-warp=<yes|no|auto> */
    static let d3d11Warp = "d3d11-warp"
    /** --d3d11-feature-level=<12_1|12_0|11_1|11_0|10_1|10_0|9_3|9_2|9_1> */
    static let d3d11FeatureLevel = "d3d11-feature-level"
    /** --d3d11-flip=<yes|no> */
    static let d3d11Flip = "d3d11-flip"
    /** --d3d11-sync-interval=<0..4> */
    static let d3d11SyncInterval = "d3d11-sync-interval"
    /** --d3d11-adapter=<adapter name|help> */
    static let d3d11Adapter = "d3d11-adapter"
    /** --d3d11-output-format=<auto|rgba8|bgra8|rgb10_a2|rgba16f> */
    static let d3d11OutputFormat = "d3d11-output-format"
    /** --d3d11-output-csp=<auto|srgb|linear|pq|bt.2020> */
    static let d3d11OutputCsp = "d3d11-output-csp"
    /** --d3d11va-zero-copy=<yes|no> */
    static let d3d11vaZeroCopy = "d3d11va-zero-copy"
    /** --wayland-frame-wait-offset=<-500..3000> */
    static let waylandFrameWaitOffset = "wayland-frame-wait-offset"
    /** --wayland-disable-vsync=<yes|no> */
    static let waylandDisableVsync = "wayland-disable-vsync"
    /** --spirv-compiler=<compiler> */
    static let spirvCompiler = "spirv-compiler"
    /** --glsl-shader=<file> */
    static let glslShader = "glsl-shader"
    /** --glsl-shaders=<file-list> */
    static let glslShaders = "glsl-shaders"
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
    /** --sharpen=<value> */
    static let sharpen = "sharpen"
    /** --opengl-glfinish */
    static let openglGlfinish = "opengl-glfinish"
    /** --opengl-waitvsync */
    static let openglWaitvsync = "opengl-waitvsync"
    /** --opengl-dwmflush=<no|windowed|yes|auto> */
    static let openglDwmflush = "opengl-dwmflush"
    /** --angle-d3d11-feature-level=<11_0|10_1|10_0|9_3> */
    static let angleD3d11FeatureLevel = "angle-d3d11-feature-level"
    /** --angle-d3d11-warp=<yes|no|auto> */
    static let angleD3d11Warp = "angle-d3d11-warp"
    /** --angle-egl-windowing=<yes|no|auto> */
    static let angleEglWindowing = "angle-egl-windowing"
    /** --angle-flip=<yes|no> */
    static let angleFlip = "angle-flip"
    /** --angle-renderer=<d3d9|d3d11|auto> */
    static let angleRenderer = "angle-renderer"
    /** --cocoa-force-dedicated-gpu=<yes|no> */
    static let cocoaForceDedicatedGpu = "cocoa-force-dedicated-gpu"
    /** --cocoa-cb-sw-renderer=<yes|no|auto> */
    static let cocoaCbSwRenderer = "cocoa-cb-sw-renderer"
    /** --cocoa-cb-10bit-context=<yes|no> */
    static let cocoaCb10bitContext = "cocoa-cb-10bit-context"
    /** --macos-title-bar-appearance=<appearance> */
    static let macosTitleBarAppearance = "macos-title-bar-appearance"
    /** --macos-title-bar-material=<material> */
    static let macosTitleBarMaterial = "macos-title-bar-material"
    /** --macos-title-bar-color=<color> */
    static let macosTitleBarColor = "macos-title-bar-color"
    /** --macos-fs-animation-duration=<default|0-1000> */
    static let macosFsAnimationDuration = "macos-fs-animation-duration"
    /** --android-surface-size=<WxH> */
    static let androidSurfaceSize = "android-surface-size"
    /** --gpu-sw */
    static let gpuSw = "gpu-sw"
    /** --gpu-context=<sys> */
    static let gpuContext = "gpu-context"
    /** --gpu-api=<type> */
    static let gpuApi = "gpu-api"
    /** --opengl-es=<mode> */
    static let openglEs = "opengl-es"
    /** --opengl-restrict=<version> */
    static let openglRestrict = "opengl-restrict"
    /** --fbo-format=<fmt> */
    static let fboFormat = "fbo-format"
    /** --gamma-factor=<0.1..2.0> */
    static let gammaFactor = "gamma-factor"
    /** --gamma-auto */
    static let gammaAuto = "gamma-auto"
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
    /** --tone-mapping-max-boost=<1.0..10.0> */
    static let toneMappingMaxBoost = "tone-mapping-max-boost"
    /** --hdr-compute-peak=<auto|yes|no> */
    static let hdrComputePeak = "hdr-compute-peak"
    /** --hdr-peak-decay-rate=<1.0..1000.0> */
    static let hdrPeakDecayRate = "hdr-peak-decay-rate"
    /** --hdr-scene-threshold-low=<0.0..100.0> */
    static let hdrSceneThresholdLow = "hdr-scene-threshold-low"
    /** --hdr-scene-threshold-high=<0.0..100.0> */
    static let hdrSceneThresholdHigh = "hdr-scene-threshold-high"
    /** --tone-mapping-desaturate=<0.0..1.0> */
    static let toneMappingDesaturate = "tone-mapping-desaturate"
    /** --tone-mapping-desaturate-exponent=<0.0..20.0> */
    static let toneMappingDesaturateExponent = "tone-mapping-desaturate-exponent"
    /** --gamut-warning */
    static let gamutWarning = "gamut-warning"
    /** --use-embedded-icc-profile */
    static let useEmbeddedIccProfile = "use-embedded-icc-profile"
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
    /** --icc-contrast=<0-1000000|inf> */
    static let iccContrast = "icc-contrast"
    /** --blend-subtitles=<yes|video|no> */
    static let blendSubtitles = "blend-subtitles"
    /** --alpha=<blend-tiles|blend|yes|no> */
    static let alpha = "alpha"
    /** --opengl-rectangle-textures */
    static let openglRectangleTextures = "opengl-rectangle-textures"
    /** --background=<color> */
    static let background = "background"
    /** --gpu-tex-pad-x */
    static let gpuTexPadX = "gpu-tex-pad-x"
    /** --gpu-tex-pad-y */
    static let gpuTexPadY = "gpu-tex-pad-y"
    /** --opengl-early-flush=<yes|no|auto> */
    static let openglEarlyFlush = "opengl-early-flush"
    /** --gpu-dumb-mode=<yes|no|auto> */
    static let gpuDumbMode = "gpu-dumb-mode"
    /** --gpu-shader-cache-dir=<dirname> */
    static let gpuShaderCacheDir = "gpu-shader-cache-dir"
  }

  struct Miscellaneous {
    /** --display-tags=tag1 */
    static let displayTags = "display-tags"
    /** --mc=<seconds/frame> */
    static let mc = "mc"
    /** --autosync=<factor> */
    static let autosync = "autosync"
    /** --video-timing-offset=<seconds> */
    static let videoTimingOffset = "video-timing-offset"
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
    /** --stream-dump=<destination-filename> */
    static let streamDump = "stream-dump"
    /** --stream-lavf-o=opt1=value1 */
    static let streamLavfO = "stream-lavf-o"
    /** --vo-mmcss-profile=<name> */
    static let voMmcssProfile = "vo-mmcss-profile"
    /** --priority=<prio> */
    static let priority = "priority"
    /** --force-media-title=<string> */
    static let forceMediaTitle = "force-media-title"
    /** --external-files=<file-list> */
    static let externalFiles = "external-files"
    /** --external-file=<file> */
    static let externalFile = "external-file"
    /** --autoload-files=<yes|no> */
    static let autoloadFiles = "autoload-files"
    /** --record-file=<file> */
    static let recordFile = "record-file"
    /** --stream-record=<file> */
    static let streamRecord = "stream-record"
    /** --lavfi-complex=<string> */
    static let lavfiComplex = "lavfi-complex"
    /** --metadata-codepage=<codepage> */
    static let metadataCodepage = "metadata-codepage"
  }

  struct Debugging {
    /** --unittest=<name> */
    static let unittest = "unittest"
  }

}
