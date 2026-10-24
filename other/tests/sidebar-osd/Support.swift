import Cocoa

enum PlaybackInfo {enum LoopStatus {case cleared}}
final class MPVTrack {}
enum Preference {
  enum Key:Hashable {case enableOSD,disableOSDFileStartMsg,disableOSDPauseResumeMsgs,disableOSDSeekMsg,disableOSDSpeedMsg}
  static var disabled=Set<Key>(),enabled=true
  static func bool(for key:Key)->Bool {key == .enableOSD ? enabled:disabled.contains(key)}
  static func reset(){disabled=[];enabled=true}
}
final class WindowFixture {
  struct Delivery {let message:OSDMessage;let autoHide:Bool;let timeout:Float?;let accessory:NSView?;let context:Any?}
  var loaded=true,engineClosed=false,sidebarOpen=true
  var speedUpdates=0
  var deliveries:[Delivery]=[]
  func displayOSD(_ message:OSDMessage,autoHide:Bool,forcedTimeout:Float?,accessoryView:NSView?,context:Any?){
    precondition(!engineClosed,"queued OSD queried a closed engine")
    deliveries.append(.init(message:message,autoHide:autoHide,timeout:forcedTimeout,accessory:accessoryView,context:context))
  }
  func updateSpeedLabel(speed:Double){speedUpdates+=1}
}
final class PlayerFixture {
  final class Info {
    struct State {var active=true}
    var state=State(),disableOSDForFileLoading=false
    var playSpeed=1.0,audioDelay=0.0,brightness=0,isMuted=false,hwdec="no"
    var hwdecEnabled:Bool {hwdec != "no"}
  }
  let info=Info(),mainWindow=WindowFixture()
  var isInMiniPlayer=false
  enum Sync {case volume}
  var syncs=0,notifications:[Notification.Name]=[]
  func syncUI(_ kind:Sync){syncs+=1}
  func postNotification(_ name:Notification.Name){notifications.append(name)}
  // PRODUCTION_CONTEXT
  // PRODUCTION_DELIVERY
  // PRODUCTION_PLAYER_OBSERVATION
}
enum NowPlayingInfoManager {static let shared=Manager();struct Manager{func updateInfo(){}}}
extension Notification.Name {
  static let iinaSpeedChanged=Self("speed"),iinaAudioDelayChanged=Self("audio-delay"),iinaVideoEqualizerChanged=Self("video-eq"),iinaHwdecChanged=Self("hwdec")
}

var checks=0,failures:[String]=[]
func check(_ condition:@autoclosure ()->Bool,_ message:String){checks+=1;if !condition(){failures.append(message);print("FAIL:",message)}}
func drain(){
  var done=false;DispatchQueue.main.async{done=true}
  let deadline=Date().addingTimeInterval(2)
  while !done && Date()<deadline{RunLoop.current.run(until:Date().addingTimeInterval(0.001))}
  check(done,"main delivery drain completes")
}
func deliver(_ p:PlayerFixture,property:String,value:OSDFeedbackValue?,message:OSDMessage){
  let captured=p.osdFeedbackOrigins.origin(for:property,value:value)
  DispatchQueue.main.async{p.withOSDFeedbackOrigin(captured){p.sendOSD(message)}}
}
