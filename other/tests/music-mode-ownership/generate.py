from pathlib import Path
import hashlib
import json
import subprocess
import sys

repo, tests, output = map(Path, sys.argv[1:])
# Reuse only the Custom Crop suite's production-source assembly and native doubles.
# Its test entry is removed before adding this suite's mode-transition attempts.
runner = repo / 'other/tests/custom-crop/run.sh'
generator = runner.read_text().split('xcrun swiftc', 1)[0]
import os
env = os.environ.copy()
env['CUSTOM_CROP_OUTPUT_DIR'] = str(output / 'crop-generator')
subprocess.run(['bash', '-c', generator, str(runner)], env=env, check=True)
source = (output / 'crop-generator/main.swift').read_text().split(
    'import Darwin\nsetbuf(stdout, nil)\nlet app = NSApplication.shared', 1)[0]

def extract(text, marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

core = (repo / 'iina/PlayerCore.swift').read_text()
main = (repo / 'iina/MainWindowController.swift').read_text()
entry = extract(core, '  func switchToMiniPlayer(')
exit = extract(core, '  func switchBackFromMiniPlayer(')
command = extract(main, '  override func handleIINACommand(')
source = source.replace('enum Key: String { case customCropAspectPresets }',
    '''enum Key: String { case customCropAspectPresets, useLegacyFullScreen, musicModeShowAlbumArt, musicModeShowPlaylist }
  static func bool(for key: Key) -> Bool { false }''')
source = source.replace('enum Level { case warning }', 'enum Level { case warning, verbose }')
source = source.replace(extract(source, '  enum State {'), '  typealias State = PlayerState', 1)
source = source.replace('class PlayerFixture {', '''class PlayerFixture {
  var overrideAutoSwitchToMusicMode = false
  let subsystem = "music-mode-ownership"
  let miniPlayer = MiniFixture()
  var currentController: MiniFixture { miniPlayer }
  let events = EventFixture()
  func log(_ message: String) {}
  func refreshSyncUITimer() {}
  func notifyWindowVideoSizeChanged() {}
''' + entry + '\n' + exit)
source = source.replace('class MainWindowController {', '''class MainWindowController: WindowActionBase {
  struct Fullscreen { var isFullscreen = false }
  var fsState = Fullscreen()
  var pendingShow = false
  let sidebars = SidebarFixture()
  func toggleWindowFullScreen() {}
  func menuToggleLiveText(_ sender: NSMenuItem) {}
  func updateTitle() {}
  func addVideoViewToWindow() {
    videoView.removeFromSuperview()
    videoViewContainer.addSubview(videoView)
    videoView.padding(.all(0))
  }
''' + command)
source = source.replace('init(size: NSSize = NSSize(width: 960, height: 620)) {',
    'init(size: NSSize = NSSize(width: 960, height: 620)) {\n    super.init()')
source = source.replace('struct FloatingOSCFixture { func cancelPositionAnimation() {} }',
    'struct FloatingOSCFixture { func cancelPositionAnimation() {}; func updatePosition() {} }')
source += '\n' + (repo / 'iina/IINACommand.swift').read_text()
source += '\n' + (repo / 'iina/PlayerState.swift').read_text()
source += '\n' + (tests / 'Support.swift').read_text()
source += '\n' + (tests / 'main.swift').read_text()
(output / 'main.swift').write_text(source)
(output / 'inputs.json').write_text(json.dumps({
    name: hashlib.sha256(value.encode()).hexdigest()
    for name, value in [('switchToMiniPlayer', entry), ('switchBackFromMiniPlayer', exit),
                        ('handleIINACommand', command)]
}, indent=2) + '\n')
