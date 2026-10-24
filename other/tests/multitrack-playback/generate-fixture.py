from pathlib import Path
import subprocess,sys
output=Path(sys.argv[1]).expanduser().resolve()
if output.exists(): raise SystemExit(f'Refusing to overwrite {output}')
output.parent.mkdir(parents=True,exist_ok=True)
import tempfile
work=tempfile.TemporaryDirectory(prefix='iina-multitrack-')
assets=Path(work.name)
renderer=assets/'labels.swift'
renderer.write_text(r'''import Cocoa
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let folder = CommandLine.arguments[1]
for (i, size) in [NSSize(width:1280,height:720), NSSize(width:960,height:720), NSSize(width:720,height:1280)].enumerated() {
 let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width),pixelsHigh:Int(size.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 NSGraphicsContext.saveGraphicsState()
 NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
 [NSColor(red:0.08,green:0.2,blue:0.31,alpha:1),NSColor(red:0.13,green:0.33,blue:0.24,alpha:1),NSColor(red:0.29,green:0.16,blue:0.36,alpha:1)][i].setFill()
 NSRect(origin:.zero,size:size).fill()
 let paragraph=NSMutableParagraphStyle(); paragraph.alignment = .center
 let text="VIDEO \(i+1)  |  \(Int(size.width)) x \(Int(size.height))\n\nIINA MULTITRACK TEST\n\nAudio 1: Game - 330 Hz\nAudio 2: Microphone - 440 Hz\nAudio 3: Discord - 550 Hz\nAudio 4: System - 660 Hz"
 let attrs:[NSAttributedString.Key:Any] = [.font:NSFont.monospacedSystemFont(ofSize:28,weight:.medium),.foregroundColor:NSColor.white,.paragraphStyle:paragraph]
 (text as NSString).draw(in:NSRect(x:24,y:size.height/2-170,width:size.width-48,height:340),withAttributes:attrs)
 NSGraphicsContext.restoreGraphicsState()
 try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:folder).appendingPathComponent("video\(i).png"))
}
''')
subprocess.run(['xcrun','swift',str(renderer),str(assets)],check=True)
duration=30
cmd=['ffmpeg','-hide_banner','-loglevel','error','-nostdin','-n']
for i in range(3):cmd+=['-loop','1','-framerate','24','-i',str(assets/f'video{i}.png')]
for freq in [330,440,550,660]:
 cmd+=['-f','lavfi','-i',f'sine=frequency={freq}:sample_rate=48000:duration={duration}']
filters=[f'[{i}:v]format=yuv420p[v{i}]' for i in range(3)]
for i in range(4): filters.append(f'[{i+3}:a]volume=0.5,pan=stereo|c0=c0|c1=c0[a{i}]')
cmd+=['-filter_complex',';'.join(filters)]
for i in range(3):cmd+=['-map',f'[v{i}]']
for i in range(4):cmd+=['-map',f'[a{i}]']
cmd+=['-c:v','libx264','-preset','ultrafast','-crf','24','-pix_fmt','yuv420p','-threads','2','-c:a','pcm_s16le']
for i,title in enumerate(['Video 1 - Landscape 16:9','Video 2 - Classic 4:3','Video 3 - Portrait 9:16']):
 cmd+= [f'-metadata:s:v:{i}',f'title={title}',f'-disposition:v:{i}','default' if i==0 else '0']
for i,(title,lang) in enumerate([('Game - 330 Hz','eng'),('Microphone - 440 Hz','rus'),('Discord - 550 Hz','deu'),('System - 660 Hz','jpn')]):
 cmd += [f'-metadata:s:a:{i}',f'title={title}',f'-metadata:s:a:{i}',f'language={lang}',f'-disposition:a:{i}','default' if i==0 else '0']
cmd += ['-t',str(duration),str(output)]
subprocess.run(cmd,check=True)
print(output)
