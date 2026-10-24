"""Check hook ordering/file-local geometry on the exact installed libmpv.

No window, network input or audio output is opened. Native production-method
integration is covered by run.sh; this probe checks the engine API assumptions.
"""
import ctypes as C
import json
from pathlib import Path
import re
import subprocess
import sys
import time

out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
library = Path(sys.argv[2] if len(sys.argv) > 2 else "/Applications/LYINA.app/Contents/Frameworks/libmpv.2.dylib")
repo = Path(__file__).resolve().parents[3]
source = (repo / "iina/TrackVideoProcessing.swift").read_text()
option_names = re.findall(r'"([a-z-]+)"', source.split("static let optionNames = [", 1)[1].split("]", 1)[0])
for name, size in [("a", "3840x2160"), ("b", "1080x1920")]:
    path = out / (name + ".mkv")
    if not path.exists():
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                        f"color=c=gray:s={size}:r=2:d=2", "-c:v", "ffv1", "-y", str(path)], check=True)
m = C.CDLL(str(library))
class Event(C.Structure):
    _fields_ = [("event_id", C.c_int), ("error", C.c_int), ("reply_userdata", C.c_ulonglong), ("data", C.c_void_p)]
class Hook(C.Structure):
    _fields_ = [("name", C.c_char_p), ("id", C.c_ulonglong)]
for name, args, result in [
    ("mpv_create", [], C.c_void_p),
    ("mpv_set_option_string", [C.c_void_p,C.c_char_p,C.c_char_p], C.c_int),
    ("mpv_initialize", [C.c_void_p], C.c_int),
    ("mpv_command", [C.c_void_p,C.POINTER(C.c_char_p)], C.c_int),
    ("mpv_set_property_string", [C.c_void_p,C.c_char_p,C.c_char_p], C.c_int),
    ("mpv_get_property_string", [C.c_void_p,C.c_char_p], C.c_void_p),
    ("mpv_wait_event", [C.c_void_p,C.c_double], C.POINTER(Event)),
    ("mpv_hook_add", [C.c_void_p,C.c_ulonglong,C.c_char_p,C.c_int], C.c_int),
    ("mpv_hook_continue", [C.c_void_p,C.c_ulonglong], C.c_int),
    ("mpv_free", [C.c_void_p], None), ("mpv_terminate_destroy", [C.c_void_p], None),
]:
    fn = getattr(m,name); fn.argtypes = args; fn.restype = result
p = m.mpv_create()
assert p
def get(name):
    value = m.mpv_get_property_string(p,name.encode())
    if not value: return None
    result = C.string_at(value).decode(); m.mpv_free(value); return result
def setp(name, value):
    result = m.mpv_set_property_string(p,name.encode(),str(value).encode())
    assert result >= 0, (name,value,result)
def command(*args):
    value = (C.c_char_p*(len(args)+1))(*[str(a).encode() for a in args],None)
    result = m.mpv_command(p,value)
    assert result >= 0, (args,result)
for name,value in {"config":"no","load-scripts":"no","vo":"null","ao":"null","hwdec":"no",
                   "pause":"yes","idle":"yes","keep-open":"yes","terminal":"no",
                   "watch-later-directory":str(out/"watch-later"),"resume-playback":"yes",
                   "watch-later-options":"video-aspect-override,video-rotate,vf,video-zoom"}.items():
    assert m.mpv_set_option_string(p,name.encode(),value.encode()) >= 0, name
assert m.mpv_initialize(p) >= 0
for index,name in enumerate(["on_load","on_preloaded","on_unload"],1):
    assert m.mpv_hook_add(p,index,name.encode(),0) >= 0
defaults = {name:get(name) for name in option_names}
assert all(v is not None for v in defaults.values()), defaults
saved = {}
current = None
loaded = False
trace = []
checks = 0
def check(value, text):
    global checks
    assert value, (text,{n:get(n) for n in ["path","vf","video-aspect-override","video-rotate"]})
    checks += 1; print("PASS:",text,flush=True)
def apply(value):
    for name,setting in value.items():
        if setting is not None: setp("file-local-options/"+name,setting)
def pump(until=None):
    global current,loaded
    end = time.monotonic()+20
    while time.monotonic()<end:
        event = m.mpv_wait_event(p,0.05).contents
        if event.event_id == 25:
            hook = C.cast(event.data,C.POINTER(Hook)).contents
            name = hook.name.decode(); trace.append([name,get("path")])
            if name == "on_unload":
                if loaded:
                    saved[current] = {n:get(n) for n in option_names+["vf"]}
                loaded = False
            elif name == "on_load":
                current = get("path"); apply(dict(defaults,vf=""))
            elif name == "on_preloaded" and current in saved:
                apply(saved[current])
            assert m.mpv_hook_continue(p,hook.id) >= 0
        elif event.event_id == 8:
            loaded = True
        if event.event_id == until: return
    raise TimeoutError((until,trace[-8:]))
def load(name):
    command("loadfile",str(out/(name+".mkv")))
    pump(21)
try:
    load("a")
    setp("video-aspect-override","4:3"); setp("video-rotate","90"); setp("video-zoom","0.25")
    setp("vf","@iina_crop:crop=3000:1800:100:100")
    # Drain geometry output before writing a deliberately stale disk resume state.
    command("write-watch-later-config")
    load("b")
    check(get("vf") in [None,""] and get("video-rotate") in ["0","no"], "new portrait file inherits no crop or rotation")
    check(float(get("video-aspect-override")) == float(defaults["video-aspect-override"]), "new file gets its native aspect")
    check(abs(float(saved[str(out/"a.mkv")]["video-zoom"])-0.25)<1e-6,
          "on_unload still exposes committed outgoing options")
    load("a")
    check("iina_crop" in (get("vf") or "") and get("video-rotate")=="90", "A-B-A restores the crop and rotation before decode")
    check(abs(float(get("video-aspect-override"))-4/3)<1e-5, "A-B-A restores aspect override")
    setp("vf",""); setp("video-aspect-override","-1"); setp("video-rotate","no"); setp("video-zoom","0")
    for _ in range(3):
        load("b"); load("a")
        check(get("vf") in [None,""] and abs(float(get("video-aspect-override"))+1)<1e-6,
              "session Reset overrides stale watch-later geometry on repeated returns")
    check(all(trace[i+1][0] == "on_preloaded" for i,row in enumerate(trace[:-1]) if row[0]=="on_load"),
          "load/preloaded barriers bracket every restoration")
    result = {"checks":checks,"engine":str(library),"mpv":get("mpv-version"),"hooks":trace,"saved":saved}
    (out/"engine-results.json").write_text(json.dumps(result,indent=2))
    print(f"Completed {checks} exact-engine lifecycle checks.",flush=True)
finally:
    # Hooks need a client draining them; remove that client before destruction.
    command("quit")
    end = time.monotonic()+5
    while time.monotonic()<end:
        event = m.mpv_wait_event(p,0.05).contents
        if event.event_id == 25:
            hook = C.cast(event.data,C.POINTER(Hook)).contents
            m.mpv_hook_continue(p,hook.id)
        if event.event_id == 1: break
    m.mpv_terminate_destroy(p)
