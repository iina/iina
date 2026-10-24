"""Measure output latency through muted CoreAudio, with a test-only engine tap.

Arguments: instrumented libmpv, four-tone fixture, output directory, production
persistent-graphs.json, case (plain/loudnorm, optional phase/layers/stress, and
refresh to exercise the fix). Apply audio-output-tap.patch only to a test build.
The tap captures generated audio before software mute; no microphone is read.
"""
import array, ctypes as C, json, math, os, struct, sys, time
from pathlib import Path
lib,fixture,out,graph_file=map(Path,sys.argv[1:5])
out.mkdir(parents=True,exist_ok=True)
label=sys.argv[5];refresh='refresh' in label;normalize='loudnorm' in label
capture=out/(label+'.capture');capture.unlink(missing_ok=True)
os.environ['LYINA_TEST_AUDIO_CAPTURE']=str(capture)
m=C.CDLL(str(lib.resolve()))
class Event(C.Structure):_fields_=[('id',C.c_int),('error',C.c_int),('userdata',C.c_ulonglong),('data',C.c_void_p)]
m.mpv_create.restype=C.c_void_p
for n,a,r in [('mpv_initialize',[C.c_void_p],C.c_int),('mpv_get_time_ns',[C.c_void_p],C.c_int64),('mpv_set_option_string',[C.c_void_p,C.c_char_p,C.c_char_p],C.c_int),('mpv_set_property_string',[C.c_void_p,C.c_char_p,C.c_char_p],C.c_int),('mpv_get_property_string',[C.c_void_p,C.c_char_p],C.c_void_p),('mpv_command',[C.c_void_p,C.POINTER(C.c_char_p)],C.c_int),('mpv_wait_event',[C.c_void_p,C.c_double],C.POINTER(Event)),('mpv_terminate_destroy',[C.c_void_p],None),('mpv_free',[C.c_void_p],None)]:
 f=getattr(m,n);f.argtypes=a;f.restype=r

def get(p,key):
 v=m.mpv_get_property_string(p,key.encode())
 if not v:return None
 s=C.string_at(v).decode();m.mpv_free(v);return s

def cmd(p,*args):
 a=(C.c_char_p*(len(args)+1))(*[x.encode() for x in args],None)
 assert m.mpv_command(p,a)>=0,args

p=m.mpv_create();graph=json.loads(graph_file.read_text())['graph']
if 'layers' in label:
 graph += ';' + json.loads((graph_file.parent/'graphs.json').read_text())[0]['h264']
options={'config':'no','terminal':'no','vo':'null','vid':'no','audio-display':'no','ao':'coreaudio','volume':'0','audio-format':'s16','audio-samplerate':'48000','audio-channels':'stereo','lavfi-complex':graph,'keep-open':'yes','log-file':str(out/(label+'.log'))}
if 'video' in label or 'layers' in label:options['vid']='auto'
if normalize:options['af']='lavfi=[loudnorm=I=-20.4:TP=-1:LRA=11:linear=false:measured_I=-28.1:measured_TP=-2.7:measured_LRA=4.1:measured_thresh=-38.6:offset=3.67]'
for k,v in options.items():assert m.mpv_set_option_string(p,k.encode(),v.encode())>=0,(k,v)
assert m.mpv_initialize(p)>=0
markers=[];restarts=0
def tick(p,seconds=.005):
 global restarts
 event=m.mpv_wait_event(p,seconds).contents
 restarts += event.id==21
 return event

try:
 cmd(p,'loadfile',str(fixture.resolve()))
 deadline=time.monotonic()+12
 while time.monotonic()<deadline:
  e=m.mpv_wait_event(p,.01).contents
  if e.id==21:break
 else:raise AssertionError('no playback-restart')
 assert get(p,'audio-out-params/samplerate')=='48000'
 for ids in ([[1,2],[1,2,3],[1,2,3,4],[1],[1,3]] if 'phase' in label else [[1,2],[],[2],[2,3,4],[1]]):
  until=time.monotonic()+(.7 if refresh or 'phase' in label else 3.6)
  while time.monotonic()<until:tick(p)
  before=m.mpv_get_time_ns(p);pos=get(p,'time-pos');start=time.monotonic()
  cmd(p,'lavfi-complex-command','amix@iina_audio_mix','weights',' '.join('1' if i in ids else '0' for i in range(1,5)),*(['yes'] if refresh else []))
  markers.append({'ids':ids,'time_ns':before,'command_ms':(time.monotonic()-start)*1000,'time_pos':pos})
 if 'stress' in label:
  def put(key,value):
   assert m.mpv_set_property_string(p,key.encode(),str(value).encode())>=0
  def drain(seconds):
   until=time.monotonic()+seconds
   while time.monotonic()<until:tick(p)
  def gains(ids):
   cmd(p,'lavfi-complex-command','amix@iina_audio_mix','weights',' '.join('1' if i in ids else '0' for i in range(1,5)),'yes')
  drain(.5);put('pause','yes');drain(.1);frozen=float(get(p,'time-pos'))
  for n in range(100):gains([2] if n%2 else [1,3])
  drain(.2)
  assert get(p,'pause')=='yes' and abs(float(get(p,'time-pos'))-frozen)<.05
  cmd(p,'seek','12','absolute+exact');gains([3]);drain(.4)
  assert get(p,'pause')=='yes' and abs(float(get(p,'time-pos'))-12)<.1
  restarts=0
  begin=m.mpv_get_time_ns(p);put('pause','no')
  markers.append({'ids':[3],'time_ns':begin,'command_ms':0,'case':'paused seek and gains before configuration'})
  drain(.8)
  begin=m.mpv_get_time_ns(p)
  for n in range(100):
   if n==99:begin=m.mpv_get_time_ns(p)
   gains([2,4] if n%2 else [1])
  markers.append({'ids':[2,4],'time_ns':begin,'command_ms':0,'case':'100 playing changes'})
  drain(.8);before=float(get(p,'time-pos'));put('speed','2')
  begin=m.mpv_get_time_ns(p);gains([1,3])
  markers.append({'ids':[1,3],'time_ns':begin,'command_ms':0,'case':'2x speed'})
  drain(.8)
  assert float(get(p,'time-pos'))-before>1.1
 until=time.monotonic()+(1 if refresh else 3.6)
 while time.monotonic()<until:
  tick(p)
 assert get(p,'lavfi-complex')==graph
finally:m.mpv_terminate_destroy(p)

# Least squares separates non-integer-period tones in short CoreAudio callbacks.
bases={}
def coefficients(n,rate):
 key=n,rate
 if key not in bases:
  cols=[[f(2*math.pi*hz*i/rate) for i in range(n)] for hz in [330,440,550,660] for f in [math.cos,math.sin]]
  matrix=[[sum(a*b for a,b in zip(x,y)) for y in cols]+[float(j==i) for j in range(8)] for i,x in enumerate(cols)]
  for i in range(8):
   k=max(range(i,8),key=lambda k:abs(matrix[k][i]));matrix[i],matrix[k]=matrix[k],matrix[i]
   pivot=matrix[i][i];matrix[i]=[v/pivot for v in matrix[i]]
   for j in range(8):
    if j!=i:
     q=matrix[j][i];matrix[j]=[v-q*w for v,w in zip(matrix[j],matrix[i])]
  inverse=[r[8:] for r in matrix]
  bases[key]=[[sum(inverse[j][k]*cols[k][i] for k in range(8)) for i in range(n)] for j in range(8)]
 return bases[key]

blocks=[];total=0;phases=[];carried=[]
with capture.open('rb') as f:
 while h:=f.read(64):
  stamp,n,rate,channels,planes,stride,samplebytes,fmt=struct.unpack('8Q',h)
  raw=[f.read(n*stride) for _ in range(planes)]
  assert samplebytes==2,(samplebytes,fmt)
  samples=array.array('h',raw[0])[::1 if planes>1 else channels]
  offset=total;total+=n
  if len(samples)<64:continue
  coeff=[sum(x*y for x,y in zip(samples,b))/32768 for b in coefficients(len(samples),rate)]
  amps=[math.hypot(coeff[i],coeff[i+1]) for i in range(0,8,2)]
  blocks.append((stamp,amps))
  if 'phase' in label and n>=384 and any(400e6<stamp-x['time_ns']<600e6 for x in markers):
   phase=math.atan2(-coeff[1],coeff[0])-2*math.pi*330*offset/rate
   phases.append(math.atan2(math.sin(phase),math.cos(phase)))
   carried.append(amps[0])
results=[]
for i,marker in enumerate(markers):
 end=markers[i+1]['time_ns'] if i+1<len(markers) else 2**63
 found=None
 for stamp,amps in blocks:
  if not marker['time_ns']<=stamp<end:continue
  if all((a>.015 if k+1 in marker['ids'] else a<.001) for k,a in enumerate(amps)):
   found=(stamp-marker['time_ns'])/1e6;break
 row={**marker,'onset_ms':found};results.append(row)
 print(label,json.dumps(row),flush=True)
 assert found is not None,(label,row)
 if refresh:assert found<300,(label,row)
assert restarts==0,restarts
report={'results':results,'restarts':restarts}
if phases:
 middle=phases[len(phases)//2]
 drift=max(abs(math.atan2(math.sin(x-middle),math.cos(x-middle))) for x in phases)
 assert drift<.01,('carried-track phase jump',drift)
 assert max(carried)-min(carried)<.001,('carried-track gain change',min(carried),max(carried))
 report['phase_drift_rad']=drift
 report['carried_amplitude_range']=[min(carried),max(carried)]
 print('PASS continuous carried-track phase and gain',drift,flush=True)
(out/(label+'-results.json')).write_text(json.dumps(report,indent=2)+'\n')
