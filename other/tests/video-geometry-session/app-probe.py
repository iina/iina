"""Exercise the isolated full app through its local MPV IPC API."""
from pathlib import Path
import json
import socket
import sys
import time

out = Path(sys.argv[1]).resolve()
lab_file = sys.argv[2] if len(sys.argv)>2 else "lab.json"
lab = json.loads((out/lab_file).read_text())
sock = socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
deadline = time.monotonic()+15
while True:
    try:
        sock.connect(lab["ipc"]); break
    except (FileNotFoundError,ConnectionRefusedError):
        if time.monotonic()>deadline: raise
        time.sleep(0.05)
sock.settimeout(5)
stream = sock.makefile("rwb",buffering=0)
request = 0
checks = 0
samples = []
def cmd(*args):
    global request
    request += 1
    stream.write((json.dumps({"command":args,"request_id":request})+"\n").encode())
    while True:
        response = json.loads(stream.readline())
        if response.get("request_id") == request:
            if response.get("error") != "success": raise RuntimeError((args,response))
            return response.get("data")
def get(name): return cmd("get_property",name)
def setp(name,value): return cmd("set_property",name,value)
def sample():
    dims = get("osd-dimensions")
    return {"path":get("path"),"vf":get("vf"),"aspect":get("video-aspect-override"),
            "rotation":get("video-rotate"),"width":dims["w"],"height":dims["h"],"fullscreen":get("fullscreen")}
def wait_for(predicate,description,timeout=12):
    end=time.monotonic()+timeout
    previous=None; stable=0
    while time.monotonic()<end:
        try: value=sample()
        except RuntimeError:
            time.sleep(0.05); continue
        if predicate(value) and value==previous:
            stable+=1
            if stable>=3:
                samples.append(dict(case=description,**value)); return value
        else: stable=0
        previous=value
        time.sleep(0.05)
    raise TimeoutError((description,previous))
def check(value,description):
    global checks
    assert value,description
    checks+=1; print("PASS:",description,flush=True)
def area(s): return s["width"]*s["height"]
def small(s): return 0<s["width"]<2000 and 0<s["height"]<2000
first=wait_for(small,"initial 500pt 4K file")
base_area=area(first)
setp("vf","@iina_crop:crop=3000:1600:100:100")
setp("video-aspect-override","4:3"); setp("video-rotate",90)
edited=wait_for(lambda s: small(s) and s["rotation"]==90 and abs(s["aspect"]-4/3)<0.0001,
                "edited A")
check(small(edited),"actual app crop/aspect/rotation retains a compact window")
for i in range(2):
    cmd("loadfile",str(out/"engine/b.mkv"))
    other=wait_for(lambda s:s["path"].endswith("/b.mkv") and not s["vf"] and s["aspect"]<0 and s["rotation"]==0 and small(s),"unvisited/reset B")
    check(not other["vf"] and other["aspect"]<0,"actual next file has no leaked crop or aspect override")
    cmd("loadfile",str(out/"engine/a.mkv"))
    restored=wait_for(lambda s:s["path"].endswith("/a.mkv") and s["rotation"]==90 and abs(s["aspect"]-4/3)<0.0001 and bool(s["vf"]) and small(s),"restored A")
    check(restored["vf"]==edited["vf"],"actual A-B-A restores the exact crop")
    check(abs(area(restored)-area(edited))<base_area*0.04,"actual round trips preserve the window area")
setp("vf",""); setp("video-aspect-override",-1); setp("video-rotate",0)
reset=wait_for(lambda s: small(s) and not s["vf"] and s["aspect"]<0 and s["rotation"]==0,"reset A")
cmd("loadfile",str(out/"engine/b.mkv"),"append")
cmd("playlist-next","force")
wait_for(lambda s:s["path"].endswith("/b.mkv") and small(s),"playlist next")
cmd("playlist-prev","force")
after_playlist=wait_for(lambda s:s["path"].endswith("/a.mkv") and not s["vf"] and s["aspect"]<0 and small(s),"playlist previous")
check(not after_playlist["vf"] and abs(area(after_playlist)-area(reset))<base_area*0.04,
      "actual playlist next/previous retains Reset and the window scale")
if "--skip-fullscreen" not in sys.argv[3:]:
    setp("fullscreen",True)
    wait_for(lambda s:s["fullscreen"] and area(s)>base_area*3,"native fullscreen entered")
    cmd("playlist-next","force")
    wait_for(lambda s:s["path"].endswith("/b.mkv") and s["fullscreen"],"portrait file while fullscreen")
    setp("fullscreen",False)
    returned=wait_for(lambda s: not s["fullscreen"] and small(s),"native fullscreen exit")
    check(small(returned),"actual fullscreen exit returns to the compact window after switching files")
    check(abs(returned["width"]/returned["height"]-9/16)<0.03,
          "native fullscreen exit applies the new portrait aspect instead of AppKit's old frame")
(out/(Path(lab_file).stem+"-app-results.json")).write_text(json.dumps({"checks":checks,"lab":lab,"samples":samples},indent=2))
print(f"Completed {checks} isolated full-app checks.",flush=True)
