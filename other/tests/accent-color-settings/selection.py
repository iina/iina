from pathlib import Path
import argparse
import json
import os
import plistlib
import shutil
import subprocess

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, default=root / "build/accent-color-api-2026-10-24/settings-selector")
parser.add_argument("--module-cache", type=Path, default=root / "build/sidebar-osd-tests/module-cache")
args = parser.parse_args()
args.module_cache = args.module_cache.resolve()
if not args.module_cache.is_dir():
    raise SystemExit(f"Reuse an existing compiler cache: {args.module_cache}")
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
bundle = output / "AccentSelectorChecks.app"
executable = bundle / "Contents/MacOS/selector-probe"
executable.parent.mkdir(parents=True, exist_ok=True)
(bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
    "CFBundleIdentifier": "org.iina.tests.accent-selector",
    "CFBundleExecutable": executable.name,
    "CFBundleDevelopmentRegion": "en",
    "CFBundlePackageType": "APPL",
}))
for locale in ["Base", "en"]:
    resources = bundle / "Contents/Resources" / f"{locale}.lproj"
    resources.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(root / "iina" / f"{locale}.lproj/Localizable.strings", resources / "Localizable.strings")
command = ["xcrun", "swiftc", "-target", "arm64-apple-macos12.0",
           "-module-cache-path", str(args.module_cache),
           str(root / "iina/AppAccentColor.swift"), str(root / "iina/AccentControls.swift"),
           str(root / "iina/AccentColorSettingsItem.swift"),
           str(Path(__file__).with_name("SelectionProbe.swift")),
           "-o", str(executable)]
subprocess.run(command, check=True)
result = subprocess.run([str(executable), "-AppleLanguages", "(en)"], text=True, capture_output=True,
                        env={**os.environ, "ACCENT_SELECTOR_OUTPUT": str(output)})
log = result.stdout + result.stderr
(output / "selection-checks.log").write_text(log)
print(result.stdout + result.stderr)
assert result.returncode == 0, "Accent selector regression"
for locale, expected in [("Base", ("Default", "System Highlight")),
                         ("en", ("Default", "System Highlight"))]:
    strings = root / "iina" / f"{locale}.lproj" / "Localizable.strings"
    data = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(strings)]))
    assert data["settings.accentColorSource.items.0"] == expected[0]
    assert data["settings.accentColorSource.items.2"] == expected[1]
    assert data["settings.accentColorSource.help.2"]
    line = f"PASS {locale} labels: {expected[0]} / {expected[1]}; source tags remain 0/2"
    print(line)
    log += line + "\n"
(output / "selection-checks.log").write_text(log)
