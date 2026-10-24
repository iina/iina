import Cocoa

enum MPVProperty { static let videoParams="video-params",videoOutParams="video-out-params",vf="vf",trackList="track-list" }
enum MPVOption { enum Video { static let videoZoom="video-zoom",videoPanX="video-pan-x",videoPanY="video-pan-y",panscan="panscan",videoAspectOverride="video-aspect-override",videoRotate="video-rotate" } }
enum Constants { enum FilterName { static let crop="crop" } }
enum AppData { static let rotations=[0,90,180,270] }
enum OSDMessage { case seek,pause,aspect,rotate;var alwaysEnabled:Bool {false} }
struct PinchFixture { let state:NSGestureRecognizer.State;let magnification:CGFloat }
enum Preference {
  enum Key { case disableAnimations }
  static var animationsDisabled=false,unlockWindowAspectRatio=false
  static func bool(for key:Key)->Bool { animationsDisabled }
}
enum AccessibilityPreferences {
  static var motionReductionEnabled=false
  static func adjustedDuration(_ value:TimeInterval)->TimeInterval { value }
}
enum ClockTrace {
  static var policies:[(TimeInterval,CropTransitionOverlay.AnimationCurve,Bool)]=[]
  static var advances:[(Double)->Void]=[]
  static var ticks:[(CFTimeInterval)->Void]=[],watchdogs:[Timer]=[]
  static func reset(){policies=[];advances=[];ticks=[];watchdogs=[]}
}
final class EventTrace { var events:[String]=[] }
final class ProjectionLayer: CALayer {
  var trace:EventTrace?
  var isInCropTransition=false,isAnimatingWindowResize=false,isPreparingCropFrame=false,inLiveResize=false
  var callbacks:[(Bool)->Void]=[],cancelCount=0
  var updates=0
  var handoffs:[(bounds:NSRect,transform:CATransform3D)]=[]
  override var transform:CATransform3D { didSet { trace?.events.append("projection") } }
  func setCropFramePreparation(_ value:Bool){isPreparingCropFrame=value;trace?.events.append(value ? "prepare-native" : "release-native-preparation")}
  func afterNextPreparedCropFrame(_ callback:@escaping (Bool)->Void){callbacks.append(callback);trace?.events.append("wait-native")}
  func cancelCropFrameRequests(){cancelCount+=1;trace?.events.append("cancel-native")}
  func update(force:Bool){precondition(force);updates+=1;trace?.events.append("request-native")}
  func withCropFrameHandoff(_ body:()->Void){trace?.events.append("handoff-begin");body();isPreparingCropFrame=false;handoffs.append((bounds,transform));trace?.events.append("handoff-end")}
}
final class VideoFixture:NSView {
  let videoLayer=ProjectionLayer()
  var activeCalls=0,idleCalls=0,assignedFrames:[NSRect]=[]
  override var frame:NSRect { didSet { assignedFrames.append(frame) } }
  init(){super.init(frame:.zero);layer=videoLayer;wantsLayer=true}
  required init?(coder:NSCoder){fatalError()}
  func displayActive(){activeCalls+=1}
  func displayIdle(){idleCalls+=1}
}
final class ContainerFixture:NSView {
  var trace:EventTrace?
  override func layoutSubtreeIfNeeded(){trace?.events.append("layout");super.layoutSubtreeIfNeeded()}
}
final class MotionWindow:NSWindow {
  var visibleForTesting=true,requested:[NSRect]=[]
  var usesClockScreenForTesting=false,occludedForTesting=false,displayLinkRequests=0
  weak var displayLinkTarget:AnyObject?
  var trace:EventTrace?
  override var isVisible:Bool { visibleForTesting }
  // Integration cases use Timer fallback; clock cases select a paused native
  // display link without ever ordering this window on screen.
  override var screen:NSScreen? {usesClockScreenForTesting ? NSScreen.main : nil}
  override var occlusionState:NSWindow.OcclusionState {occludedForTesting ? [] : [.visible]}
  @available(macOS 14.0, *)
  override func displayLink(target:Any,selector:Selector)->CADisplayLink {
    displayLinkRequests+=1;displayLinkTarget=target as AnyObject
    let link=super.displayLink(target:target,selector:selector);link.isPaused=true;return link
  }
  override func setFrame(_ frame:NSRect,display:Bool){requested.append(frame);trace?.events.append("window-frame");super.setFrame(frame,display:display)}
}
final class MPVFixture {
  struct Filter { var label:String? }
  var values:[String:Double]=[:],strings:[String:String]=[:],nodes:[String:Any]=[:],writes:[(String,String)]=[]
  var filters:[Filter]=[],pendingEvents:[()->Void]=[]
  enum Command { case seek }
  var commands:[[String]]=[]
  var failNext=false,defaultAspect=16/9.0
  var sourceRotation=0 {didSet{values["video-dec-params/rotate"]=Double(sourceRotation)}}
  var synchronizeDecoder=true,autoPublishOutput=false
  var onWrite:((String,String)->Void)?
  init(){
    values["video-aspect-override"] = -1;values["video-rotate"]=0
    values["video-scale-x"]=1;values["video-scale-y"]=1
    strings["video-crop"]="";strings["video-unscaled"]="no";strings["lavfi-complex"]=""
    for prefix in ["video-params","video-out-params"] {
      for (name,value) in ["w":1920.0,"h":1080.0,"dw":1920.0,"dh":1080.0,"rotate":0.0,"par":1.0] {values[prefix+"/"+name]=value}
    }
  }
  func getInt(_ name:String)->Int { Int(values[name] ?? 0) }
  func getDouble(_ name:String)->Double { values[name] ?? 0 }
  func getString(_ name:String)->String? { strings[name] }
  func getNode(_ name:String)->Any? {nodes[name]}
  func getFilters(_ name:String)->[Filter] { filters }
  func afterPendingEvents(_ completion:@escaping ()->Void){pendingEvents.append(completion)}
  func drainPendingEvents(){let pending=pendingEvents;pendingEvents=[];pending.forEach{$0()}}
  func command(_ command:Command,args:[String],checkError:Bool=true){commands.append(args)}
  func setString(_ name:String,_ value:String)->Int32 {
    writes.append((name,value));onWrite?(name,value)
    if failNext { failNext=false;return -4 }
    if name=="video-aspect-override" {
      let parts=value.split(separator:":").compactMap{Double($0)}
      values[name]=parts.count==2 ? parts[0]/parts[1] : -1
    }else{values[name]=Double(value) ?? 0}
    if synchronizeDecoder { updateDecoder() }
    if autoPublishOutput { publishOutput() }
    return 0
  }
  func updateDecoder(){
    let ratio=(values["video-aspect-override"] ?? -1)>0 ? values["video-aspect-override"]! : defaultAspect
    let width=values["video-params/w"]!,height=values["video-params/h"]!
    values["video-params/dw"]=height*ratio;values["video-params/dh"]=height
    values["video-params/par"]=ratio/(width/height)
    values["video-params/rotate"]=Double((sourceRotation+getInt("video-rotate"))%360)
  }
  func publishOutput(){for key in ["w","h","dw","dh","rotate","par"] {values["video-out-params/"+key]=values["video-params/"+key]}}
  func publishOutput(effectiveRotation:Int,pixelAspect:Double){
    let width=getDouble("video-params/w"),height=getDouble("video-params/h")
    for (key,value) in ["w":width,"h":height,"dw":width*pixelAspect,"dh":height,"rotate":Double(effectiveRotation),"par":pixelAspect] {values["video-out-params/"+key]=value}
  }
}
final class PlayerFixture {
  func preservingOSDFeedbackOrigin<T>(_ action: @escaping () -> T) -> () -> T { action }
  enum State { case playing,paused,stopped;var loaded:Bool { self != .stopped };var active:Bool { loaded } }
  struct Track { let id:Int;var demuxPixelAspect:Double? }
  final class Info {
    var state=State.playing,trackSelectionGeneration=1,justStartedFile=false,unsureAspect="Default"
    var videoTracks:[Track]=[],vid=1
  }
  let info=Info(),mpv=MPVFixture()
  weak var mainWindow:MainWindowController!
  var disableWindowAnimation=false,ownedTrackGraph:String?
  var nativeRequests:Int {mainWindow?.videoView.videoLayer.updates ?? 0}
  var pausedRefreshFinishes=0
  var displayOSD=true
  var osdBegins:[UUID]=[],osdEnds:[UUID]=[]
  func beginVideoGeometryOSDRefresh()->UUID {let id=UUID();osdBegins.append(id);return id}
  func endVideoGeometryOSDRefresh(_ id:UUID){osdEnds.append(id)}
  func finishPausedCropRefresh(){pausedRefreshFinishes+=1}
  // PRODUCTION_PLAYER_METHODS
}
final class GeometrySeekFixture {
  let info=PlayerFixture.Info(),mpv=MPVFixture()
  struct FeedbackOrigins { func reset() {} }
  let osdFeedbackOrigins=FeedbackOrigins()
  // PRODUCTION_SEEK_FIELDS
  // PRODUCTION_SEEK_METHODS
}
final class MainWindowController {
  let player=PlayerFixture(),videoView=VideoFixture(),trace=EventTrace()
  var videoViewContainer:ContainerFixture! = ContainerFixture(frame:NSRect(x:0,y:0,width:800,height:450))
  var videoViewConstraints:[NSLayoutConstraint.Attribute:NSLayoutConstraint]=[:]
  var window:NSWindow?
  var loaded=true,isApplyingVideoTransformWindowFrame=false
  enum WindowState { case windowed,fullscreen }
  enum PIPStatus { case notInPIP,inPIP }
  enum OSCPosition { case floating,bottom }
  var fsState=WindowState.windowed,pipStatus=PIPStatus.notInPIP,oscPosition=OSCPosition.floating
  final class Editor { var isActive=false,isEntering=false }
  let interactiveMode=Editor()
  var cropExitOverlay:CropTransitionOverlay?
  var isShowingPersistentOSD=false
  final class LiveText { var requests=0;func requestAnalysis(){requests+=1} }
  let liveText=LiveText()
  final class Floating {
    let trace:EventTrace
    init(_ trace:EventTrace){self.trace=trace}
    func prepareForResize(to size:NSSize){trace.events.append("osc-prepare")}
    func updatePosition(deferringFinalLayout:Bool=false,afterPreparedResize:Bool=false){trace.events.append(deferringFinalLayout && afterPreparedResize ? "osc-prepared-position" : "osc-position")}
  }
  lazy var oscFloatingView=Floating(trace)
  var sizingCalls=0,parameterUpdates=0,interrupts=0,legacyFinishes=0,referencePrepares=0
  var cropRestartNotifications=0
  var lastMagnification:CGFloat=0,frameWhenStartedPinching:NSRect = .zero
  var requestedTarget=NSRect(x:300,y:80,width:400,height:450)
  // PRODUCTION_MAIN_FIELDS
  var motionExists:Bool { geometryMotion != nil }
  var motionOverlay:CropTransitionOverlay? {geometryMotion?.overlay}
  var waiting:Bool {geometryMotion?.waitingForFrame == true}
  var animating:Bool {geometryMotion?.animating == true}
  var expected:(Int,Double)? {geometryMotion.map{($0.expectedRotation,$0.expectedPAR)}}
  var targetFrame:NSRect? {geometryMotion?.targetWindowFrame}
  init(){
    player.mainWindow=self
    let window=MotionWindow(contentRect:NSRect(x:100,y:80,width:800,height:450),styleMask:[.borderless],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.trace=trace;self.window=window
    window.contentView=videoViewContainer;videoViewContainer.trace=trace
    videoViewContainer.addSubview(videoView);videoView.translatesAutoresizingMaskIntoConstraints=false
    videoViewConstraints=[.leading:videoView.leadingAnchor.constraint(equalTo:videoViewContainer.leadingAnchor),.trailing:videoView.trailingAnchor.constraint(equalTo:videoViewContainer.trailingAnchor),.top:videoView.topAnchor.constraint(equalTo:videoViewContainer.topAnchor),.bottom:videoView.bottomAnchor.constraint(equalTo:videoViewContainer.bottomAnchor)]
    NSLayoutConstraint.activate(Array(videoViewConstraints.values));videoViewContainer.layoutSubtreeIfNeeded();videoView.videoLayer.trace=trace
  }
  func prepareVideoTransformWindowReference(){referencePrepares+=1}
  func interruptPlayerCropTransition(){interrupts+=1}
  func finishVideoAspectTransition(){legacyFinishes+=1}
  func finishCropExitTransition(outputIsReady:Bool=false){if outputIsReady {cropRestartNotifications+=1}}
  func invalidateFloatingOSCLayout(){trace.events.append("osc-invalidate")}
  func handleVideoSizeChange(keepWindowSize:Bool){sizingCalls+=1;geometryMotion?.targetWindowFrame=Preference.unlockWindowAspectRatio ? window!.frame : requestedTarget}
  func updateWindowParametersForMPV(){parameterUpdates+=1;trace.events.append("window-parameters")}
  func publishOutput(){player.mpv.publishOutput();geometryVideoOutputDidChange()}
  // PRODUCTION_MAIN_METHODS
}
