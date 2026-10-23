  var scopedTrackSettings=TrackProcessingState()
  var observers:[NSObjectProtocol]=[],settingOSDs=0,cropRemovals=0,beginCropRefreshes=0
  enum VideoEqualizerType { case brightness,contrast,saturation,gamma,hue }
  enum TrackType { case audio,video }
  deinit {observers.forEach{NotificationCenter.default.removeObserver($0)}}
