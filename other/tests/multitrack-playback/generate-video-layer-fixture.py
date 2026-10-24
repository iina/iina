"""Small alpha-capable MKV: front red at 50%, opaque green, opaque blue.
Top-to-bottom stream order matches the sidebar's front-to-back order.
"""
from pathlib import Path
import subprocess, sys
output = Path(sys.argv[1]).expanduser().resolve()
output.parent.mkdir(parents=True, exist_ok=True)
inputs = [
    'color=c=black@0:s=320x180:r=10:d=30,format=rgba,drawbox=x=20:y=20:w=80:h=80:color=red@0.5:t=fill:replace=1',
    'color=c=black@0:s=320x180:r=10:d=30,format=rgba,drawbox=x=60:y=60:w=80:h=80:color=lime@1:t=fill:replace=1',
    'color=c=blue:s=320x180:r=10:d=30,format=rgba',
    'sine=frequency=330:duration=30', 'sine=frequency=660:duration=30',
]
command = ['ffmpeg', '-v', 'error', '-n']
for source in inputs: command += ['-f', 'lavfi', '-i', source]
for source in ['0:v','1:v','2:v','3:a','4:a']: command += ['-map',source]
command += ['-c:v','ffv1','-pix_fmt','bgra','-c:a','pcm_s16le']
for index,title in enumerate(['Front - translucent red','Middle - green','Back - blue']):
    command += [f'-metadata:s:v:{index}',f'title={title}']
subprocess.run(command + [str(output)],check=True)
print(output)
