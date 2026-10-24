"""Stage the built executable with the installed custom engine and an isolated lab."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import uuid

out = Path(sys.argv[1]).resolve()
final = "--final" in sys.argv[2:]
installed = Path("/Applications/LYINA.app")
built = out / "DerivedData/Build/Products/Release/IINA.app"
stage = out / "stage/LYINA.app"
lab = out / ("Video Geometry Final Lab.app" if final else "Video Geometry Lab.app")
if lab.exists() or (stage.exists() and not final):
    raise SystemExit("Reuse existing stage/lab; do not overwrite a running candidate.")
if not stage.exists(): shutil.copytree(installed, stage, symlinks=True)
shutil.copy2(built/"Contents/MacOS/IINA", stage/"Contents/MacOS/IINA")
subprocess.run(["codesign","--force","--sign","-","--preserve-metadata=entitlements,flags,runtime",str(stage)],check=True)
subprocess.run(["codesign","--verify","--deep","--strict",str(stage)],check=True)
engine = "Contents/Frameworks/libmpv.2.dylib"
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert digest(stage/engine) == digest(installed/engine)
shutil.copytree(stage,lab,symlinks=True)
bundle = "org.lyzmin41.video-geometry-session-20261019" + ("-final" if final else "")
info_path = lab/"Contents/Info.plist"
info = plistlib.loads(info_path.read_bytes())
name = "Video Geometry Final Lab" if final else "Video Geometry Lab"
info.update(CFBundleIdentifier=bundle,CFBundleName=name,CFBundleDisplayName=name,SUEnableAutomaticChecks=False)
info.pop("CFBundleURLTypes",None)
info_path.write_bytes(plistlib.dumps(info))
subprocess.run(["codesign","--force","--sign","-","--preserve-metadata=entitlements,flags,runtime",str(lab)],check=True)
subprocess.run(["codesign","--verify","--deep","--strict",str(lab)],check=True)
home = out/"home"
(home/"Library/Preferences").mkdir(parents=True,exist_ok=True)
(out/"tmp").mkdir(exist_ok=True)
prefs = {
    "iinaEnablePluginSystem":False,"pauseWhenOpen":True,"recordPlaybackHistory":False,
    "recordRecentFiles":False,"resumeLastPosition":False,"SUEnableAutomaticChecks":False,
    "enableLogging":True,"enableControlBarAutoHide":False,"resizeWindowTiming":0,
    "resizeWindowOption":2,"usePhysicalResolution":False,"unlockWindowAspectRatio":False,
    "autoAddFileToPlaylist":False,"autoLoadOnlineSub":False,"enableAdvancedSettings":False,
    "AppleLanguages":["en"],"enableOSC":True,"disableAnimations":True,
    "windowBehaviorWhenPip":0 if final else 1,
}
profile = home/"Library/Preferences"/(bundle+".plist")
profile.write_bytes(plistlib.dumps(prefs))
subprocess.run(["defaults","import",bundle,str(profile)],check=True)
ipc = "/tmp/lyina-geometry-"+uuid.uuid4().hex[:10]+".sock"
env = dict(os.environ,CFFIXED_USER_HOME=str(home),TMPDIR=str(out/"tmp")+"/")
log = (out/"app-stdout.log").open("w")
args = [str(lab/"Contents/MacOS/IINA"),"--mpv-input-ipc-server="+ipc,
        "--mpv-geometry=500","--mpv-hwdec=no","--mpv-volume=0",str(out/"engine/a.mkv")]
process = subprocess.Popen(args,env=env,stdout=log,stderr=subprocess.STDOUT)
receipt = {"pid":process.pid,"lab":str(lab),"stage":str(stage),"bundle":bundle,"home":str(home),"ipc":ipc,
           "executableSHA256":digest(stage/"Contents/MacOS/IINA"),"engineSHA256":digest(stage/engine)}
(out/("final-lab.json" if final else "lab.json")).write_text(json.dumps(receipt,indent=2))
print(json.dumps(receipt,indent=2))
