// Pure value/key matching is used across typed writes and differently formatted
// engine observations; nonfinite numeric values must never match by tolerance.
for (text,value) in [("yes",1.0),("no",0.0),("1.000",1.0),("-0.5",-0.5),("1e3",1000.0)] {
  check(OSDFeedbackValue(text).matches(.number(value)),"value normalization matches\(text) with its typed engine value")
}
check(OSDFeedbackValue("4:3") == .text("4:3") && !OSDFeedbackValue("YES").matches(.number(1)),"non-numeric text retains exact semantics")
check(OSDFeedbackValue.number(2).matches(.number(2.000001)) && !OSDFeedbackValue.number(2).matches(.number(2.00001)),"numeric matching tolerates formatting precision without suppressing a different setting")
check(OSDFeedbackValue.number(10000).matches(.number(10000.005)) && !OSDFeedbackValue.number(10000).matches(.number(10000.02)),"matching tolerance scales with magnitude")
check(!OSDFeedbackValue.number(.nan).matches(.number(.nan)) && !OSDFeedbackValue.number(.infinity).matches(.number(.infinity)),"nonfinite typed values cannot match setting acknowledgements")

do {
  let origins=OSDFeedbackOrigins()
  let speed=origins.record("options/speed",value:.number(2),origin:.sidebar)
  check(speed != nil && origins.origin(for:"file-local-options/speed",value:OSDFeedbackValue("2.0")) == .sidebar,"property prefixes share one typed sidebar intent")
  check(origins.origin(for:"speed",value:.number(3)) == .command && origins.origin(for:"speed",value:nil) == .command,"mismatching or unavailable observations remain visible")
  check(origins.origin(for:"speed",value:.number(2)) == .command,"a different observed value clears stale quiet attribution before a later external return")
  _=origins.record("volume",value:.number(20),origin:.sidebar)
  _=origins.record("speed",value:.number(2),origin:.command)
  check(origins.origin(for:"speed",value:.number(2)) == .command && origins.origin(for:"volume",value:.number(20)) == .sidebar,"keyboard command supersedes only its own property even at the same value")
  let old=origins.record("speed",value:.number(2),origin:.sidebar)
  let latest=origins.record("speed",value:.number(3),origin:.sidebar)
  origins.cancel("options/speed",token:old)
  check(origins.origin(for:"speed",value:.number(3)) == .sidebar,"failed old mutation cannot cancel a newer intent")
  origins.cancel("different",token:latest);origins.cancel("speed",token:nil)
  check(origins.origin(for:"speed",value:.number(3)) == .sidebar,"wrong-property and nil rollback tokens are harmless")
  origins.cancel("file-local-options/speed",token:latest)
  check(origins.origin(for:"speed",value:.number(3)) == .command,"failed current mutation removes its matching sidebar token")
  _=origins.record("volume",value:nil,origin:.sidebar)
  check(origins.origin(for:"volume",value:.number(20)) == .command,"unknown mutation value cannot leave stale quiet attribution")
  _=origins.record("speed",value:.number(4),origin:.sidebar);origins.reset()
  check(origins.origin(for:"speed",value:.number(4)) == .command,"lifecycle reset clears recorded provenance")
}

do {
  let origins=OSDFeedbackOrigins(),lock=NSLock();var concurrentFailures=0
  DispatchQueue.concurrentPerform(iterations:128){index in
    let key="setting-\(index)",value=OSDFeedbackValue.number(Double(index))
    let token=origins.record(key,value:value,origin:.sidebar)
    let first=origins.origin(for:key,value:value)
    origins.cancel(key,token:token)
    let second=origins.origin(for:key,value:value)
    if first != .sidebar || second != .command {lock.lock();concurrentFailures+=1;lock.unlock()}
  }
  check(concurrentFailures==0,"locked provenance supports independent MPV/event-thread interleaving")
}

do {
  let p=PlayerFixture()
  check(p.currentOSDFeedbackOrigin == .command,"ordinary command is the default without consulting sidebar visibility")
  let result=p.performSidebarChange{() -> Int in
    check(p.currentOSDFeedbackOrigin == .sidebar,"direct sidebar action enters its explicit context")
    let nested=p.withOSDFeedbackOrigin(.command){() -> Int in
      check(p.currentOSDFeedbackOrigin == .command,"keyboard/menu context can override an open sidebar action")
      p.sendOSD(.speed(1.5));return 9
    }
    check(nested==9 && p.currentOSDFeedbackOrigin == .sidebar,"nested context restores its previous origin and generic result")
    p.sendOSD(.speed(2));return 42
  }
  check(result==42 && p.currentOSDFeedbackOrigin == .command,"sidebar context restores default after returning a value")
  drain()
  check(p.mainWindow.deliveries.count==1,"only the nested ordinary command's setting OSD is queued")
  var backgroundOrigin=OSDFeedbackOrigin.sidebar
  let signal=DispatchSemaphore(value:0)
  p.performSidebarChange{
    DispatchQueue.global().async{backgroundOrigin=p.currentOSDFeedbackOrigin;signal.signal()}
    check(signal.wait(timeout:.now()+1) == .success,"background provenance query completes independently")
  }
  check(backgroundOrigin == .command,"sidebar context cannot leak onto the MPV event queue")
}

do {
  let p=PlayerFixture()
  let action=p.performSidebarChange{p.preservingOSDFeedbackOrigin{() -> Int in
    check(p.currentOSDFeedbackOrigin == .sidebar,"deferred mutation restores its captured sidebar origin")
    p.sendOSD(.aspect("4:3"));return 17
  }}
  check(action()==17 && p.currentOSDFeedbackOrigin == .command,"deferred sidebar mutation preserves result and restores caller context")
  let command=p.preservingOSDFeedbackOrigin{p.sendOSD(.rotate(90))}
  p.performSidebarChange{command();check(p.currentOSDFeedbackOrigin == .sidebar,"deferred normal command restores surrounding sidebar context")}
  drain()
  check(p.mainWindow.deliveries.count==1,"deferred normal command remains visible while deferred sidebar change stays quiet")
}

let settingFeedback:[OSDMessage]=[.speed(2),.aspect("4:3"),.crop("None"),.rotate(0),.audioDelay(0.5),.subDelay(1),.secondSubPos(20),.track(MPVTrack()),.brightness(20),.hwdec(true),.addFilter("eq"),.removeFilter,.volume(10)]
for message in settingFeedback {
  let p=PlayerFixture()
  p.performSidebarChange{p.sendOSD(message)}
  p.sendOSD(message);drain()
  check(message.isSettingFeedback && p.mainWindow.deliveries.count==1,"setting feedback is quiet for a sidebar control and visible for command/menu while the panel stays open")
}
for message:OSDMessage in [.pause,.resume,.seek("1","2",0.5),.screenshot,.custom("plugin status"),.networkError,.fileError,.cannotConnect] {
  let p=PlayerFixture();p.performSidebarChange{p.sendOSD(message)};drain()
  check(!message.isSettingFeedback && p.mainWindow.deliveries.count==1,"sidebar context preserves unrelated playback, error and asynchronous notification feedback")
}

do {
  let p=PlayerFixture()
  _=p.osdFeedbackOrigins.record("speed",value:.number(2),origin:.sidebar)
  deliver(p,property:"speed",value:.number(2),message:.speed(2))
  // Delivery of this already-classified sidebar acknowledgement can be delayed
  // until after another command has superseded that property's intent.
  _=p.osdFeedbackOrigins.record("speed",value:.number(3),origin:.command)
  deliver(p,property:"speed",value:.number(3),message:.speed(3))
  _=p.osdFeedbackOrigins.record("volume",value:.number(20),origin:.sidebar)
  deliver(p,property:"volume",value:.number(21),message:.volume(21))
  deliver(p,property:"volume",value:.number(20),message:.volume(20))
  drain();drain()
  check(p.mainWindow.deliveries.count==3,"captured asynchronous origins preserve old quiet acknowledgement and keep a later command/mismatch/return visible")
  p.sendOSD(.speed(4))
  p.performSidebarChange{drain()}
  check(p.mainWindow.deliveries.count==4,"ordinary queued feedback is not reclassified by an unrelated sidebar context at delivery time")
}

do {
  let p=PlayerFixture(),accessory=NSView(),context=NSObject()
  p.performSidebarChange{p.sendOSD(.speed(2),autoHide:false,forcedTimeout:7,accessoryView:accessory,context:context,external:true)}
  drain()
  let delivered=p.mainWindow.deliveries.first
  check(delivered?.autoHide==false && delivered?.timeout==7 && delivered?.accessory===accessory && delivered?.context as? NSObject === context,"external plugin feedback bypasses sidebar quieting and preserves delivery metadata")
  Preference.enabled=false
  p.performSidebarChange{p.sendOSD(.speed(3),external:true);p.sendOSD(.networkError)};drain()
  check(p.mainWindow.deliveries.count==2,"external flag preserves normal OSD preference while always-enabled error UI survives")
  Preference.reset();p.info.disableOSDForFileLoading=true
  p.sendOSD(.speed(4));p.sendOSD(.fileStart("fixture"));p.performSidebarChange{p.sendOSD(.speed(5),external:true)};drain()
  check(p.mainWindow.deliveries.count==4,"file-loading gate remains intact with its existing external-message exception")
}

do {
  let p=PlayerFixture();p.sendOSD(.speed(2));p.info.state.active=false;p.mainWindow.engineClosed=true;drain()
  check(p.mainWindow.deliveries.isEmpty,"stopping after enqueue still prevents stale OSD delivery into closed engine")
}
Preference.disabled=[.disableOSDSpeedMsg]
do {let p=PlayerFixture();p.sendOSD(.speed(2));p.performSidebarChange{p.sendOSD(.speed(3),external:true)};drain();check(p.mainWindow.deliveries.isEmpty,"normal disabled-message preferences also apply to external feedback")}
Preference.reset()
print("Sidebar OSD: \(checks) extracted policy/context/delivery checks; failures=\(failures.count)")
if !failures.isEmpty{exit(1)}
