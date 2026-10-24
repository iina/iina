"""Exercise the repository's actual libmpv without opening an output device."""
import ctypes as C, sys, time
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

class Param(C.Structure):_fields_=[('type',C.c_int),('data',C.c_void_p)]
for name,args,result in [('mpv_render_context_create',[C.POINTER(C.c_void_p),C.c_void_p,C.POINTER(Param)],C.c_int),('mpv_render_context_update',[C.c_void_p],C.c_uint64),('mpv_render_context_render',[C.c_void_p,C.POINTER(Param)],C.c_int),('mpv_render_context_report_swap',[C.c_void_p],None),('mpv_render_context_free',[C.c_void_p],None)]:
 f=getattr(m,name);f.argtypes=args;f.restype=result
p=create({'vo':'libmpv','vid':'3','demuxer':'lavf','ao':'null','pause':'yes','keep-open':'yes','osd-level':'0'})
context=C.c_void_p();api=C.create_string_buffer(b'sw')
params=(Param*2)(Param(1,C.cast(api,C.c_void_p)),Param(0,None))
assert m.mpv_render_context_create(C.byref(context),p,params)>=0

def render(w,h):
 size=(C.c_int*2)(w,h);fmt=C.create_string_buffer(b'rgb0');stride=C.c_size_t(w*4);pixels=C.create_string_buffer(w*h*4);block=C.c_int(0)
 params=(Param*6)(Param(17,C.cast(size,C.c_void_p)),Param(18,C.cast(fmt,C.c_void_p)),Param(19,C.cast(C.byref(stride),C.c_void_p)),Param(20,C.cast(pixels,C.c_void_p)),Param(12,C.cast(C.byref(block),C.c_void_p)),Param(0,None))
 assert m.mpv_render_context_render(context,params)>=0
 m.mpv_render_context_report_swap(context)
 return bytes(pixels)
try:
 command(p,'loadfile',str(fixture))
 ready=False;until=time.monotonic()+10
 while time.monotonic()<until:
  event=m.mpv_wait_event(p,.01).contents
  if m.mpv_render_context_update(context)&1:render(640,360)
  if event.event_id==21:ready=True;break
 assert ready,'paused output failed to present'
 for fill in [0,1]:
  put(p,'file-local-options/panscan',fill)
  for w,h in [(640,360),(500,500),(400,712)]:
   raw=render(w,h)
   points=[(4,4),(w-5,4),(4,h-5),(w-5,h-5)]
   black=sum(max(raw[(y*w+x)*4:(y*w+x)*4+3])<5 for x,y in points)
   if fill==1:assert black==0,(fill,w,h,black)
   elif w>h:assert black>0,(fill,w,h,black)
   (output/f'portrait-fill-{fill}-{w}x{h}.ppm').write_bytes(f'P6\n{w} {h}\n255\n'.encode()+b''.join(raw[i:i+3] for i in range(0,len(raw),4)))
   print('PASS real render viewport',w,h,'fill',fill,'black corners',black,flush=True)
 put(p,'file-local-options/panscan',.35)
 assert abs(float(get(p,'panscan'))-.35)<1e-6
 print('PASS precise fill restoration',flush=True)
 command(p,'loadfile',str(fixture))
 until=time.monotonic()+10
 while time.monotonic()<until:
  event=m.mpv_wait_event(p,.01).contents
  if m.mpv_render_context_update(context)&1:render(400,712)
  if event.event_id==21:break
 assert abs(float(get(p,'panscan')))<1e-6,get(p,'panscan')
 print('PASS temporary file-local fill resets on new media',flush=True)
finally:
 m.mpv_render_context_free(context);m.mpv_terminate_destroy(p)
