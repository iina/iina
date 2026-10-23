var checks=0,failures:[String]=[]
func check(_ value:@autoclosure ()->Bool,_ message:String){checks+=1;if !value(){failures.append(message);print("FAIL:",message)}}
func near(_ a:CGFloat,_ b:CGFloat)->Bool {abs(a-b)<0.001}
func near(_ a:NSRect,_ b:NSRect)->Bool {near(a.minX,b.minX) && near(a.minY,b.minY) && near(a.width,b.width) && near(a.height,b.height)}
func reset(){Preference.animationsDisabled=false;Preference.unlockWindowAspectRatio=false;AccessibilityPreferences.motionReductionEnabled=false;ClockTrace.reset()}
func projectedRect(_ layer:CALayer)->NSRect {
  let b=layer.bounds,t=layer.transform
  let corners=[NSPoint(x:b.minX,y:b.minY),NSPoint(x:b.maxX,y:b.minY),NSPoint(x:b.maxX,y:b.maxY),NSPoint(x:b.minX,y:b.maxY)].map{point -> NSPoint in
    let x=point.x-b.minX-b.width*layer.anchorPoint.x,y=point.y-b.minY-b.height*layer.anchorPoint.y
    return NSPoint(x:layer.position.x+x*t.m11+y*t.m21+t.m41,y:layer.position.y+x*t.m12+y*t.m22+t.m42)
  }
  return NSRect(x:corners.map{$0.x}.min()!,y:corners.map{$0.y}.min()!,width:corners.map{$0.x}.max()!-corners.map{$0.x}.min()!,height:corners.map{$0.y}.max()!-corners.map{$0.y}.min()!)
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
  check(!c.motionExists,"controlled completion drains all queued motion")
}

// Actual perform/readiness/frame/clock/finish path, with real native affine owner.
reset()
do {
  let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  c.player.mpv.onWrite={_,_ in check(c.videoView.videoLayer.isPreparingCropFrame,"native preparation gate precedes engine mutation")}
  let original=c.window!.frame
  c.player.setVideoRotate(90)
  check(c.motionExists && c.motionOverlay != nil,"first quarter rotation owns native motion")
  check(c.expected?.0==90 && c.videoView.videoLayer.callbacks.isEmpty,"old effective rotation cannot release readiness")
  c.geometryVideoOutputDidChange()
  check(c.sizingCalls==0 && c.player.nativeRequests==0,"mismatched output cannot size or request a native frame")
  c.publishOutput()
  check(c.waiting && c.videoView.videoLayer.callbacks.count==1,"matching output registers exactly one native waiter")
  c.geometryVideoOutputDidChange()
  check(c.videoView.videoLayer.callbacks.count==1 && ClockTrace.policies.isEmpty,"repeat metadata cannot bypass or duplicate the native gate")
  c.videoView.videoLayer.callbacks.first?(true)
  check(c.animating && ClockTrace.policies.count==1,"native frame starts shared production clock")
  check(ClockTrace.policies.first?.0==0.4 && near(ClockTrace.policies[0].1.progress(at:0.1),0.028),"actual clock receives400ms smoothstep policy")
  check(ClockTrace.policies.first?.2==true,"new geometry motion starts its400ms interval on first UI refresh")
  check(near(c.videoView.bounds.width/c.videoView.bounds.height,9/16),"native raster initializes at target true aspect before inverse compensation")
  check(near(c.videoView.assignedFrames.last!.width/c.videoView.assignedFrames.last!.height,9/16),"raster allocation frame uses canonical target aspect")
  check(near(projectedRect(c.videoView.videoLayer),NSRect(x:0,y:0,width:800,height:450)),"initial inverse compensation reproduces old visible rectangle")
  let fixedRaster=c.videoView.bounds,writes=c.player.mpv.writes.count
  let advance=ClockTrace.advances[0]
  for time in [0.0,0.1,0.5,0.9] {
    c.trace.events=[];advance(time)
    check(c.player.mpv.writes.count==writes,"animation tick never writes engine options")
    check(c.videoView.bounds==fixedRaster,"animation tick preserves canonical fixed raster")
    let e=c.trace.events
    if let prepare=e.firstIndex(of:"osc-prepare"),let frame=e.firstIndex(of:"window-frame"),let post=e.firstIndex(of:"osc-prepared-position"),let layout=e.lastIndex(of:"layout"),let projection=e.lastIndex(of:"projection") {
      check(prepare<frame && frame<post && post<layout && layout<projection,"window and prepared OSC finish layout before native projection")
    }else{check(false,"animation tick records complete OSC/frame/layout/projection sequence")}
  }
  let requested=(c.window as! MotionWindow).requested
  check(requested.contains{near($0.width,original.width+(c.requestedTarget.width-original.width)*0.028)},"first tenth follows smoothstep rather than ease-out catch-up")
  advance(1)
  check(!c.motionExists && near(c.window!.frame,c.requestedTarget),"clock completion settles exact window endpoint")
  check(!c.videoView.videoLayer.isInCropTransition && !c.videoView.videoLayer.isPreparingCropFrame && c.videoView.videoLayer.cancelCount==1,"completion releases native gates once")
  check(c.player.osdBegins.count==1 && c.player.osdEnds==c.player.osdBegins,"completion releases the matching OSD refresh token")
  let handoffs=c.videoView.videoLayer.handoffs.count;advance(1)
  check(c.videoView.videoLayer.handoffs.count==handoffs,"old clock callback cannot finish a completed owner again")
}

// PAR and effective rotation are independent gates, including same-sized turns.
for kind in ["par","180","square90","default-same-aspect"] {
  reset();let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  if kind=="square90" {
    c.player.mpv.defaultAspect=1
    for prefix in ["video-params","video-out-params"] {for key in ["w","h","dw","dh"] {c.player.mpv.values[prefix+"/"+key]=1024}}
  }
  if kind=="default-same-aspect" {c.player.mpv.values["video-aspect-override"]=16/9;c.requestedTarget=c.window!.frame;c.player.setVideoAspect("Default")}
  else if kind=="par" {c.player.setVideoAspect("4:3")}
  else {c.player.setVideoRotate(kind=="180" ? 180 : 90)}
  check(c.motionOverlay != nil,"\(kind) receives the shared visual transition")
  if kind != "default-same-aspect" {check(c.videoView.videoLayer.callbacks.isEmpty,"\(kind) retains source until matching output metadata")}
  if kind=="par" {
    c.player.mpv.publishOutput();c.player.mpv.values["video-out-params/par"]=0.75002;c.geometryVideoOutputDidChange()
    check(c.videoView.videoLayer.callbacks.isEmpty,"same rotate/W/H with wrong PAR cannot release readiness")
  }
  c.publishOutput()
  check(c.videoView.videoLayer.callbacks.count==1,"\(kind) uses explicit native readiness without requiring changed W/H")
  c.videoView.videoLayer.callbacks.first?(true)
  check(c.animating,"\(kind) begins after native output is prepared")
  ClockTrace.advances.last?(0.5)
  check(c.videoView.bounds.width>0 && c.videoView.bounds.height>0,"\(kind) has no midpoint collapse")
  ClockTrace.advances.last?(1)
  check(!c.motionExists,"\(kind) completes without a nonexistent size-change event")
}

for embedded in [90,180,270] {
  reset();let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  c.player.mpv.sourceRotation=embedded;c.player.mpv.updateDecoder();c.player.mpv.publishOutput()
  let oldVisible=CropTransitionOverlay.fit(c.player.interactiveVideoGeometry(uncropped:false).displaySize,in:c.videoViewContainer.bounds)
  c.player.setVideoRotate(90)
  check(c.expected?.0==(embedded+90)%360,"embedded\(embedded) readiness captures effective rotation rather than user option")
  c.player.mpv.values["video-out-params/rotate"]=90;c.geometryVideoOutputDidChange()
  check(c.videoView.videoLayer.callbacks.isEmpty,"embedded\(embedded) cannot accept the user angle as effective output")
  c.publishOutput();c.videoView.videoLayer.callbacks.first?(true)
  check(c.animating && near(projectedRect(c.videoView.videoLayer),oldVisible),"embedded\(embedded) inverse compensation preserves the previous fitted image")
  ClockTrace.advances.last?(1)
  check(!c.motionExists,"embedded\(embedded) completes at the effective rotation endpoint")
}

// Ordinary subsequent aspect/rotation requests must not be excluded by Crop's
// stricter source predicate after an earlier option was committed.
for turn in [90,180,270] {
  reset();let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  c.player.mpv.values["video-aspect-override"]=4/3
  c.player.mpv.values["video-rotate"]=Double(turn);c.player.mpv.updateDecoder();c.player.mpv.publishOutput()
  check(c.player.canAnimateVideoGeometry && !c.player.canAnimateCropSource,"existing4:3 +\(turn) accepts geometry compensation without widening Crop eligibility")
  c.player.setVideoRotate((turn+90)%360)
  check(c.motionOverlay != nil,"rotation from existing\(turn) degrees remains animated")
  complete(c)
}

// The actual source predicate accepts only geometry this one native surface can
// compensate. Unsupported options still commit once through the canonical path.
let rejectedSources:[(String,(PlayerFixture)->Void)]=[
  ("zoom",{$0.mpv.values["video-zoom"]=0.2}),
  ("pan-x",{$0.mpv.values["video-pan-x"] = -0.1}),
  ("pan-y",{$0.mpv.values["video-pan-y"]=0.1}),
  ("panscan",{$0.mpv.values["panscan"]=0.2}),
  ("align-x",{$0.mpv.values["video-align-x"]=0.1}),
  ("align-y",{$0.mpv.values["video-align-y"] = -0.1}),
  ("margin-left",{$0.mpv.values["video-margin-ratio-left"]=0.05}),
  ("margin-right",{$0.mpv.values["video-margin-ratio-right"]=0.05}),
  ("margin-top",{$0.mpv.values["video-margin-ratio-top"]=0.05}),
  ("margin-bottom",{$0.mpv.values["video-margin-ratio-bottom"]=0.05}),
  ("scale-x",{$0.mpv.values["video-scale-x"]=1.1}),
  ("scale-y",{$0.mpv.values["video-scale-y"]=0.9}),
  ("arbitrary-angle",{$0.mpv.values["video-rotate"]=45}),
  ("video-crop",{$0.mpv.strings["video-crop"]="640x360+10+10"}),
  ("unscaled",{$0.mpv.strings["video-unscaled"]="yes"}),
  ("unowned-filter",{$0.mpv.filters=[.init(label:nil)]}),
  ("flip-filter",{$0.mpv.filters=[.init(label:"flip")]}),
  ("crop-and-extra-filter",{$0.mpv.filters=[.init(label:Constants.FilterName.crop),.init(label:"mirror")]}),
  ("independent-graph",{$0.mpv.strings["lavfi-complex"]="[vid1]scale=640:360[vo]"}),
  ("owned-video-graph",{$0.ownedTrackGraph="[vid1]null[vo]";$0.mpv.strings["lavfi-complex"]=$0.ownedTrackGraph})
]
for (name,configure) in rejectedSources {
  reset();let c=MainWindowController();defer{c.cancelVideoGeometryTransition()};configure(c.player)
  check(!c.player.canAnimateVideoGeometry,"\(name) rejects native compensation")
  c.player.setVideoAspect("4:3")
  check(c.motionOverlay==nil && ClockTrace.policies.isEmpty,"\(name) uses canonical nonanimated geometry")
  c.publishOutput()
  check(!c.motionExists && c.player.mpv.writes.count==1 && c.videoView.videoLayer.callbacks.isEmpty,"\(name) completes once without a native visual waiter")
}
reset()
do {
  let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  c.player.mpv.filters=[.init(label:Constants.FilterName.crop)]
  c.player.ownedTrackGraph="[aid1][aid2]amix[ao]";c.player.mpv.strings["lavfi-complex"]=c.player.ownedTrackGraph
  check(c.player.canAnimateVideoGeometry,"owned crop + audio-only graph retains independent native video")
  c.player.setVideoRotate(90)
  check(c.motionOverlay != nil,"owned crop + audio-only graph uses visual path")
  complete(c)
}

// A graph can intentionally replace the decoder's PAR/effective rotation. Its
// first real output event must finish the nonanimated scope; the initial call
// immediately after an option write is not such an event.
reset()
do {
  let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  c.player.mpv.strings["lavfi-complex"]="[vid1]scale=640:360,setsar=2[vo]"
  c.player.setVideoRotate(90)
  check(c.motionExists && c.motionOverlay==nil && c.sizingCalls==0,"graph mismatch remains pending after apply's non-output readiness call")
  c.geometryVideoOutputDidChange(fromOutputEvent:false)
  check(c.motionExists && c.sizingCalls==0,"repeated initial graph checks cannot masquerade as an output event")
  c.player.mpv.values["video-out-params/rotate"]=180;c.player.mpv.values["video-out-params/par"]=2
  c.geometryVideoOutputDidChange()
  check(!c.motionExists && c.sizingCalls==1 && c.player.osdEnds.count==1,"actual graph output releases mismatching PAR/rotation without stranding OSD ownership")
  check(ClockTrace.policies.isEmpty && c.videoView.videoLayer.callbacks.isEmpty,"arbitrary graph fallback does not acquire native visual ownership")
}
for aspect in ["4:3","16:9"] {
  reset();let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  _=c.player.mpv.setString("video-aspect-override",aspect);c.player.mpv.publishOutput();c.player.mpv.writes=[]
  c.player.setVideoAspect(aspect=="4:3" ? "16:9" : "4:3")
  check(c.motionOverlay != nil,"aspect from existing\(aspect) override remains animated")
  complete(c)
}

// Latest pending request survives independently in each channel.
reset()
do {
  let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  c.player.setVideoRotate(90)
  c.player.setVideoAspect("4:3");c.player.setVideoRotate(180)
  c.player.setVideoAspect("16:9");c.player.setVideoRotate(270)
  check(c.player.mpv.writes.count==1,"queued mixed requests do not mutate engine during current preparation")
  complete(c)
  check(c.player.mpv.writes.map{$0.0+"="+$0.1}==["video-rotate=90","video-aspect-override=16:9","video-rotate=270"],"latest aspect and rotation both survive coalescing")
  check(ClockTrace.policies.count==3,"each coalesced ordinary request uses the common visual clock")
  check(c.player.osdBegins.count==3 && c.player.osdEnds.count==3,"queued motions release each matching refresh scope")
}

// Failed apply, failed native frame, cancellation, stale callback and new media.
reset()
do {
  let c=MainWindowController();c.player.mpv.failNext=true;c.player.setVideoRotate(90)
  check(!c.motionExists && ClockTrace.policies.isEmpty && c.videoView.videoLayer.callbacks.isEmpty,"failed property write releases preparation without animation")
  check(!c.videoView.videoLayer.isPreparingCropFrame && c.player.osdEnds.count==1,"failed write releases native and OSD ownership")
}
for staleMedia in [false,true] {
  reset();let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  c.player.setVideoRotate(90);c.publishOutput();let old=c.videoView.videoLayer.callbacks[0]
  c.player.setVideoAspect("4:3")
  if staleMedia {c.player.info.trackSelectionGeneration+=1;old(true)}else{old(false)}
  check(!c.motionExists && ClockTrace.policies.isEmpty,"failed/stale native callback cannot begin motion")
  check(c.player.mpv.writes.count==1,"failed/stale native callback discards queued work instead of writing into another generation")
}
reset()
do {
  let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  c.player.setVideoRotate(90);c.publishOutput();let stale=c.videoView.videoLayer.callbacks[0]
  c.cancelVideoGeometryTransition(settleWindowFrame:false)
  c.player.setVideoRotate(180);c.publishOutput()
  let expected=c.expected
  stale(true)
  check(c.motionExists && c.expected?.0==expected?.0 && !c.animating,"cancelled callback cannot acquire or finish replacement owner")
  c.videoView.videoLayer.callbacks.last?(true)
  check(c.animating,"replacement request retains its own native continuation")
  if let oldClock=ClockTrace.advances.last {
    c.cancelVideoGeometryTransition(settleWindowFrame:false)
    let handoffs=c.videoView.videoLayer.handoffs.count;oldClock(1)
    check(c.videoView.videoLayer.handoffs.count==handoffs,"cancelled clock cannot publish an obsolete final handoff")
  }else{check(false,"replacement request exposes a clock to test cancellation")}
}
reset()
do {
  let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  c.player.setVideoRotate(90);c.player.info.state = .stopped;c.geometryVideoOutputDidChange()
  check(!c.motionExists && c.parameterUpdates==0,"stopped media cannot update window-scale bookkeeping")
}

// Reduced/disabled motion uses the same canonical option and metadata path,
// while unlocked sizing retains its manually selected outer frame.
for mode in ["disabled","reduced","fullscreen","pip","unlocked"] {
  reset();let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  let frame=c.window!.frame
  if mode=="disabled" {Preference.animationsDisabled=true}
  if mode=="reduced" {AccessibilityPreferences.motionReductionEnabled=true}
  if mode=="fullscreen" {c.fsState = .fullscreen}
  if mode=="pip" {c.pipStatus = .inPIP}
  if mode=="unlocked" {Preference.unlockWindowAspectRatio=true}
  c.player.setVideoRotate(90);c.publishOutput()
  if mode=="unlocked" {
    check(c.targetFrame==frame,"unlocked geometry retains its manually selected frame")
    c.videoView.videoLayer.callbacks.last?(true);ClockTrace.advances.last?(0.5)
    check(near(c.window!.frame,frame),"unlocked image motion does not resize the outer window")
    ClockTrace.advances.last?(1)
  }else{
    check(c.motionOverlay==nil && ClockTrace.policies.isEmpty,"\(mode) bypasses visual owner/clock")
    check(c.videoView.videoLayer.callbacks.isEmpty && !c.motionExists,"\(mode) does not wait for a visual native continuation")
  }
  check(c.player.mpv.writes.count==1,"\(mode) commits the canonical engine option exactly once")
}

// Test the exact last delivery guards separately from OSD drawing, together
// with real PlayerCore seek-intent/token methods. Internal refresh SEEK stays
// suppressed; a deliberate user seek and pause survive an active geometry owner.
reset()
do {
  let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  check(c.canDeliverOSD(.seek),"normal final OSD delivery remains enabled")
  c.cropExitOverlay=CropTransitionOverlay(frame:c.videoViewContainer.bounds)
  check(!c.canDeliverOSD(.seek) && !c.canDeliverOSD(.pause),"existing Crop-specific final delivery suppression survives")
  c.cropExitOverlay=nil;c.interactiveMode.isEntering=true
  check(!c.canDeliverOSD(.seek),"editor entry retains existing final OSD suppression")
  c.interactiveMode.isEntering=false;c.player.setVideoRotate(90)
  let intent=GeometrySeekFixture(),token=intent.beginVideoGeometryOSDRefresh()
  check(!intent.shouldShowSeekOSD,"geometry refresh rejects unsolicited seek OSD at the source")
  intent.userInitiatedSeek()
  check(intent.shouldShowSeekOSD && c.canDeliverOSD(.seek),"deliberate seek passes source intent and final geometry delivery guards")
  check(c.canDeliverOSD(.pause) && c.canDeliverOSD(.aspect) && c.canDeliverOSD(.rotate),"pause and setting feedback remain deliverable during geometry motion")
  intent.seekOSDDidStart();intent.seekOSDDidRestart()
  check(!intent.shouldShowSeekOSD,"completed deliberate seek cannot authorize a later internal refresh seek")
  intent.endVideoGeometryOSDRefresh(UUID())
  check(intent.mpv.pendingEvents.isEmpty,"unrelated OSD scope token cannot release current ownership")
  intent.endVideoGeometryOSDRefresh(token)
  check(intent.mpv.pendingEvents.count==1,"OSD scope release waits for preceding engine events")
  intent.mpv.drainPendingEvents()
  check(!intent.shouldShowSeekOSD,"drained refresh scope leaves unsolicited seek feedback suppressed")
  intent.userInitiatedSeek()
  check(intent.shouldShowSeekOSD,"a fresh deliberate seek remains visible after refresh drain")
  c.isShowingPersistentOSD=true
  check(!c.canDeliverOSD(.seek),"geometry exception does not bypass persistent OSD ownership")
  c.isShowingPersistentOSD=false;c.player.displayOSD=false
  check(!c.canDeliverOSD(.pause),"geometry exception does not bypass normal OSD preference")
}

// Decoder metadata may lag a committed option. Requested readiness derives from
// the option and old output, and must not accept or animate that old frame.
for change in ["aspect","180","embedded90-user-delta"] {
  reset();let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  if change=="embedded90-user-delta" {
    c.player.mpv.sourceRotation=90;c.player.mpv.values["video-rotate"]=90
    c.player.mpv.updateDecoder();c.player.mpv.publishOutput()
  }
  let oldDecoderRotation=c.player.mpv.getInt("video-params/rotate"),oldDecoderPAR=c.player.mpv.getDouble("video-params/par")
  c.player.mpv.synchronizeDecoder=false
  if change=="aspect" {c.requestedTarget=NSRect(x:200,y:80,width:600,height:450);c.player.setVideoAspect("4:3")}
  else{c.player.setVideoRotate(change=="180" ? 180 : 270)}
  let expectedRotation=change=="180" ? 180 : 0,expectedPAR=change=="aspect" ? 0.75 : 1.0
  check(c.expected?.0==expectedRotation && abs((c.expected?.1 ?? 0)-expectedPAR)<0.000001,"delayed decoder \(change) derives requested signature from committed options")
  c.geometryVideoOutputDidChange()
  check(!c.waiting && c.sizingCalls==0 && c.videoView.videoLayer.callbacks.isEmpty,"delayed decoder \(change) retains source while old output is still published")
  check(c.player.mpv.getInt("video-params/rotate")==oldDecoderRotation && c.player.mpv.getDouble("video-params/par")==oldDecoderPAR,"delayed decoder \(change) fixture leaves decoder signature old")
  c.player.mpv.publishOutput(effectiveRotation:expectedRotation,pixelAspect:expectedPAR);c.geometryVideoOutputDidChange()
  check(c.waiting && c.videoView.videoLayer.callbacks.count==1,"delayed decoder \(change) accepts new output independently of stale decoder metadata")
  c.videoView.videoLayer.callbacks.first?(true)
  check(c.animating,"delayed decoder \(change) begins only after new output's native frame")
  if change=="aspect" {check(near(c.videoView.bounds.width/c.videoView.bounds.height,4/3),"first4:3 transition allocates the new4:3 native raster")}
  ClockTrace.advances.last?(1)
  check(!c.motionExists,"delayed decoder \(change) releases motion ownership")
}

// Default restores the selected track's nonsquare container PAR, independent of
// an old override and decoder signature. Other tracks cannot supply that value.
reset()
do {
  let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  c.player.info.vid=7;c.player.info.videoTracks=[.init(id:1,demuxPixelAspect:64/45),.init(id:7,demuxPixelAspect:16/15)]
  c.player.mpv.defaultAspect=4/3;c.player.mpv.values["video-dec-params/par"]=1.2
  c.player.mpv.values["video-params/w"]=720;c.player.mpv.values["video-params/h"]=576
  _=c.player.mpv.setString("video-aspect-override","16:9");c.player.mpv.publishOutput();c.player.mpv.writes=[]
  let oldDecoderPAR=c.player.mpv.getDouble("video-params/par")
  c.player.mpv.synchronizeDecoder=false;c.player.setVideoAspect("Default")
  check(abs(c.player.defaultVideoPixelAspect-16/15)<0.000001,"Default selects current track's finite positive container PAR before decoder fallback")
  check(abs((c.expected?.1 ?? 0)-16/15)<0.000001 && !c.waiting,"Default nonsquare PAR cannot accept old16:9 output")
  c.player.mpv.publishOutput(effectiveRotation:0,pixelAspect:16/15);c.geometryVideoOutputDidChange()
  check(c.waiting && c.player.mpv.getDouble("video-params/par")==oldDecoderPAR,"Default new container PAR releases readiness despite stale decoder override")
  c.videoView.videoLayer.callbacks.first?(true)
  check(c.animating && near(c.videoView.bounds.width/c.videoView.bounds.height,4/3),"Default nonsquare native raster uses restored display aspect")
  ClockTrace.advances.last?(1)
  check(!c.motionExists && c.player.mpv.writes.count==1,"Default nonsquare reset completes with one canonical option write")
}
for (container,decoded,expected) in [(nil,1.2,1.2),(Double.nan,1.1,1.1),(0.0,1.3,1.3),(-1.0,Double.infinity,1.0),(Double.infinity,Double.nan,1.0)] as [(Double?,Double,Double)] {
  let p=PlayerFixture();p.info.videoTracks=[.init(id:1,demuxPixelAspect:container)];p.mpv.values["video-dec-params/par"]=decoded
  check(abs(p.defaultVideoPixelAspect-expected)<0.000001,"Default PAR rejects absent/invalid container or decoder values and falls back safely")
}
do {
  let p=PlayerFixture();p.info.vid=7
  p.mpv.nodes["track-list"]=[["type":"audio","id":7,"demux-rotation":270],["type":"video","id":8,"demux-rotation":180],["type":"video","id":7,"demux-rotation":90]] as [[String:Any]]
  check(p.defaultVideoRotation==90,"raw file rotation fallback selects current video id and ignores matching audio/other video")
  p.mpv.values["video-dec-params/rotate"]=270
  check(p.defaultVideoRotation==270,"nonzero raw decoder rotation precedes track-list fallback")
  p.mpv.values["video-dec-params/rotate"]=0;p.mpv.nodes["track-list"]="unavailable"
  check(p.defaultVideoRotation==0,"missing track-list node safely supplies zero file rotation")
  p.mpv.nodes["track-list"]=[["type":"video","id":8,"demux-rotation":180],["type":"video","id":7]] as [[String:Any]]
  check(p.defaultVideoRotation==0,"selected video without rotation does not borrow another track's rotation")
}

for change in ["aspect","rotation"] {
  reset();let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  for prefix in ["video-params","video-out-params"] {for key in ["w","h","dw","dh"] {c.player.mpv.values[prefix+"/"+key]=0}}
  c.player.mpv.synchronizeDecoder=false
  if change=="aspect" {c.player.setVideoAspect("4:3")}else{c.player.setVideoRotate(90)}
  check(!c.motionExists && c.player.osdBegins.isEmpty && c.videoView.videoLayer.callbacks.isEmpty,"audio-only \(change) creates no readiness/OSD scope")
  check(c.player.mpv.writes.count==1 && c.sizingCalls==0,"audio-only \(change) applies canonical option directly without window sizing")
}

// Paused refresh can publish PLAYBACK_RESTART before geometry metadata reaches
// main, or after a prepared-frame waiter has missed the already-consumed frame.
reset()
do {
  let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  c.player.info.state = .paused;c.player.mpv.synchronizeDecoder=false;c.player.setVideoAspect("4:3")
  c.player.playbackRestarted()
  check(c.motionExists && !c.waiting && !c.animating,"early restart caches frame readiness without accepting stale aspect metadata")
  check(c.player.nativeRequests==0 && c.videoView.videoLayer.callbacks.isEmpty,"early restart requires no additional native frame while metadata mismatches")
  c.player.mpv.publishOutput(effectiveRotation:0,pixelAspect:0.75);c.geometryVideoOutputDidChange()
  check(c.animating && ClockTrace.policies.count==1,"new metadata consumes the cached paused restart and starts motion")
  check(c.player.nativeRequests==0 && c.videoView.videoLayer.callbacks.isEmpty,"cached current frame bypasses redundant native request and waiter")
  let handoffs=c.videoView.videoLayer.handoffs.count
  c.player.playbackRestarted()
  check(ClockTrace.policies.count==1 && c.videoView.videoLayer.handoffs.count==handoffs,"repeated restart during motion cannot publish a second initial handoff")
  ClockTrace.advances.last?(1)
  let settled=c.videoView.videoLayer.handoffs.count
  c.player.playbackRestarted()
  check(!c.motionExists && ClockTrace.policies.count==1 && c.videoView.videoLayer.handoffs.count==settled,"restart after completion cannot revive the completed owner")
  check(c.player.mpv.writes.count==1 && c.player.mpv.commands.isEmpty && c.player.nativeRequests==0,"early cached restart adds no engine mutation, seek or native-frame request")
}
reset()
do {
  let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  c.player.info.state = .paused;c.player.setVideoRotate(90);c.publishOutput()
  check(c.waiting && !c.animating && c.player.nativeRequests==1 && c.videoView.videoLayer.callbacks.count==1,"late restart begins from one existing prepared-frame waiter")
  let consumed=c.videoView.videoLayer.callbacks.first
  c.player.playbackRestarted()
  check(c.animating && ClockTrace.policies.count==1,"late paused restart supplies the current frame if the waiter missed it")
  let handoffs=c.videoView.videoLayer.handoffs.count
  consumed?(true);consumed?(false);c.player.playbackRestarted()
  check(c.animating && ClockTrace.policies.count==1 && c.videoView.videoLayer.handoffs.count==handoffs,"consumed waiter and repeated restart cannot publish twice or cancel active motion")
  check(c.player.nativeRequests==1 && c.player.mpv.writes.count==1 && c.player.mpv.commands.isEmpty,"late restart reuses its one native request without seek or extra engine write")
  ClockTrace.advances.last?(1)
  check(!c.motionExists && c.videoView.idleCalls==1,"paused restart completion settles once and returns the native video to idle")
}
reset()
do {
  let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  c.player.info.state = .paused;c.player.setVideoRotate(90);c.publishOutput()
  let stale=c.videoView.videoLayer.callbacks.first
  c.cancelVideoGeometryTransition(settleWindowFrame:false)
  let cancelledHandoffs=c.videoView.videoLayer.handoffs.count
  c.player.playbackRestarted();stale?(true)
  check(!c.motionExists && c.videoView.videoLayer.handoffs.count==cancelledHandoffs,"restart and native callback cannot resurrect a cancelled owner")
  c.player.setVideoRotate(180);c.publishOutput()
  stale?(false)
  check(c.waiting && !c.animating,"cancelled frame callback cannot consume replacement ownership")
  c.player.playbackRestarted()
  check(c.animating && ClockTrace.policies.count==1,"replacement motion owns its later paused restart")
  ClockTrace.advances.last?(1)
  check(!c.motionExists && c.player.nativeRequests==2 && c.player.mpv.commands.isEmpty,"cancel/restart replacement consumes one request per owner without seeking")
}
reset()
do {
  let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  c.player.info.state = .paused;c.player.setVideoRotate(90);c.publishOutput()
  let stale=c.videoView.videoLayer.callbacks.first
  c.player.setVideoAspect("4:3");c.player.info.trackSelectionGeneration+=1
  c.player.playbackRestarted();stale?(true)
  check(!c.motionExists && ClockTrace.policies.isEmpty && c.player.mpv.writes.count==1,"new media restart cancels old native waiter and discards pending requests")
}

// A cancelled request may already have committed its user option while the old
// output is still visible. Derive the new request from raw file metadata rather
// than applying an option delta to that obsolete output. Cached readiness stays
// with the cancelled owner.
for embedded in [0,90] {
  for oldOption in [0,90] {
    reset();let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
    c.player.info.state = .paused;c.player.mpv.sourceRotation=embedded;c.player.mpv.values["video-rotate"]=Double(oldOption)
    if embedded==90 {
      c.player.info.vid=7;c.player.mpv.values["video-dec-params/rotate"]=0
      c.player.mpv.nodes["track-list"]=[["type":"video","id":7,"demux-rotation":embedded]] as [[String:Any]]
    }
    c.player.mpv.updateDecoder();c.player.mpv.publishOutput();c.player.mpv.synchronizeDecoder=false
    c.player.setVideoRotate((oldOption+90)%360);c.player.playbackRestarted()
    check(!c.waiting && !c.animating,"cancel-before-output file\(embedded)/user\(oldOption) retains stale current frame")
    c.cancelVideoGeometryTransition(settleWindowFrame:false)
    let next=(oldOption+180)%360,effective=(embedded+next)%360
    c.player.setVideoRotate(next)
    check(c.expected?.0==effective,"replacement file\(embedded)/user\(oldOption) uses raw file rotation plus committed option")
    c.player.mpv.publishOutput(effectiveRotation:effective,pixelAspect:1);c.geometryVideoOutputDidChange()
    check(c.waiting && !c.animating && c.player.nativeRequests==1,"replacement file\(embedded)/user\(oldOption) cannot inherit cancelled cached readiness")
    c.player.playbackRestarted()
    check(c.animating && ClockTrace.policies.count==1,"replacement file\(embedded)/user\(oldOption) accepts its own current-frame restart")
    ClockTrace.advances.last?(1)
    check(!c.motionExists && c.player.mpv.writes.count==2 && c.player.mpv.commands.isEmpty,"replacement file\(embedded)/user\(oldOption) completes without extra mutation or seek")
  }
}

for first in ["aspect","rotation"] {
  for embedded in [0,90] {
    reset();let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
    c.player.info.state = .paused;c.player.mpv.sourceRotation=embedded
    c.player.mpv.updateDecoder();c.player.mpv.publishOutput();c.player.mpv.synchronizeDecoder=false
    if first=="aspect" {c.player.setVideoAspect("4:3")}else{c.player.setVideoRotate(90)}
    c.player.playbackRestarted();c.cancelVideoGeometryTransition(settleWindowFrame:false)
    if first=="aspect" {c.player.setVideoRotate(90)}else{c.player.setVideoAspect("4:3")}
    let effective=(embedded+90)%360
    check(c.expected?.0==effective && abs((c.expected?.1 ?? 0)-0.75)<0.000001,"cancelled \(first)/file\(embedded) replacement derives both channels from committed options")
    check(!c.waiting && !c.animating,"cancelled \(first)/file\(embedded) replacement cannot accept stale output from the other channel")
    c.player.mpv.publishOutput(effectiveRotation:effective,pixelAspect:0.75);c.geometryVideoOutputDidChange()
    check(c.waiting && !c.animating && c.player.nativeRequests==1,"cancelled \(first)/file\(embedded) replacement registers its own new-output waiter")
    c.player.playbackRestarted()
    let display=c.player.interactiveVideoGeometry(uncropped:false).displaySize
    check(c.animating && near(c.videoView.bounds.width/c.videoView.bounds.height,display.width/display.height),"cancelled \(first)/file\(embedded) replacement allocates combined current aspect/rotation raster")
    ClockTrace.advances.last?(1)
    check(!c.motionExists && c.player.mpv.writes.count==2 && c.player.mpv.commands.isEmpty,"cancelled \(first)/file\(embedded) replacement settles both committed channels without seeking")
  }
}

reset()
do {
  let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  c.player.setVideoRotate(90);c.publishOutput();c.videoView.videoLayer.callbacks.first?(true)
  ClockTrace.advances.last?(0.4)
  let intermediate=c.window!.frame,obsoleteClock=ClockTrace.advances.last
  c.player.setVideoAspect("4:3")
  c.beginWindowSizePinchForTesting(.init(state:.began,magnification:0.125))
  check(!c.motionExists && near(c.window!.frame,intermediate),"pinch began cancels geometry without snapping to its target endpoint")
  check(c.frameWhenStartedPinching==intermediate && c.lastMagnification==0.125 && c.videoView.videoLayer.inLiveResize,"pinch captures its manual start frame after cancellation")
  obsoleteClock?(1)
  check(near(c.window!.frame,intermediate) && c.player.mpv.writes.count==1,"pinch cancellation discards queued geometry and prevents stale clock frame publication")
}

// Observe the real tick/watchdog closures while the actual native display link
// is paused. Synthetic target timestamps control refresh delivery, not progress
// or completion logic; no physical/visible window is required.
if #available(macOS 14.0, *), NSScreen.main != nil {
  let window=MotionWindow(contentRect:NSRect(x:0,y:0,width:200,height:120),styleMask:[.borderless],backing:.buffered,defer:false)
  window.isReleasedWhenClosed=false;window.usesClockScreenForTesting=true
  let content=NSView(frame:NSRect(x:0,y:0,width:200,height:120));window.contentView=content
  let clock=CropTransitionOverlay(frame:content.bounds);content.addSubview(clock)
  defer{clock.stopAnimation();clock.removeFromSuperview()}

  reset();var progress:[CGFloat]=[],completions=0
  let scheduled=CACurrentMediaTime()
  clock.animate(duration:0.4,curve:.smoothstep,startOnFirstTick:true,update:{progress.append($0)}){completions+=1}
  check(window.displayLinkRequests==1 && ClockTrace.watchdogs.count==1,"first-tick clock creates one native driver and completion watchdog")
  let tick=ClockTrace.ticks.last!,watchdog=ClockTrace.watchdogs.last!
  watchdog.fire()
  check(progress.isEmpty && completions==0 && watchdog.isValid,"visible first-tick clock watchdog preserves motion before any refresh callback")
  let first=scheduled+0.6
  tick(first)
  check(progress==[0] && completions==0,"first target timestamp delayed600ms begins at exact zero progress")
  watchdog.fire()
  check(progress==[0] && completions==0,"watchdog cannot consume movement time immediately after the first target timestamp")
  tick(first+0.1);check(near(progress.last ?? -1,0.15625) && completions==0,"100ms after late first refresh follows smoothstep from the refresh origin")
  tick(first+0.2);check(near(progress.last ?? -1,0.5) && completions==0,"200ms after late first refresh reaches the middle of400ms movement")
  tick(first+0.399);check((progress.last ?? 1)<1 && completions==0,"late first refresh preserves the whole400ms movement before completion")
  tick(first+0.4001)
  check(progress.last==1 && completions==1 && !watchdog.isValid,"late first refresh completes once after its full400ms and invalidates watchdog")
  let completedCount=progress.count;tick(first+1);watchdog.fire()
  check(progress.count==completedCount && completions==1,"late tick/watchdog cannot revive a completed generation")

  for visibility in ["hidden","occluded"] {
    reset();progress=[];completions=0;window.visibleForTesting=true;window.occludedForTesting=false
    clock.animate(duration:0.4,startOnFirstTick:true,update:{progress.append($0)}){completions+=1}
    if visibility=="hidden" {window.visibleForTesting=false}else{window.occludedForTesting=true}
    ClockTrace.watchdogs.last?.fire()
    check(progress==[1] && completions==1,"\(visibility) first-tick clock can finish without a refresh callback")
  }

  reset();progress=[];completions=0;window.visibleForTesting=true;window.occludedForTesting=false
  clock.animate(duration:0.4,update:{progress.append($0)}){completions+=1}
  check(ClockTrace.policies.last?.2==false,"omitted first-tick argument preserves legacy Crop clock policy")
  ClockTrace.ticks.last?(CACurrentMediaTime()+0.6)
  check(progress==[1] && completions==1,"legacy default clock still includes elapsed preparation time at its first late tick")

  reset();progress=[];completions=0
  clock.animate(duration:0.4,update:{progress.append($0)}){completions+=1}
  ClockTrace.watchdogs.last?.fire()
  check(progress==[1] && completions==1,"legacy default watchdog still completes even if visible before its first tick")

  reset();progress=[];completions=0
  clock.animate(duration:0.4,startOnFirstTick:true,update:{progress.append($0)}){completions+=1}
  let cancelledTick=ClockTrace.ticks.last!,cancelledWatchdog=ClockTrace.watchdogs.last!
  clock.stopAnimation();cancelledTick(CACurrentMediaTime()+0.6);cancelledWatchdog.fire()
  check(progress.isEmpty && completions==0 && !cancelledWatchdog.isValid,"cancelling before first tick invalidates both opt-in clock paths")

  reset();progress=[];completions=0
  clock.animate(duration:0,startOnFirstTick:true,update:{progress.append($0)}){completions+=1}
  check(progress==[1] && completions==1 && ClockTrace.watchdogs.isEmpty,"zero-duration opt-in still publishes its endpoint immediately")
}else{print("SKIP: native display-link clock checks require macOS14 and a screen")}

// Exercise the real400ms fallback timer/watchdog once without manual advance.
reset()
do {
  let c=MainWindowController();defer{c.cancelVideoGeometryTransition()}
  c.player.setVideoRotate(90);c.publishOutput();c.videoView.videoLayer.callbacks[0](true)
  let start=CACurrentMediaTime(),deadline=Date().addingTimeInterval(1)
  while c.motionExists && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.002))}
  check(!c.motionExists && CACurrentMediaTime()-start>=0.35,"real shared clock finishes from its timer without a visible window")
}
print("Completed \(checks) extracted-production geometry motion checks; failures=\(failures.count)")
if !failures.isEmpty {exit(1)}
