#!/bin/bash
set -eu
test_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$test_dir/../../.." && pwd)"
output_dir="${MULTITRACK_OUTPUT_DIR:-$repo_dir/build/multitrack-playback/native}"
mkdir -p "$output_dir/module-cache"
python3 - "$repo_dir" "$test_dir" "$output_dir" <<'PY'
from pathlib import Path
import sys, os
repo,tests,out=map(Path,sys.argv[1:])
def extract(text,marker):
 start=text.index(marker);end=text.index('{',start)+1;depth=1
 while depth:
  if text[end]=='{':depth+=1
  elif text[end]=='}':depth-=1
  end+=1
 return text[start:end]
player=(repo/'iina/PlayerCore.swift').read_text()
settings=(repo/'iina/TrackSettings.swift').read_text()
session_restore=extract(player,'  private func restoreVideoTrackGeometryForCurrentMedia(')
support=(tests/'Support.swift').read_text().replace('// PRODUCTION_CORE','\n'.join(extract(player,m) for m in ['  private func supportsTrackAudioCommands(', '  private func audioMixerInputsAreCompatible(', '  private func prepareAudioMixer(', '  private func clearTrackGraphForNewFile(', '  func setAudioTracks(', '  func setVideoTracks(', '  private func applyTrackSelection(', '  func refreshTrackProcessing(', '  func refreshTrackAudioEQ(', '  func neutralizeTrackAudioEQ(', '  private func sendTrackAudioEQCommands(', '  private func reconcileTrackGraph(', '  func cycleVideoTrack(', '  func cycleAudioTrack(', '  func setTrack(', '  func removeExternalTrack(', '  func aidChanged(', '  func vidChanged('])).replace('// PRODUCTION_ACTIVE_IDS',extract((repo/'iina/PlaybackInfo.swift').read_text(),'  func activeTrackIDs('))
support=support.replace('// PRODUCTION_ORDERED_TRACKS',extract((repo/'iina/PlaybackInfo.swift').read_text(),'  func orderedTrackList('))
support=support.replace('// PRODUCTION_SCOPE_CROP','@discardableResult\n'+extract(settings,'  func finishScopedCustomCrop(')+'\n'+extract(settings,'  private func prepareScopedCropPreview('))
support=support.replace('  func prepareMixer() {',extract(player,'  func loadExternalAudioFile(')+'\n'+extract(player,'  func detachSavedVideoLUT(')+'\n  func prepareMixer() {')
support=support.replace('  func restoreVideoSession() {',session_restore+'\n  func restoreVideoSession() {')
support=support.replace('// PRODUCTION_SCOPE_RESET',extract((repo/'iina/TrackSettings.swift').read_text(),'  func resetTrackSettings('))
sidebar=(repo/'iina/SidebarPane.swift').read_text()
support=support.replace('// PRODUCTION_SIDEBAR_SCROLL',extract(sidebar,'protocol SidebarPane:')+'\n'+extract(sidebar,'class SidebarSectionScrollView:'))
popup=(repo/'iina/TrackSettings.swift').read_text().split('extension PlayerCore {',1)[0]
support+='\n'+extract((repo/'iina/UIHelper.swift').read_text(),'enum CircularActionButtonStyle {')
(out/'main.swift').write_text(support+'\n'+popup+'\n'+(repo/'iina/ConstraintsSugar.swift').read_text()+'\n'+(repo/'iina/TrackSelectionState.swift').read_text()+'\n'+(repo/'iina/TrackAudioProcessing.swift').read_text()+'\n'+(repo/'iina/TrackVideoProcessing.swift').read_text()+'\n'+(repo/'iina/TrackProcessingState.swift').read_text()+'\n'+(repo/'iina/ResizeCursor.swift').read_text()+'\n'+(repo/'iina/SidebarTrackSelector.swift').read_text()+'\n'+('' if os.environ.get('TRACK_SETTINGS_ONLY') == '1' else (tests/'main.swift').read_text()+'\n'+(tests/'removal.swift').read_text()+'\n'+(tests/'subtitles.swift').read_text())+'\n'+(repo/'other/tests/track-processing/scope-main.swift').read_text()+'\n'+(repo/'other/tests/track-processing/popup-main.swift').read_text()+'\n'+(repo/'other/tests/track-processing/audit-main.swift').read_text())
PY
xcrun swiftc -module-cache-path "$output_dir/module-cache" "$output_dir/main.swift" -o "$output_dir/tests"
"$output_dir/tests" "$output_dir/graphs.json"
