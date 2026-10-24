"""Verify imported audio PCM with the bundled engine and production graph receipts.

Arguments: libmpv, three-video/four-tone fixture, external 770 Hz WAV,
external-audio-graphs.json from the native suite, output directory.
Uses a PCM file, never an output device or personal player profile.
"""
import array
import ctypes as C
import json
import math
from pathlib import Path
import sys
import time
import wave

lib, fixture, external, graph_file, output = map(Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=True)
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
    getattr(m, name).argtypes = args
    getattr(m, name).restype = result

def get(player, key):
    data = m.mpv_get_property_string(player, key.encode())
    if not data:
        return None
    value = C.string_at(data).decode()
    m.mpv_free(data)
    return value

def put(player, key, value):
    assert m.mpv_set_property_string(player, key.encode(), str(value).encode()) >= 0, key

def command(player, *args):
    values = (C.c_char_p * (len(args) + 1))(*[str(v).encode() for v in args], None)
    assert m.mpv_command(player, values) >= 0, args

def drain(player, duration):
    until = time.monotonic() + duration
    while time.monotonic() < until:
        event = m.mpv_wait_event(player, .01).contents
        assert event.id != 7, ('unexpected end', event.error)

results = []
for graph in json.loads(graph_file.read_text()):
    player = m.mpv_create()
    pcm = output / ('persistent.wav' if graph['persistent'] else 'mixed.wav')
    options = {'config': 'no', 'terminal': 'no', 'vo': 'null', 'demuxer': 'lavf',
               'audio-display': 'no', 'ao': 'pcm', 'ao-pcm-file': str(pcm.resolve()),
               'audio-format': 's16', 'audio-samplerate': '48000', 'audio-channels': 'stereo',
               'af': 'lavfi=[arealtime]', 'pause': 'yes', 'keep-open': 'yes',
               'log-file': str((output / (pcm.stem + '.log')).resolve()),
               'lavfi-complex': graph['before']}
    for key, value in options.items():
        assert m.mpv_set_option_string(player, key.encode(), value.encode()) >= 0, key
    assert m.mpv_initialize(player) >= 0
    segments = []
    states = []
    try:
        command(player, 'loadfile', fixture.resolve())
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if m.mpv_wait_event(player, .05).contents.id == 8:
                break
        else:
            raise AssertionError('file-loaded timeout')
        for phase in ['before', 'after']:
            if phase == 'after':
                count = int(get(player, 'track-list/count'))
                command(player, 'audio-add', external.resolve(), 'auto')
                assert int(get(player, 'track-list/count')) == count + 1
                assert get(player, 'lavfi-complex') == graph['before']
                put(player, 'lavfi-complex', graph['after'])
            put(player, 'pause', 'no')
            drain(player, 3.5)
            put(player, 'pause', 'yes')
            drain(player, .1)
            segments.append(pcm.stat().st_size)
            states.append({key: get(player, key) for key in ['time-pos', 'audio-pts', 'core-idle', 'paused-for-cache', 'pause']})
    finally:
        m.mpv_terminate_destroy(player)
    (output / (pcm.stem + '-segments.json')).write_text(json.dumps({'bytes': segments, 'states': states}))
    with wave.open(str(pcm)) as audio:
        channels, rate = audio.getnchannels(), audio.getframerate()
        data = audio.readframes(audio.getnframes())
    header = pcm.stat().st_size - len(data)
    samples = array.array('h', data)
    start = 0
    powers = []
    for end_bytes in segments:
        end = (end_bytes - header) // (2 * channels)
        mono = samples[(start + rate // 4) * channels:(end - rate // 10) * channels:channels]
        assert len(mono) > rate // 2
        power = {}
        for frequency in [330, 550, 770]:
            real = sum(value * math.cos(2 * math.pi * frequency * i / rate) for i, value in enumerate(mono))
            imag = sum(value * math.sin(2 * math.pi * frequency * i / rate) for i, value in enumerate(mono))
            power[frequency] = 2 * math.hypot(real, imag) / len(mono)
        powers.append(power)
        start = end
    assert powers[0][770] < 30, powers
    assert all(powers[1][frequency] > 100 for frequency in [330, 550, 770]), powers
    results.append({'persistent': graph['persistent'], 'tone_amplitudes': powers, 'passed': True})
(output / 'results.json').write_text(json.dumps(results, indent=2))
print('External audio activation: PCM verified for ordinary and persistent mixers.')
