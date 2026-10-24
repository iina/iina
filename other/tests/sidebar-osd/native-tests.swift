let mutations:[(String,(Controller)->Void,Controller.Observation)]=[
  ("speed",{$0.setDouble("options/speed",2)},.number(2)),
  ("brightness",{$0.setInt("brightness",10)},.integer(10)),
  ("mute",{$0.setFlag("mute",true)},.flag(true)),
  ("hwdec",{_=$0.setString("file-local-options/hwdec","auto")},.text("auto"))
]
for (property,write,value) in mutations {
  let p=PlayerFixture(),c=Controller(p)
  var recordedBeforeWrite=false
  c.native.onWrite={name,value in recordedBeforeWrite=p.osdFeedbackOrigins.origin(for:name,value:value) == .sidebar}
  p.performSidebarChange{write(c)}
  check(recordedBeforeWrite,"typed\(property) records sidebar provenance before the native setter can publish an observation")
  c.observe(property,value);drain();drain()
  check(p.mainWindow.deliveries.isEmpty,"actual typed\(property) observer inherits quiet sidebar origin after asynchronous dispatch")
  check(property=="mute" ? p.syncs==1 : !p.notifications.isEmpty,"quiet\(property) retains UI synchronization/notification side effects")
  check(c.native.writes.count==1,"quiet feedback does not require a replacement engine mutation")
}

do {
  let p=PlayerFixture(),c=Controller(p)
  p.performSidebarChange{c.setDouble("speed",2)}
  c.setDouble("speed",2)
  c.observe("speed",.number(2));drain();drain()
  check(p.mainWindow.deliveries.count==1 && p.mainWindow.sidebarOpen,"same-value keyboard/menu write stays visible while the sidebar remains open")
  p.performSidebarChange{c.setInt("brightness",10)}
  c.observe("brightness",.integer(15));c.observe("brightness",.integer(10));drain();drain()
  check(p.mainWindow.deliveries.count==3 && p.info.brightness==10,"mismatching observation and later external return to the old value both remain visible")
}
do {
  let p=PlayerFixture(),c=Controller(p)
  p.performSidebarChange{c.setDouble("speed",2)}
  c.observe("speed",.number(2))
  c.setDouble("speed",3)
  c.observe("speed",.number(3))
  p.performSidebarChange{c.setDouble("audio-delay",0.25)}
  c.setInt("brightness",20);c.observe("brightness",.integer(20));c.observe("audio-delay",.number(0.25))
  drain();drain()
  check(p.mainWindow.deliveries.count==2 && p.info.playSpeed==3,"observation origin is copied before delayed main delivery and interleaved normal commands remain visible")
  check(p.notifications.filter{$0 == .iinaSpeedChanged}.count==2 && p.notifications.contains(.iinaAudioDelayChanged) && p.notifications.contains(.iinaVideoEqualizerChanged),"suppression cannot skip property cache or asynchronous notifications")
}
for (property,write,value) in mutations {
  let p=PlayerFixture(),c=Controller(p);c.native.failNext=true
  p.performSidebarChange{write(c)}
  c.observe(property,value);drain();drain()
  check(p.mainWindow.deliveries.count==1,"failed typed\(property) write rolls back quiet attribution for a later external observation")
}
do {
  let p=PlayerFixture(),c=Controller(p);c.native.failNext=true
  c.native.onWrite={_,_ in c.native.onWrite=nil;c.setDouble("speed",3)}
  p.performSidebarChange{c.setDouble("speed",2)}
  c.observe("speed",.number(3));drain();drain()
  check(p.mainWindow.deliveries.isEmpty && p.info.playSpeed==3,"failed older setter token cannot remove a newer successful sidebar mutation")
}
do {
  let p=PlayerFixture(),c=Controller(p)
  p.performSidebarChange{_ = c.setString("speed","2.000")}
  c.observe("speed",.number(2));drain();drain()
  check(p.mainWindow.deliveries.isEmpty && p.info.playSpeed==2,"string numeric write matches the engine's typed double acknowledgement")
  p.performSidebarChange{c.setFlag("mute",false)};c.observe("mute",.flag(false));drain();drain()
  check(p.mainWindow.deliveries.isEmpty && !p.info.isMuted,"false/no flag normalization preserves quiet acknowledgement")
  p.performSidebarChange{_ = c.setString("hwdec","auto")};c.observe("hwdec",.text("auto"));drain();drain()
  check(p.info.hwdec=="auto" && p.mainWindow.deliveries.isEmpty,"string property data is copied before the native event buffer is released")
  let notifications=p.notifications.count;c.observe("speed",.missing);drain();drain()
  check(c.errors==1 && p.notifications.count==notifications && p.mainWindow.deliveries.isEmpty,"invalid property keeps error logging without manufacturing setting feedback or UI notifications")
}
for (label,writes,observations) in [
  ("ordered",[10,20],[10,20]),
  ("coalesced",[10,20],[20]),
  ("duplicate",[10,20],[10,20,20]),
  ("toggle",[10,20,10],[10,20,10]),
  ("coalesced-toggle",[10,20,10],[10]),
  ("repeated-write",[10,10,20],[10,10,20])
] {
  let p=PlayerFixture(),c=Controller(p)
  p.performSidebarChange{for value in writes {c.setInt("brightness",value)}}
  for value in observations {c.observe("brightness",.integer(Int64(value)))}
  drain();drain()
  check(p.mainWindow.deliveries.isEmpty && p.info.brightness==observations.last,"rapid\(label) slider acknowledgements stay quiet and finish at the actual observed value")
  check(p.notifications.count==observations.count,"rapid\(label) quieting preserves every observer notification")
  c.setInt("brightness",30);c.observe("brightness",.integer(30));drain();drain()
  check(p.mainWindow.deliveries.count==1,"normal command after rapid\(label) clears that property's pending UI acknowledgements")
}
do {
  let p=PlayerFixture(),c=Controller(p)
  p.performSidebarChange{c.setInt("brightness",10);c.native.failNext=true;c.setInt("brightness",20)}
  c.observe("brightness",.integer(10));drain();drain()
  check(p.mainWindow.deliveries.isEmpty,"failed latest slider write retains the earlier successful pending acknowledgement")
  c.observe("brightness",.integer(20));drain();drain()
  check(p.mainWindow.deliveries.count==1,"failed latest slider value cannot acquire quiet feedback later")
}
for (property,write,value) in [
  ("lavfi-complex",{(c:Controller) in _=c.setString("lavfi-complex","[aid1]anull[ao]")},OSDFeedbackValue.text("[aid1]anull[ao]")),
  ("vf",{(c:Controller) in _=c.setString("vf","scale=640:360")},OSDFeedbackValue.text("scale=640:360")),
  ("af",{(c:Controller) in _=c.setString("af","volume=1")},OSDFeedbackValue.text("volume=1")),
  ("sub-font",{(c:Controller) in _=c.setString("options/sub-font","HelveticaNeue")},OSDFeedbackValue.text("HelveticaNeue")),
  ("sub-font-size",{(c:Controller) in c.setDouble("options/sub-font-size",48)},OSDFeedbackValue.number(48)),
  ("video-out-params",{(c:Controller) in c.native.failNext=true;_=c.setString("video-out-params","node")},OSDFeedbackValue.text("node"))
] {
  let p=PlayerFixture(),c=Controller(p)
  p.performSidebarChange{for _ in 0..<32 {write(c)}}
  check(p.osdFeedbackOrigins.origin(for:property,value:value) == .command,"\(property) without typed acknowledgement cannot retain quiet provenance")
  check(c.native.writes.count==32,"filtering\(property) bookkeeping preserves every native setter call")
}
print("Sidebar OSD native hooks: \(checks) total extracted policy/mutation/observation/delivery checks; failures=\(failures.count)")
if !failures.isEmpty{exit(1)}
