"""Verify independent subtitle styles on real libmpv software-rendered pixels."""
import ctypes as C
import json
import os
from pathlib import Path
import subprocess
import sys
import time

lib, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=True)
media = out / 'two-subtitles.mkv'
for i in (1, 2):
    (out / f'{i}.srt').write_text('1\n00:00:00,000 --> 00:00:09,000\nSubtitle ABCDE 123\n')
subprocess.run(['ffmpeg', '-y', '-v', 'error', '-f', 'lavfi', '-i',
                'color=black:s=640x360:r=10:d=10', '-i', str(out/'1.srt'),
                '-i', str(out/'2.srt'), '-map', '0:v', '-map', '1:s', '-map', '2:s',
                '-c:v', 'libx264', '-preset', 'ultrafast', '-c:s', 'srt', str(media)], check=True, env={k:v for k,v in os.environ.items() if k!='DYLD_LIBRARY_PATH'})
m = C.CDLL(str(lib))
class Event(C.Structure):
    _fields_ = [('id', C.c_int), ('error', C.c_int), ('userdata', C.c_uint64), ('data', C.c_void_p)]
class Param(C.Structure):
    _fields_ = [('type', C.c_int), ('data', C.c_void_p)]
for name, args, result in [
    ('mpv_create', [], C.c_void_p), ('mpv_initialize', [C.c_void_p], C.c_int),
    ('mpv_set_option_string', [C.c_void_p, C.c_char_p, C.c_char_p], C.c_int),
    ('mpv_set_property_string', [C.c_void_p, C.c_char_p, C.c_char_p], C.c_int),
    ('mpv_get_property_string', [C.c_void_p, C.c_char_p], C.c_void_p),
    ('mpv_command', [C.c_void_p, C.POINTER(C.c_char_p)], C.c_int),
    ('mpv_wait_event', [C.c_void_p, C.c_double], C.POINTER(Event)),
    ('mpv_render_context_create', [C.POINTER(C.c_void_p), C.c_void_p, C.POINTER(Param)], C.c_int),
    ('mpv_render_context_render', [C.c_void_p, C.POINTER(Param)], C.c_int),
    ('mpv_render_context_update', [C.c_void_p], C.c_uint64),
    ('mpv_render_context_free', [C.c_void_p], None),
    ('mpv_terminate_destroy', [C.c_void_p], None), ('mpv_free', [C.c_void_p], None),
]:
    f = getattr(m, name); f.argtypes = args; f.restype = result

results = []
def check(value, label):
    assert value, label
    results.append(label); print('PASS:', label, flush=True)

class Player:
    def __init__(self, separate, source=media, overrides=None):
        self.p = m.mpv_create()
        options = {'config':'no', 'terminal':'no', 'vo':'libmpv', 'ao':'null',
                   'pause':'yes', 'keep-open':'yes', 'start':'1', 'osd-level':'0',
                   'sid':'1', 'secondary-sid':'2', 'sub-font':'Helvetica Neue',
                   'sub-font-size':'50', 'sub-color':'1/0/0/1', 'sub-outline-size':'0',
                   'sub-shadow-offset':'0', 'sub-back-color':'0/0/0/0',
                   'secondary-sub-style-override': 'yes' if separate else 'no',
                   'secondary-sub-font':'Helvetica Neue', 'secondary-sub-font-size':'25',
                   'secondary-sub-color':'0/1/0/1', 'secondary-sub-outline-size':'0',
                   'secondary-sub-shadow-offset':'0', 'secondary-sub-back-color':'0/0/0/0'}
        options.update(overrides or {})
        for k,v in options.items():
            assert m.mpv_set_option_string(self.p, k.encode(), v.encode()) >= 0, (k,v)
        assert m.mpv_initialize(self.p) >= 0
        self.ctx = C.c_void_p()
        sw = C.create_string_buffer(b'sw')
        params = (Param*2)(Param(1, C.cast(sw,C.c_void_p)), Param(0,None))
        assert m.mpv_render_context_create(C.byref(self.ctx), self.p, params) >= 0
        self.size = (C.c_int*2)(640,360); self.stride = C.c_size_t(640*4)
        self.pixels = (C.c_ubyte*(640*360*4))(); self.format=C.create_string_buffer(b'rgb0')
        self.params=(Param*5)(Param(17,C.cast(self.size,C.c_void_p)),
            Param(18,C.cast(self.format,C.c_void_p)),Param(19,C.cast(C.byref(self.stride),C.c_void_p)),
            Param(20,C.cast(self.pixels,C.c_void_p)),Param(0,None))
        self.command('loadfile', str(source))
    def command(self,*args):
        command=(C.c_char_p*(len(args)+1))(*[str(a).encode() for a in args],None)
        assert m.mpv_command(self.p,command)>=0,args
    def put(self,k,v):
        assert m.mpv_set_property_string(self.p,k.encode(),str(v).encode())>=0,(k,v)
    def frame(self,name):
        end=time.monotonic()+.5
        while time.monotonic()<end:
            m.mpv_wait_event(self.p,.01)
            m.mpv_render_context_update(self.ctx)
            assert m.mpv_render_context_render(self.ctx,self.params)>=0
        raw=bytes(self.pixels)
        rgb=bytearray()
        for i in range(0,len(raw),4): rgb.extend(raw[i:i+3])
        (out/(name+'.ppm')).write_bytes(b'P6\n640 360\n255\n'+rgb)
        return raw
    def close(self):
        m.mpv_render_context_free(self.ctx);m.mpv_terminate_destroy(self.p)

def regions(raw, channel):
    return [{(i//4%640, i//4//640) for i in range(y0*640*4,y1*640*4,4)
             if raw[i+channel]>120 and all(raw[i+channel]>raw[i+c]*2 for c in range(3) if c!=channel)}
            for y0,y1 in [(0,180),(180,360)]]

def height(points):
    return max(y for x,y in points)-min(y for x,y in points)+1

p=Player(True)
try:
    before=p.frame('independent')
    red,green=regions(before,0),regions(before,1)
    check(len(red[1])>200 and len(green[0])>100 and not red[0] and not green[1],
          'Primary renders red at the bottom; Secondary renders green at the top')
    check(height(red[1])>height(green[0])*1.5, '50 and 25 font sizes render independently')
    p.put('sub-font-size',60)
    larger=p.frame('primary-larger')
    check(regions(larger,1)==green, 'changing Primary size leaves Secondary pixels unchanged')
    p.put('secondary-sub-scale',2)
    scaled=p.frame('secondary-scaled')
    check(regions(scaled,0)==regions(larger,0) and height(regions(scaled,1)[0])>height(green[0])*1.5,
          'Secondary scale changes only Secondary rendering')
    p.put('secondary-sub-font','Georgia')
    font=p.frame('secondary-font')
    check(regions(font,0)==regions(scaled,0) and regions(font,1)!=regions(scaled,1),
          'Secondary font family changes independently')
    p.put('secondary-sub-outline-color','0/0/1/1');p.put('secondary-sub-outline-size',4)
    border=p.frame('secondary-border')
    check(len(regions(border,2)[0])>100 and not regions(border,2)[1] and regions(border,0)==regions(font,0),
          'Secondary outline color and width do not alter Primary')
    p.put('secondary-sub-back-color','1/1/0/1');p.put('secondary-sub-shadow-offset',4)
    shadow=p.frame('secondary-shadow')
    check(shadow[:180*640*4]!=border[:180*640*4] and shadow[180*640*4:]==border[180*640*4:],
          'Secondary background/shadow color changes only its own pixels')
    p.command('seek','3','absolute+exact')
    check(p.frame('seek')==shadow, 'independent styles survive exact seek')
    p.put('sid','no');p.put('secondary-sid','no');p.put('sid','2');p.put('secondary-sid','1')
    check(p.frame('swapped-sources')==shadow, 'styles follow roles when source tracks swap')
    p.command('loadfile',str(media),'replace')
    check(p.frame('reload')==shadow, 'independent styles survive reloading the file')
finally: p.close()
p=Player(False)
try:
    inherited=p.frame('stock-inheritance')
    red=regions(inherited,0)
    check(len(red[0])>200 and len(red[1])>200 and not any(regions(inherited,1)),
          'without opt-in Secondary retains stock Primary style inheritance')
finally:p.close()
ass_media = out/'two-ass.mkv'
subprocess.run(['ffmpeg', '-y', '-v', 'error', '-i', str(media), '-map', '0',
                '-c:v', 'copy', '-c:s', 'ass', str(ass_media)], check=True,
               env={k:v for k,v in os.environ.items() if k!='DYLD_LIBRARY_PATH'})
p=Player(True, ass_media, {'sub-ass-override':'force', 'secondary-sub-ass-override':'strip'})
try:
    ass=p.frame('ass-force-strip')
    check(len(regions(ass,0)[1])>100 and len(regions(ass,1)[0])>100,
          'ASS force and strip modes respect their independent role styles')
    p.put('secondary-sub-font-size',40)
    changed=p.frame('ass-secondary-size')
    check(regions(changed,0)==regions(ass,0) and height(regions(changed,1)[0])>height(regions(ass,1)[0]),
          'changing Secondary ASS style preserves Primary ASS pixels')
finally:p.close()
(out/'results.json').write_text(json.dumps({'checks':results,'libmpv':str(lib)},indent=2))
