import Cocoa

// PRODUCTION_GEOMETRY

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message)
  checks += 1
}
func near(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 0.000001) -> Bool { abs(a-b) < tolerance }
func near(_ a: NSPoint, _ b: NSPoint) -> Bool { near(a.x,b.x) && near(a.y,b.y) }
func near(_ a: NSRect, _ b: NSRect) -> Bool {
  near(a.minX,b.minX) && near(a.minY,b.minY) && near(a.width,b.width) && near(a.height,b.height)
}
func points(_ rect: NSRect) -> [NSPoint] {
  [NSPoint(x:rect.minX,y:rect.minY),NSPoint(x:rect.maxX,y:rect.minY),
   NSPoint(x:rect.maxX,y:rect.maxY),NSPoint(x:rect.minX,y:rect.maxY)]
}
func project(_ point: NSPoint, through layer: CALayer) -> NSPoint {
  let local = NSPoint(x:point.x-layer.bounds.minX-layer.bounds.width*layer.anchorPoint.x,
                      y:point.y-layer.bounds.minY-layer.bounds.height*layer.anchorPoint.y)
  let t=layer.transform
  return NSPoint(x:layer.position.x+local.x*t.m11+local.y*t.m21+t.m41,
                 y:layer.position.y+local.x*t.m12+local.y*t.m22+t.m42)
}
func pathPoints(_ path: CGPath) -> [NSPoint] {
  var result: [NSPoint] = []
  path.applyWithBlock { item in
    if item.pointee.type == .moveToPoint || item.pointee.type == .addLineToPoint {
      result.append(item.pointee.points[0])
    }
  }
  return result
}
func expectedQuarter(_ point: NSPoint, bounds: NSRect, frame: NSRect, degrees: Int) -> NSPoint {
  let x=(point.x-bounds.midX)*frame.width/bounds.width
  let y=(point.y-bounds.midY)*frame.height/bounds.height
  let offset: NSPoint
  switch degrees {
  case 90: offset=NSPoint(x:-y,y:x)
  case 180: offset=NSPoint(x:-x,y:-y)
  case 270: offset=NSPoint(x:y,y:-x)
  default: offset=NSPoint(x:x,y:y)
  }
  return NSPoint(x:frame.midX+offset.x,y:frame.midY+offset.y)
}
func context() -> (NSView,NSView,CALayer) {
  let container=NSView(frame:NSRect(x:0,y:0,width:800,height:450));container.wantsLayer=true
  let native=NSView(frame:NSRect(x:30,y:50,width:320,height:180));native.wantsLayer=true
  container.addSubview(native)
  let layer=native.layer!;layer.contentsScale=2;layer.contentsFormat = .RGBA16Float
  return (container,native,layer)
}

for from in [0,90,180,270] {
  for to in [0,90,180,270] {
    let delta=VideoGeometryTransition.shortestQuarterTurnDelta(from:from,to:to)
    check(abs(delta)<=180 && delta%90==0,"quarter-turn delta is bounded")
    check(((from+delta)%360+360)%360==to,"shortest delta reaches requested orientation")
  }
}
check(VideoGeometryTransition.shortestQuarterTurnDelta(from:270,to:0)==90,"270→0 takes clockwise quarter turn")
check(VideoGeometryTransition.shortestQuarterTurnDelta(from:0,to:270)==(-90),"0→270 takes counterclockwise quarter turn")
check(VideoGeometryTransition.shortestQuarterTurnDelta(from:0,to:180)==180,"180 tie keeps clockwise intent")
check(VideoGeometryTransition.shortestQuarterTurnDelta(from:450,to:-90)==180,"full-turn aliases normalize")

let old=NSRect(x:110,y:70,width:640,height:360)
for degree in [0,90,180,270,-90,-180] {
  let start=VideoGeometryTransition.startFrame(oldVisibleRect:old,quarterTurnDelta:degree)
  check(near(start.midX,old.midX) && near(start.midY,old.midY),"start raster keeps old image center")
  check(near(start.width,abs(degree/90)%2==1 ? old.height : old.width),"odd quarter turns swap raster width")
  check(near(start.height,abs(degree/90)%2==1 ? old.width : old.height),"odd quarter turns swap raster height")
  let radians=CGFloat(degree) * .pi/180
  let extent=NSSize(width:abs(cos(radians))*start.width+abs(sin(radians))*start.height,
                    height:abs(sin(radians))*start.width+abs(cos(radians))*start.height)
  check(near(extent.width,old.width) && near(extent.height,old.height),"compensated raster reproduces old visible rectangle")
}

// Exercise the actual layer mapping with asymmetric labelled corners and an
// interior marker; expected quarter-turn mappings are specified independently.
for anchor in [NSPoint(x:0,y:0),NSPoint(x:0.2,y:0.8),NSPoint(x:0.5,y:0.5),NSPoint(x:1,y:1)] {
  let (container,native,layer)=context();layer.anchorPoint=anchor
  let owner=NativeCropVideoPresentation(view:native,container:container,pixelSize:NSSize(width:3840,height:2160))
  let initial=NSRect(x:30,y:50,width:320,height:180)
  owner.present(frame:initial,clip:container.bounds)
  let raster=layer.bounds,position=layer.position
  let frame=NSRect(x:210,y:95,width:470,height:230)
  for degree in [0,90,180,270] {
    owner.present(frame:frame,clip:NSRect(x:240,y:100,width:170,height:130),rotation:CGFloat(degree) * .pi/180)
    check(layer.anchorPoint==anchor && layer.position==position,"presentation preserves noncentral anchor and position")
    // Nonzero angles have the new center contract. Zero keeps the legacy
    // AppKit-origin-anchor mapping, verified separately below.
    for marker in (degree != 0 || anchor == .zero) ? points(raster)+[NSPoint(x:raster.minX+37,y:raster.minY+19)] : [] {
      check(near(project(marker,through:layer),expectedQuarter(marker,bounds:raster,frame:frame,degrees:degree)),
            "labelled corner/interior marker follows centered quarter rotation: angle=\(degree), anchor=\(anchor), marker=\(marker), actual=\(project(marker,through:layer)), expected=\(expectedQuarter(marker,bounds:raster,frame:frame,degrees:degree)), position=\(layer.position), bounds=\(layer.bounds)")
    }
    check(layer.bounds==raster && native.layer===layer,"rotation keeps one native layer and fixed raster")
    if degree != 0 {
      let mask=layer.mask as! CAShapeLayer
      let mapped=pathPoints(mask.path!).map { project($0,through:layer) }
      check(mapped.count==4,"rotation clip has four inverse-mapped corners")
      for (actual,expected) in zip(mapped,points(NSRect(x:240,y:100,width:170,height:130))) {
        check(near(actual,expected),"full affine inverse returns each clip corner to container coordinates")
      }
    }
  }
  owner.restore()
}

// Arbitrary angles and nonuniform scale must preserve the clip mapping too.
for angle: CGFloat in [-2.7,-0.45,0.6,2.2] {
  let (container,native,layer)=context();layer.anchorPoint=NSPoint(x:0.13,y:0.71)
  let owner=NativeCropVideoPresentation(view:native,container:container,pixelSize:NSSize(width:3840,height:2160))
  owner.present(frame:NSRect(x:30,y:50,width:320,height:180),clip:container.bounds)
  let clip=NSRect(x:145,y:102,width:237,height:119), frame=NSRect(x:80,y:170,width:510,height:97)
  owner.present(frame:frame,clip:clip,rotation:angle)
  check(near(project(NSPoint(x:layer.bounds.midX,y:layer.bounds.midY),through:layer),NSPoint(x:frame.midX,y:frame.midY)),"arbitrary rotation pivots around image center")
  let mapped=pathPoints((layer.mask as! CAShapeLayer).path!).map { project($0,through:layer) }
  for (actual,expected) in zip(mapped,points(clip)) { check(near(actual,expected),"nonuniform rotated clip inverse is exact") }
  owner.restore()
}

// Legacy crop expectations: default and explicit zero keep the rectangular
// mask and the original transform/aperture formulas for every sampled frame.
let (cropContainer,cropNative,cropLayer)=context()
let crop=NativeCropVideoPresentation(view:cropNative,container:cropContainer,pixelSize:NSSize(width:3840,height:2160))
let base=NSRect(x:-35,y:42,width:640,height:360)
crop.present(frame:base,clip:cropContainer.bounds)
let oldAperture=cropLayer.mask!
for step in 0...100 {
  let p=CGFloat(step)/100
  let frame=NSRect(x:-35+p*50,y:42-p*60,width:640-p*370,height:360+p*95)
  let clip=NSRect(x:10+p*15,y:20+p*30,width:220+p*90,height:170-p*40)
  if step.isMultiple(of:2) { crop.present(frame:frame,clip:clip) }
  else { crop.present(frame:frame,clip:clip,rotation:0) }
  let sx=frame.width/base.width,sy=frame.height/base.height
  var expected=CATransform3DMakeScale(sx,sy,1)
  expected.m41=frame.minX-base.minX+(frame.width-base.width)*cropLayer.anchorPoint.x
  expected.m42=frame.minY-base.minY+(frame.height-base.height)*cropLayer.anchorPoint.y
  let mask=NSRect(x:(clip.minX-frame.minX)/sx,y:(clip.minY-frame.minY)/sy,width:clip.width/sx,height:clip.height/sy).intersection(cropNative.bounds)
  check(CATransform3DEqualToTransform(cropLayer.transform,expected),"zero rotation retains exact original crop transform")
  check(cropLayer.mask===oldAperture && !(cropLayer.mask is CAShapeLayer) && near(cropLayer.mask!.frame,mask),"zero rotation retains exact original rectangular crop mask: step=\(step), actual=\(cropLayer.mask!.frame), expected=\(mask), identity=\(cropLayer.mask===oldAperture), shape=\(cropLayer.mask is CAShapeLayer)")
}
crop.restore()

// Animate each relative turn through changing minimum/portrait viewports.
// The helper receives eased progress; it must never collapse at a180 midpoint.
for delta in [-180,-90,0,90,180] {
  for finalViewport in [NSRect(x:0,y:0,width:400,height:225),NSRect(x:0,y:0,width:400,height:711),NSRect(x:17,y:29,width:225,height:400)] {
    let startViewport=NSRect(x:0,y:0,width:800,height:450)
    let initialFrame=VideoGeometryTransition.startFrame(oldVisibleRect:startViewport,quarterTurnDelta:delta)
    let targetAspect: CGFloat=abs(delta/90)%2==1 ? 9/16 : 16/9
    let targetSize=NSSize(width:targetAspect,height:1)
    let fit=min(finalViewport.width/targetSize.width,finalViewport.height/targetSize.height)
    let target=NSRect(x:finalViewport.midX-targetSize.width*fit/2,y:finalViewport.midY-fit/2,width:targetSize.width*fit,height:fit)
    for tick in 0...100 {
      let u=CGFloat(tick)/100,p=u*u*(3-2*u)
      let viewport=NSRect(x:startViewport.minX+(finalViewport.minX-startViewport.minX)*p,
                          y:startViewport.minY+(finalViewport.minY-startViewport.minY)*p,
                          width:startViewport.width+(finalViewport.width-startViewport.width)*p,
                          height:startViewport.height+(finalViewport.height-startViewport.height)*p)
      let sample=VideoGeometryTransition.sample(from:initialFrame,to:target,viewport:viewport,progress:p,initialRotation:CGFloat(delta) * .pi/180)
      check(sample.frame.width>0 && sample.frame.height>0,"intermediate rotation has positive area including180 midpoint")
      check(near(sample.rotation,CGFloat(delta) * .pi/180*(1-p)),"rotation follows caller's shared eased progress")
      let c=cos(sample.rotation),s=sin(sample.rotation)
      for point in points(sample.frame) {
        let x=point.x-sample.frame.midX,y=point.y-sample.frame.midY
        let rotated=NSPoint(x:sample.frame.midX+c*x-s*y,y:sample.frame.midY+s*x+c*y)
        check(rotated.x>=viewport.minX-0.000001 && rotated.x<=viewport.maxX+0.000001 && rotated.y>=viewport.minY-0.000001 && rotated.y<=viewport.maxY+0.000001,"complete rotated quad fits current viewport")
      }
      if tick==0 { check(near(sample.frame,initialFrame),"start compensation keeps exact endpoint") }
      if tick==100 { check(near(sample.frame,target) && sample.rotation==0,"completion reaches exact canonical fit and zero rotation") }
    }
  }
}

// Restore from either aperture kind, and never overwrite a canonical mask
// installed by a newer handoff while this presentation is being cancelled.
for endRotated in [false,true] {
  let (container,native,layer)=context()
  let original=CALayer();layer.mask=original;let originalTransform=CATransform3DIdentity;layer.transform=originalTransform
  var acquired=0,restored=0
  let owner=NativeCropVideoPresentation(view:native,container:container,pixelSize:NSSize(width:3840,height:2160),beginLayout:{acquired+=1},restoreLayout:{restored+=1})
  let parent=layer.superlayer
  owner.present(frame:NSRect(x:0,y:0,width:320,height:180),clip:container.bounds,rotation:.pi/3)
  let raster=layer.bounds
  for index in 0..<10 { owner.present(frame:NSRect(x:20,y:30,width:400,height:225),clip:container.bounds,rotation:CGFloat(index+1)/10) }
  if !endRotated { owner.present(frame:NSRect(x:10,y:20,width:400,height:225),clip:container.bounds) }
  check(layer.bounds==raster && native.layer===layer && layer.superlayer===parent,"mixed rotation does not replace or resize native raster")
  owner.restore();owner.restore()
  check(layer.mask===original && CATransform3DEqualToTransform(layer.transform,originalTransform),"both aperture kinds restore original native mask/transform: rotated=\(endRotated), mask=\(layer.mask===original), transform=\(layer.transform), expected=\(originalTransform)")
  check(acquired==1 && restored==1 && layer.contentsFormat == .RGBA16Float && layer.contentsScale==2,"layout is owned once and native output precision survives")
}
let (canonicalContainer,canonicalNative,canonicalLayer)=context()
let cancelled=NativeCropVideoPresentation(view:canonicalNative,container:canonicalContainer,pixelSize:NSSize(width:3840,height:2160))
cancelled.present(frame:NSRect(x:0,y:0,width:320,height:180),clip:canonicalContainer.bounds,rotation:.pi/2)
let canonicalMask=CALayer();canonicalLayer.mask=canonicalMask;canonicalLayer.transform=CATransform3DIdentity
cancelled.restore()
check(canonicalLayer.mask===canonicalMask && CATransform3DIsIdentity(canonicalLayer.transform),"stale rotated restoration preserves newer canonical ownership")
print("PASS: \(checks) affine rotation, inverse clip, quarter-turn, dynamic fit, zero-angle parity and restoration checks; no window or renderer")
