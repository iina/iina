// Install only in the uniquely isolated Restart QA profile.
// This uses the existing player API, not production instrumentation or polling.
const token = Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 9);
const socket = '/tmp/iina-restart-qa-' + token + '.sock';
iina.mpv.set('input-ipc-server', socket);
function snapshot(reason) {
  const loaded = iina.core.window.loaded;
  const state = {
    token, socket, reason, timestamp: Date.now(),
    url: iina.core.status.url,
    path: iina.mpv.getString('path'),
    position: iina.mpv.getNumber('time-pos'),
    paused: iina.mpv.getFlag('pause'),
    volume: iina.mpv.getNumber('volume'),
    muted: iina.mpv.getFlag('mute'),
    speed: iina.mpv.getNumber('speed'),
    playlist: iina.mpv.getNative('playlist'),
    frame: loaded ? iina.core.window.frame : null,
    miniaturized: loaded ? iina.core.window.miniaturized : null,
    fullscreen: loaded ? iina.core.window.fullscreen : null,
    pip: loaded ? iina.core.window.pip : null,
    appearance: iina.appearance ? iina.appearance.getTheme() : null
  };
  iina.file.write('@data/' + token + '.json', JSON.stringify(state));
  iina.console.log('RESTART_SESSION_QA ' + JSON.stringify(state));
}
for (const event of ['iina.window-loaded', 'iina.file-loaded', 'iina.window-moved',
                     'iina.window-resized', 'iina.music-mode.changed', 'iina.pip.changed',
                     'mpv.playback-restart', 'mpv.pause.changed',
                     'mpv.user-data/restart-session-qa-probe.changed']) {
  iina.event.on(event, () => snapshot(event));
}
iina.menu.addItem(iina.menu.item('Restart QA — Snapshot', () => snapshot('menu')));
snapshot('initialized');
