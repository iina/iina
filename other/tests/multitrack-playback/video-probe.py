"""Exercise the repository's actual libmpv without opening an output device."""
import ctypes as C, json, math, sys, time, wave, subprocess
from pathlib import Path
lib=Path(sys.argv[1]).resolve();fixture=Path(sys.argv[2]).resolve();output=Path(sys.argv[3]).resolve();output.mkdir(parents=True,exist_ok=True)
m=C.CDLL(str(lib))
class Event(C.Structure):_fields_=[('event_id',C.c_int),('error',C.c_int),('reply_userdata',C.c_ulonglong),('data',C.c_void_p)]
m.mpv_create.restype=C.c_void_p
for name,args,result in [('mpv_initialize',[C.c_void_p],C.c_int),('mpv_set_option_string',[C.c_void_p,C.c_char_p,C.c_char_p],C.c_int),('mpv_set_property_string',[C.c_void_p,C.c_char_p,C.c_char_p],C.c_int),('mpv_get_property_string',[C.c_void_p,C.c_char_p],C.c_void_p),('mpv_command',[C.c_void_p,C.POINTER(C.c_char_p)],C.c_int),('mpv_wait_event',[C.c_void_p,C.c_double],C.POINTER(Event)),('mpv_terminate_destroy',[C.c_void_p],None),('mpv_free',[C.c_void_p],None)]:
 f=getattr(m,name);f.argtypes=args;f.restype=result

def get(p,key):
 v=m.mpv_get_property_string(p,key.encode())
 if not v:return None
 s=C.string_at(v).decode();m.mpv_free(v);return s

def put(p,key,value):
 code=m.mpv_set_property_string(p,key.encode(),str(value).encode());assert code>=0,(key,value,code)

def command(p,*args):
 a=(C.c_char_p*(len(args)+1))(*[s.encode() for s in args],None);code=m.mpv_command(p,a);assert code>=0,(args,code)

def create(options):
 p=m.mpv_create();assert p
 for k,v in {'config':'no','terminal':'no','vo':'null','vid':'no','audio-display':'no',**options}.items():
  assert m.mpv_set_option_string(p,k.encode(),str(v).encode())>=0,(k,v)
 assert m.mpv_initialize(p)>=0
 return p

def await_event(p,event,timeout=12):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  e=m.mpv_wait_event(p,.1).contents
  if e.event_id==event:return
  if e.event_id==7 and event!=7:raise AssertionError(('early end',e.error,get(p,'lavfi-complex')))
 raise AssertionError(('timeout',event))

def graph(ids):return ''.join(f'[aid{i}]' for i in sorted(ids))+f'amix=inputs={len(ids)}:normalize=0:dropout_transition=0,alimiter=level=false:latency=true[ao]'


graphs=json.loads(Path(sys.argv[4]).read_text())
# Render the exact graphs emitted by the production Swift graph builder.
for case in graphs:
 order=case['order']; folder=output/('order-'+''.join(map(str,order))); folder.mkdir(exist_ok=True)
 wav=folder/'audio.wav'
 p=create({'vo':'image','vo-image-format':'png','vo-image-outdir':str(folder),
           'ao':'pcm','ao-pcm-file':str(wav),'audio-format':'s16','audio-samplerate':'48000',
           'audio-channels':'stereo','untimed':'yes','length':'2','lavfi-complex':case['combined']})
 try:command(p,'loadfile',str(fixture));await_event(p,7,30)
 finally:m.mpv_terminate_destroy(p)
 frame=next(folder.glob('*.png'))
 raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(frame),'-frames:v','1','-f','rawvideo','-pix_fmt','rgb24','-'])
 def pixel(x,y):return tuple(raw[(y*320+x)*3:(y*320+x)*3+3])
 expected = {
  (1,2,3):[(0,0,255),(127,0,127),(127,127,0),(0,255,0)],
  (2,1,3):[(0,0,255),(127,0,127),(0,255,0),(0,255,0)],
  (3,2,1):[(0,0,255)]*4,
 }[tuple(order)]
 points=[(0,0),(30,30),(70,70),(120,120)]
 actual=[pixel(*pt) for pt in points]
 assert all(all(abs(a-b)<5 for a,b in zip(rgb,want)) for rgb,want in zip(actual,expected)),(order,actual,expected)
 print('PASS real video pixels, alpha and stacking order',order,actual,flush=True)
 with wave.open(str(wav),'rb') as w:
  import array
  samples=array.array('h',w.readframes(48000))[::w.getnchannels()]
 for frequency in [330,660]:
  re=sum(v*math.cos(2*math.pi*frequency*i/48000) for i,v in enumerate(samples))
  im=sum(v*math.sin(2*math.pi*frequency*i/48000) for i,v in enumerate(samples))
  assert 2*math.hypot(re,im)/len(samples)/32768 > .025
 print('PASS both audio inputs survive simultaneous video compositing',order,flush=True)

p=create({'ao':'null','vid':'auto','pause':'yes','keep-open':'yes'})
try:
 command(p,'loadfile',str(fixture));await_event(p,8)
 for case in graphs:
  put(p,'lavfi-complex',case['combined'])
  command(p,'seek','1','absolute+exact')
  until=time.monotonic()+2
  while time.monotonic()<until:
   m.mpv_wait_event(p,.02)
   if abs(float(get(p,'time-pos') or 0)-1)<.05:break
  selected=json.loads(get(p,'track-list'))
  assert {t['id'] for t in selected if t['type']=='video' and t['selected']}=={1,2,3},selected
  assert {t['id'] for t in selected if t['type']=='audio' and t['selected']}=={1,2},selected
  assert abs(float(get(p,'time-pos') or 0)-1)<.05
  print('PASS live combined graph reordering and paused exact seek',case['order'],flush=True)
 # Remove one graph output while keeping the other; force native reselection.
 for keep,removed in [('video','audio'),('audio','video')]:
  put(p,'lavfi-complex',graphs[0]['combined'])
  remaining=graphs[0]['video'] if keep=='video' else graph([1,2])
  put(p,'lavfi-complex',remaining)
  option='aid' if removed=='audio' else 'vid'
  put(p,option,'no');put(p,option,'1')
  m.mpv_wait_event(p,.05)
  selected=json.loads(get(p,'track-list'))
  active={t['id'] for t in selected if t['type']==removed and t['selected']}
  assert active=={1},(keep,active,selected)
  print('PASS native solo',removed,'preserves complex',keep,flush=True)
 put(p,'lavfi-complex','')
 for option in ['aid','vid']:put(p,option,'no');put(p,option,'1')
 selected=json.loads(get(p,'track-list'))
 assert {t['id'] for t in selected if t['type']=='video' and t['selected']}=={1},selected
 print('PASS complete return to native audio/video solo',flush=True)
finally:m.mpv_terminate_destroy(p)

# Regression: native MKV seeking skips earlier streams' keyframes when their
# cues lie in separate clusters. Exercise the file-local on_load workaround.
if len(sys.argv) > 5:
 h264=Path(sys.argv[5]).resolve()
 class Hook(C.Structure): _fields_=[('name',C.c_char_p),('id',C.c_uint64)]
 m.mpv_hook_add.argtypes=[C.c_void_p,C.c_uint64,C.c_char_p,C.c_int]
 m.mpv_hook_continue.argtypes=[C.c_void_p,C.c_uint64]
 for key,point,want in [('h264',(20,200),(15,48,80)),('h264Reverse',(180,20),(28,78,60))]:
  folder=output/key;folder.mkdir(exist_ok=True)
  p=create({'ao':'null','vo':'image','vid':'1','pause':'yes','vo-image-format':'png',
            'vo-image-outdir':str(folder),'untimed':'yes','length':'1','start':'5.208'})
  try:
   assert m.mpv_hook_add(p,123,b'on_load',0)>=0
   command(p,'loadfile',str(h264))
   until=time.monotonic()+12;handled=False
   while time.monotonic()<until:
    e=m.mpv_wait_event(p,.1).contents
    if e.event_id==25:
     hook=C.cast(e.data,C.POINTER(Hook)).contents
     put(p,'file-local-options/demuxer','lavf');m.mpv_hook_continue(p,hook.id);handled=True
    elif e.event_id==8:break
   assert handled and get(p,'demuxer')=='lavf'
   put(p,'lavfi-complex',graphs[0][key])
   put(p,'aid','no');put(p,'aid','1');put(p,'pause','no');await_event(p,7)
  finally:m.mpv_terminate_destroy(p)
  frame=sorted(folder.glob('*.png'))[-1]
  dimensions=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-of','json',str(frame)]))['streams'][0]
  width=dimensions['width'];raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(frame),'-frames:v','1','-f','rawvideo','-pix_fmt','rgb24','-'])
  x,y=point;rgb=tuple(raw[(y*width+x)*3:(y*width+x)*3+3])
  assert all(abs(a-b)<6 for a,b in zip(rgb,want)),(key,rgb,want)
  print('PASS on_load file-local demuxer and runtime H.264 layer order',key,rgb,flush=True)
