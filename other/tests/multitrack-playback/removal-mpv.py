"""Verify external-input detachment on the shipping libmpv with disposable media.

Usage: python3 removal-mpv.py LIBMPV MEDIA_DIRECTORY OUTPUT_JSON
No UI, personal profile or media modification; both outputs use null devices.
"""
import ctypes as C
import hashlib
import json
from pathlib import Path
import sys
import time

library, media, receipt = map(Path, sys.argv[1:])
m = C.CDLL(str(library.resolve()))
m.mpv_create.restype = C.c_void_p
class Event(C.Structure):
    _fields_ = [('id', C.c_int), ('error', C.c_int), ('userdata', C.c_ulonglong), ('data', C.c_void_p)]
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
p = m.mpv_create()
checks = []
def check(value, label):
    assert value, label
    checks.append(label)
    print('PASS:', label, flush=True)
def get(key):
    pointer = m.mpv_get_property_string(p, key.encode())
    if not pointer:
        return None
    try:
        return C.string_at(pointer).decode()
    finally:
        m.mpv_free(pointer)
def put(key, value):
    assert m.mpv_set_property_string(p, key.encode(), str(value).encode()) >= 0, (key, value)
def command(*args):
    values = (C.c_char_p * (len(args) + 1))(*[str(v).encode() for v in args], None)
    assert m.mpv_command(p, values) >= 0, args
def tracks(kind):
    return [t for t in json.loads(get('track-list')) if t['type'] == kind]
def contains(kind, identifier):
    return any(t['id'] == identifier for t in tracks(kind))
def load(path):
    command('loadfile', str(path.resolve()), 'replace')
    end = time.monotonic() + 10
    loaded = False
    while time.monotonic() < end:
        event = m.mpv_wait_event(p, .02).contents
        assert event.id != 7, ('load ended', event.error)
        if event.id == 8:
            loaded = True
        if loaded and event.id == 21:
            return
    raise AssertionError('initial playback-restart deadline')
def mix(ids):
    return ''.join(f'[aid{i}]' for i in ids) + f'amix@iina_audio_mix=inputs={len(ids)}:normalize=0:dropout_transition=0,alimiter=level=false:latency=true[ao]'
files = [media / name for name in ['base.mkv', 'external-audio.mka', 'external-video.mkv']]
before = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in files}
try:
    for key, value in {'config':'no', 'terminal':'no', 'vo':'null', 'ao':'null', 'pause':'yes', 'keep-open':'yes', 'hwdec':'no'}.items():
        assert m.mpv_set_option_string(p, key.encode(), value.encode()) >= 0
    assert m.mpv_initialize(p) >= 0
    load(media / 'base.mkv')
    source = get('path')
    command('audio-add', str((media / 'external-audio.mka').resolve()))
    external = next(t['id'] for t in tracks('audio') if t['external'])
    audio_position = float(get('time-pos'))
    put('lavfi-complex', mix([1, external]))
    command('audio-remove', external)
    check(contains('audio', external), 'mpv reports success but retains graph-connected audio: production must inspect track-list')
    put('lavfi-complex', mix([1, 2, 3, 4]))
    command('audio-remove', external)
    check(not contains('audio', external), 'disconnecting persistent input permits actual external audio removal')
    check(len(tracks('audio')) == 4, 'all four embedded audio tracks remain')
    check(abs(float(get('time-pos')) - audio_position) < 0.1, 'audio detachment preserves paused position')
    command('video-add', str((media / 'external-video.mkv').resolve()))
    video = next(t['id'] for t in tracks('video') if t['external'])
    video_position = float(get('time-pos'))
    graph = f'[vid1]format=rgba[base];[vid{video}]format=rgba[layer];[base][layer]overlay=eof_action=pass[vo]'
    put('lavfi-complex', mix([1, 2, 3, 4]) + ';' + graph)
    command('video-remove', video)
    check(contains('video', video), 'mpv also retains a video input connected to a layer graph')
    put('lavfi-complex', mix([1, 2, 3, 4]))
    put('vid', 1)
    command('video-remove', video)
    check(not contains('video', video), 'disconnecting layer permits external video removal')
    check(len(tracks('video')) == 3 and get('vid') == '1', 'native fallback video and original video tracks remain')
    check('[ao]' in get('lavfi-complex'), 'removing video retains the independent audio output')
    check(get('path') == source and get('pause') == 'yes', 'both removals retain current source and pause state')
    check(abs(float(get('time-pos')) - video_position) < 0.1, 'video detachment preserves paused position')
    put('lavfi-complex', '')
    command('audio-add', str((media / 'external-audio.mka').resolve()))
    external = next(t['id'] for t in tracks('audio') if t['external'])
    put('aid', external)
    put('aid', 4)
    command('audio-remove', external)
    check(get('aid') == '4' and not contains('audio', external), 'native solo fallback permits removal and keeps the chosen neighbour')
    after = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in files}
    check(before == after, 'all source files remain byte-for-byte unchanged')
finally:
    m.mpv_terminate_destroy(p)
receipt.write_text(json.dumps({'checks': checks, 'count':len(checks), 'source_hashes': before}, indent=2) + '\n')
