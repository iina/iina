"""Exercise the repository's actual libmpv without opening an output device."""
import ctypes as C, json, math, sys, time, wave
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

# Render real mixed PCM and measure each distinctive input frequency.
for ids in [[1],[1,2,3,4],[2,4]]:
 wav=output/('mix-'+''.join(map(str,ids))+'.wav')
 options={'ao':'pcm','ao-pcm-file':str(wav),'audio-format':'s16','audio-samplerate':'48000','audio-channels':'stereo','untimed':'yes','length':'2'}
 if len(ids)>1:options['lavfi-complex']=graph(ids)
 else:options['aid']=str(ids[0])
 p=create(options)
 try:command(p,'loadfile',str(fixture));await_event(p,7,30)
 finally:m.mpv_terminate_destroy(p)
 with wave.open(str(wav),'rb') as w:
  assert w.getsampwidth()==2
  channels=w.getnchannels();rate=w.getframerate();raw=w.readframes(rate)
 import array
 samples=array.array('h',raw)[::channels]
 amplitudes={}
 for track,freq in enumerate([330,440,550,660],1):
  re=sum(x*math.cos(2*math.pi*freq*i/rate) for i,x in enumerate(samples));im=sum(x*math.sin(2*math.pi*freq*i/rate) for i,x in enumerate(samples))
  amplitude=2*math.hypot(re,im)/len(samples)/32768;amplitudes[track]=round(amplitude,6)
  assert (amplitude>.025 if track in ids else amplitude<.001),(ids,track,amplitudes)
 print('PASS bundled libmpv PCM',ids,amplitudes,flush=True)

p=create({'ao':'null','pause':'yes','keep-open':'yes'})
try:
 command(p,'loadfile',str(fixture));await_event(p,8)
 tracks=json.loads(get(p,'track-list'))
 assert len([t for t in tracks if t['type']=='video'])==3
 assert len([t for t in tracks if t['type']=='audio'])==4
 for ids in [[1,2],[1,2,3,4],[2,4]]:
  put(p,'lavfi-complex',graph(ids))
  # Synchronous graph write has attached the labelled inputs; drain notices.
  m.mpv_wait_event(p,.05)
  tracks=json.loads(get(p,'track-list'))
  selected=[t['id'] for t in tracks if t['type']=='audio' and t['selected']]
  assert set(selected)==set(ids),(ids,selected)
  command(p,'seek','10','absolute+exact')
  end=time.monotonic()+3
  while time.monotonic()<end:
   m.mpv_wait_event(p,.02)
   pos=float(get(p,'time-pos') or 0)
   if abs(pos-10)<.1:break
  assert abs(pos-10)<.1,pos
  print('PASS live graph reassignment + paused seek',ids,'native aid',get(p,'aid'),flush=True)
 put(p,'lavfi-complex','');put(p,'aid','1')
 assert get(p,'aid')=='1'
 print('PASS return from mix to native solo',flush=True)
 # Regression: selecting the first-added input after successive graph changes
 # can be ignored by mpv unless its cached native aid is cleared first.
 m.mpv_set_property.argtypes=[C.c_void_p,C.c_char_p,C.c_int,C.c_void_p]
 m.mpv_set_property.restype=C.c_int
 def set_aid(value):
  data=C.c_int64(value)
  assert m.mpv_set_property(p,b'aid',4,C.byref(data))>=0
 for ids in [[1,2,4],[2,4,1],[4,1,2],[3,2,1]]:
  put(p,'lavfi-complex','');set_aid(0);set_aid(ids[0])
  for count in [2,3]:put(p,'lavfi-complex',graph(ids[:count]))
  put(p,'lavfi-complex','');set_aid(0);set_aid(ids[0])
  end=time.monotonic()+.15
  while time.monotonic()<end:m.mpv_wait_event(p,.01)
  active=[t['id'] for t in json.loads(get(p,'track-list')) if t['type']=='audio' and t['selected']]
  assert active==[ids[0]] and get(p,'aid')==str(ids[0]),(ids,active,get(p,'aid'))
  print('PASS successive mix additions -> first-added native solo',ids,flush=True)
finally:m.mpv_terminate_destroy(p)
