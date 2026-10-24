"""Measure actual PCM after runtime gain changes and seek with the patched engine.

Arguments: libmpv path, four-tone fixture path, output directory, Swift graphs JSON.
No output device or user's player/profile is opened.
"""
import array
import ctypes as C
import json
import math
from pathlib import Path
import sys
import time
import wave

lib, fixture, output, graph_file = map(Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=True)
graphs = json.loads(graph_file.read_text())
m = C.CDLL(str(lib.resolve()))

class Event(C.Structure):
    _fields_ = [('id', C.c_int), ('error', C.c_int), ('userdata', C.c_ulonglong), ('data', C.c_void_p)]

m.mpv_create.restype = C.c_void_p
for name, args, result in [
    ('mpv_initialize', [C.c_void_p], C.c_int),
    ('mpv_set_option_string', [C.c_void_p, C.c_char_p, C.c_char_p], C.c_int),
    ('mpv_set_property_string', [C.c_void_p, C.c_char_p, C.c_char_p], C.c_int),
    ('mpv_get_property_string', [C.c_void_p, C.c_char_p], C.c_void_p),
    ('mpv_command', [C.c_void_p, C.POINTER(C.c_char_p)], C.c_int),
    ('mpv_wait_event', [C.c_void_p, C.c_double], C.POINTER(Event)),
    ('mpv_terminate_destroy', [C.c_void_p], None), ('mpv_free', [C.c_void_p], None)
]:
    f = getattr(m, name)
    f.argtypes, f.restype = args, result

def get(p, key):
    data = m.mpv_get_property_string(p, key.encode())
    if not data:
        return None
    value = C.string_at(data).decode()
    m.mpv_free(data)
    return value

def put(p, key, value):
    result = m.mpv_set_property_string(p, key.encode(), str(value).encode())
    assert result >= 0, (key, value, result)

def command(p, *args, accept_failure=False):
    values = (C.c_char_p * (len(args) + 1))(*[v.encode() for v in args], None)
    result = m.mpv_command(p, values)
    assert accept_failure or result >= 0, (args, result)
    return result

def drain(p, duration):
    end = time.monotonic() + duration
    restarts = 0
    while time.monotonic() < end:
        event = m.mpv_wait_event(p, .01).contents
        assert event.id != 7, ('unexpected end', event.error)
        restarts += event.id == 21
    return restarts

p = m.mpv_create()
wav_path = output / 'dynamic.wav'
options = {'config':'no', 'terminal':'no', 'vo':'null', 'vid':'no',
           'audio-display':'no', 'ao':'pcm', 'ao-pcm-file':str(wav_path.resolve()),
           'audio-format':'s16', 'audio-samplerate':'48000', 'audio-channels':'stereo',
           'af':'lavfi=[arealtime]',
           'pause':'yes', 'keep-open':'yes', 'lavfi-complex':graphs['graph']}
for key, value in options.items():
    assert m.mpv_set_option_string(p, key.encode(), value.encode()) >= 0
assert m.mpv_initialize(p) >= 0
segments = []

def segment(label, ids):
    put(p, 'pause', 'no')
    drain(p, 1.2)
    put(p, 'pause', 'yes')
    drain(p, .08)
    segments.append({'label':label, 'ids':ids, 'end_bytes':wav_path.stat().st_size})

def gains(ids):
    command(p, 'lavfi-complex-command', graphs['target'], 'weights',
            ' '.join('1' if i in ids else '0' for i in range(1, 5)))

try:
    command(p, 'loadfile', str(fixture.resolve()))
    end = time.monotonic() + 10
    while time.monotonic() < end:
        if m.mpv_wait_event(p, .05).contents.id == 8:
            break
    else:
        raise AssertionError('file-loaded timeout')
    drain(p, .2)
    for ids in [[1], [1,2], [1,2,3], [1], [2,4], [], [4]]:
        gains(ids)
        segment('gains-' + ''.join(map(str, ids)), ids)
        assert get(p, 'lavfi-complex') == graphs['graph']
    command(p, 'seek', '12', 'absolute+exact')
    drain(p, .25)
    segment('selection-survives-seek', [4])
    command(p, 'seek', '5', 'absolute+exact')
    gains([1,3])  # Also works while the graph is awaiting frames after seek.
    drain(p, .25)
    segment('command-immediately-after-seek', [1,3])
    assert command(p, 'lavfi-complex-command', 'missing_filter', 'weights', '1', accept_failure=True) < 0
    segment('rejected-command-preserves-sound', [1,3])
    for i in range(100):
        gains([1] if i % 2 == 0 else [2,4])
    assert drain(p, .1) == 0
    segment('rapid-selection-last-command-wins', [2,4])
    assert get(p, 'lavfi-complex') == graphs['graph']
    print('PASS paused rapid commands preserve the running graph', flush=True)
finally:
    m.mpv_terminate_destroy(p)

with wave.open(str(wav_path), 'rb') as wav:
    assert wav.getsampwidth() == 2 and wav.getnchannels() == 2 and wav.getframerate() == 48000
    samples = array.array('h', wav.readframes(wav.getnframes()))[::2]
results = []
for segment in segments:
    end = min(len(samples), (segment['end_bytes'] - 44) // 4 - 1000)
    window = samples[end-9600:end]
    assert len(window) == 9600
    amplitudes = {}
    for track, frequency in enumerate([330,440,550,660], 1):
        re = sum(x * math.cos(2*math.pi*frequency*i/48000) for i,x in enumerate(window))
        im = sum(x * math.sin(2*math.pi*frequency*i/48000) for i,x in enumerate(window))
        amplitude = 2*math.hypot(re,im)/len(window)/32768
        assert (amplitude > .025 if track in segment['ids'] else amplitude < .001), (segment, track, amplitude)
        amplitudes[track] = round(amplitude, 6)
    results.append({**segment, 'amplitudes':amplitudes})
    print('PASS PCM', segment['label'], amplitudes, flush=True)
baseline = results[0]['amplitudes'][1]
assert all(abs(item['amplitudes'][1] / baseline - 1) < .03 for item in results if 1 in item['ids'])
print('PASS input gain stays constant across solo, additions and seek', flush=True)
(output / 'results.json').write_text(json.dumps(results, indent=2)+'\n')
