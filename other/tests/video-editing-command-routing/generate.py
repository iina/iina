from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys

repo, tests, output = map(Path, sys.argv[1:])
runner = repo / 'other/tests/custom-crop/run.sh'
env = os.environ.copy()
env['CUSTOM_CROP_OUTPUT_DIR'] = str(output / 'crop-generator')
subprocess.run(['bash', '-c', runner.read_text().split('xcrun swiftc', 1)[0], str(runner)], env=env, check=True)
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

source = source.replace(extract(source, '  enum State {'), '  typealias State = PlayerState', 1)
source = source.replace('enum Level { case warning }', 'enum Level { case warning, error }')
source = source.replace('enum OSD { case crop(String) }', 'enum OSD { case crop(String), screenshot, showTime(Double) }')
source = source.replace('  class Info {', '  class Info {\n    var progress: Double = 0\n    var currentURL: URL?\n    var isNetworkResource = false')
source = source.replace('func getInt(_ property: String) -> Int { Int(property.hasSuffix("/w") ? size.width : size.height) }',
    'func getInt(_ property: String) -> Int { if property == "playlist-pos" { _ = engine.property(property); return Int(engine.values[property] ?? "0") ?? 0 }; return Int(property.hasSuffix("/w") ? size.width : size.height) }')
source = source.replace('class MainWindowController {', 'class MainWindowController: DispatchBase {')
source = source.replace('  let player = PlayerFixture()', '  private let playerStorage = PlayerFixture()\n  override var player: PlayerFixture { playerStorage }')
source = source.replace('init(size: NSSize = NSSize(width: 960, height: 620)) {',
    'init(size: NSSize = NSSize(width: 960, height: 620)) {\n    super.init()')

player = (repo / 'iina/PlayerWindowController.swift').read_text()
main = (repo / 'iina/MainWindowController.swift').read_text()
message = (repo / 'iina/OSDMessage.swift').read_text()
js = (repo / 'iina/JavascriptAPIMpv.swift').read_text()
menu = (repo / 'iina/MainMenuActions.swift').read_text()
pieces = {
    'dispatcher': extract(player, '  func handleKeyBinding('),
    'mainDispatcher': extract(main, '  override func handleKeyBinding('),
    'menuValidation': extract(menu, '  func validateMenuItem('),
    'menuFilter': extract(menu, '  private func menuToggleFilterString('),
}
source = source.replace('class MainWindowController: DispatchBase {',
    'class MainWindowController: DispatchBase {\n' + pieces['mainDispatcher'])
for marker in ['  private var canAccessMPV:', '  @objc func getFlag(', '  @objc func getNumber(',
               '  @objc func getString(', '  @objc func getNative(', '  @objc func set(',
               '  @objc func command(', '  @objc func addHook(']:
    pieces[marker] = extract(js, marker)

support = (tests / 'Support.swift').read_text()
support = support.replace('// PRODUCTION_DISPATCH', pieces['dispatcher'])
support = support.replace('// PRODUCTION_JS', '\n'.join(value for key, value in pieces.items() if key.startswith('  ')))
support = support.replace('// PRODUCTION_MENU', pieces['menuValidation'] + '\n' + pieces['menuFilter'])
policy = '\n'.join(extract(message, marker) for marker in [
    'enum OSDFeedbackOrigin {', 'enum OSDFeedbackValue:', 'final class OSDFeedbackOrigins {', 'enum OSDCommandRouting {'])
source += '\n' + (repo / 'iina/IINACommand.swift').read_text()
source += '\n' + (repo / 'iina/PlayerState.swift').read_text()
source += '\n' + policy + '\n' + support + '\n' + (tests / 'main.swift').read_text()
(output / 'main.swift').write_text(source)
(output / 'inputs.json').write_text(json.dumps({key: hashlib.sha256(value.encode()).hexdigest()
    for key, value in pieces.items()}, indent=2) + '\n')
