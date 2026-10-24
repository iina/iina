var checks=0,failures:[String]=[]
func check(_ value:@autoclosure ()->Bool,_ message:String){checks+=1;if !value(){failures.append(message);print("FAIL:",message)}}
func drain(){
  var done=false;DispatchQueue.main.async{done=true}
  let deadline=Date().addingTimeInterval(2)
  while !done && Date()<deadline{RunLoop.current.run(until:Date().addingTimeInterval(0.001))}
  check(done,"main observer delivery reaches its boundary")
}
func complete(_ c:MainWindowController){
  var delivered=0
  for _ in 0..<12 {
    if !c.motionExists{return}
    c.publishOutput()
    if !c.motionExists{return}
    if c.videoView.videoLayer.callbacks.count>delivered {
      let callback=c.videoView.videoLayer.callbacks[delivered];delivered+=1;callback(true)
    }
    if c.animating {ClockTrace.advances.last?(1)}
  }
  check(!c.motionExists,"all reset geometry requests eventually finish")
}
for state in [PlayerFixture.State.paused,.playing] {
  for aspect in ["Default","4:3"] {
    for cropped in [false,true] {
      ClockTrace.reset();Preference.animationsDisabled=false
      let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
      let p=c.player,observer=RotationObserver(p)
      p.info.state=state;p.info.rotation=270;p.info.unsureAspect=aspect
      p.mpv.values["video-rotate"]=270
      if aspect != "Default" {_=p.mpv.setString("video-aspect-override",aspect)}
      if cropped {p.info.cropFilter=ResetFilter(Constants.FilterName.crop);p.info.unsureCrop="4:3";p.mpv.filters=[.init(label:Constants.FilterName.crop)]}
      p.mpv.updateDecoder();p.mpv.publishOutput();p.mpv.writes=[]
      let view=RotationView(player:p)
      let selector=view.subviews.compactMap{$0 as? NSSegmentedControl}.first!
      p.postNotification(.iinaTrackSettingsChanged)
      check(selector.selectedSegment==3,"initial rotation selection reflects270")
      p.mpv.onWrite={name,value in if name==MPVOption.Video.videoRotate,let angle=Int64(value){observer.receive(angle)}}
      p.resetTrackSettings(.videoGeometry)
      complete(c)
      check(p.mpv.getDouble("video-aspect-override")==(-1) && p.info.cropFilter==nil && p.mpv.getInt("video-rotate")==0,"one Reset commits Default/None/0 for\(state)/\(aspect)/crop\(cropped)")
      check(p.mpv.writes.filter{$0.0=="video-rotate" && $0.1=="0"}.count==1,"one Reset issues exactly one canonical rotation0 write")
      check(p.cropRemovals==(cropped ? 1:0),"Reset removes only an existing crop filter")
      drain()
      check(p.info.rotation==0,"rotation observer updates the canonical cached user angle")
      check(selector.selectedSegment==0,"first Reset observer refreshes the visible selector for\(state)/\(aspect)/crop\(cropped)")
      let writes=p.mpv.writes.count
      p.resetTrackSettings(.videoGeometry)
      check(selector.selectedSegment==0 && p.mpv.writes.count==writes,"second Reset is an engine no-op rather than a required UI repair")
    }
  }
}
for phase in ["preparing","animating"] {
  for state in [PlayerFixture.State.paused,.playing] {
    ClockTrace.reset();let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
    let p=c.player,observer=RotationObserver(p)
    p.info.state=state;p.info.rotation=270;p.info.unsureAspect="4:3";p.mpv.values["video-rotate"]=270
    _=p.mpv.setString("video-aspect-override","4:3");p.mpv.updateDecoder();p.mpv.publishOutput()
    p.info.cropFilter=ResetFilter(Constants.FilterName.crop);p.info.unsureCrop="Custom";p.mpv.filters=[.init(label:Constants.FilterName.crop)]
    let view=RotationView(player:p),selector=view.subviews.compactMap{$0 as? NSSegmentedControl}.first!
    p.postNotification(.iinaTrackSettingsChanged);p.mpv.writes=[]
    p.mpv.onWrite={name,value in if name==MPVOption.Video.videoRotate,let angle=Int64(value){observer.receive(angle)}}
    p.setVideoAspect("16:9")
    if phase=="animating" {c.publishOutput();c.videoView.videoLayer.callbacks.first?(true);ClockTrace.advances.last?(0.3)}
    check(c.motionExists && (phase=="preparing" ? !c.animating:c.animating),"Reset regression starts with an existing\(phase) owner in\(state)")
    p.resetTrackSettings(.videoGeometry)
    complete(c);drain()
    check(p.mpv.getDouble("video-aspect-override")==(-1) && p.info.cropFilter==nil && p.mpv.getInt("video-rotate")==0,"Reset drains latest canonical Default/None/0 through an existing\(phase) owner")
    check(p.mpv.writes.filter{$0.0=="video-rotate" && $0.1=="0"}.count==1 && selector.selectedSegment==0,"existing\(phase) Reset updates selector from one committed rotation write")
  }
}

do {
  let c=MainWindowController(),p=c.player,observer=RotationObserver(c.player)
  p.info.rotation=270
  let view=RotationView(player:p),selector=view.subviews.compactMap{$0 as? NSSegmentedControl}.first!
  p.postNotification(.iinaTrackSettingsChanged)
  var reportedAngles:[Int]=[]
  p.observe(.iinaVideoParamsChanged){_ in reportedAngles.append(p.info.rotation)}
  observer.receive(0)
  check(p.info.rotation==270 && selector.selectedSegment==3 && reportedAngles.isEmpty,"rotation observer keeps cache/UI/notification delivery asynchronous")
  drain()
  check(reportedAngles==[0] && selector.selectedSegment==0,"notification observes the updated angle before refreshing the actual selector")
  check(p.mpv.writes.isEmpty && p.settingOSDs==0,"observer refresh does not issue engine writes or extra OSD")
  let notifications=reportedAngles.count
  observer.handleProperty(.init(data:nil,format:4));drain()
  check(observer.errors==1 && p.info.rotation==0 && reportedAngles.count==notifications,"invalid native property preserves error handling and emits no refresh")
  p.scopedTrackSettings.setTarget(2,for:.videoGeometry);p.scopedTrackSettings.video[2]=VideoTrackProcessing(rotation:90)
  p.postNotification(.iinaTrackSettingsChanged);observer.receive(180);drain()
  check(p.info.rotation==180 && selector.selectedSegment==1,"output angle notification preserves the selected source track's independent90-degree value")
}
print("Geometry Reset: \(checks) production reset/queue/observer/UI checks; failures=\(failures.count)")
if !failures.isEmpty{exit(1)}
