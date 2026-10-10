// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import SwiftUI
import UniformTypeIdentifiers

struct PlaylistPanelView: View {
    @ObservedObject var model: PlayerModel
    let addFiles: () -> Void
    @State private var showChapters = false
    @State private var editing: EditMode = .inactive
    @State private var showFolder = false
    @State private var showLibrary = false
    @State private var saving = false
    @State private var playlistName = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("Content", selection: $showChapters) {
                Text("Playlist").tag(false); Text("Chapters").tag(true)
            }.pickerStyle(.segmented).padding(16)
            if !showChapters {
                HStack {
                    Button(editing.isEditing ? "Done" : "Edit") { editing = editing.isEditing ? .inactive : .active }
                        .frame(minWidth: 44, minHeight: 44)
                    Spacer()
                    Button { saving = true } label: {
                        Image(systemName: "square.and.arrow.down").frame(width: 44, height: 44)
                    }.accessibilityLabel("Save playlist").accessibilityIdentifier("savePlaylistButton")
                        .disabled(model.playlist.isEmpty)
                    Button { showLibrary = true } label: {
                        Image(systemName: "list.bullet.rectangle").frame(width: 44, height: 44)
                    }.accessibilityLabel("Saved playlists").accessibilityIdentifier("savedPlaylistsButton")
                    Menu {
                        Button("Open Folder…", systemImage: "folder") { showFolder = true }
                        Button("Sort by Episode / Name", systemImage: "arrow.up.arrow.down", action: model.sortPlaylist)
                        Button("Shuffle", systemImage: "shuffle", action: model.shufflePlaylist)
                    } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel("Playlist actions")
                    .accessibilityIdentifier("playlistActionsMenu")
                }.padding(.horizontal, 18)
            }
            if model.readingPlaylist { ProgressView("Reading playlist…").padding(8) }
            List {
                if showChapters {
                    if model.chapters.isEmpty { Text("No chapters in this media.").foregroundStyle(.secondary) }
                    ForEach(model.chapters) { chapter in
                        Button { model.seek(to: chapter.time) } label: {
                            HStack { Text(chapter.title); Spacer(); Text(playbackTime(chapter.time)).font(.caption.monospacedDigit()) }
                        }.frame(minHeight: 44)
                    }
                } else {
                    if model.playlist.isEmpty { Text("Open files or a folder to build a playlist.").foregroundStyle(.secondary) }
                    ForEach(model.playlist) { entry in
                        Button { model.play(entry.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: entry.id == model.currentID ? "play.fill" : "doc").frame(width: 18)
                                Text(entry.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            }.foregroundStyle(.primary).padding(.vertical, 6)
                        }
                        .listRowBackground(entry.id == model.currentID ? Color.white.opacity(0.07) : .clear)
                        .contextMenu {
                            Button("Remove from Playlist", role: .destructive) {
                                if let index = model.playlist.firstIndex(where: { $0.id == entry.id }) {
                                    model.removePlaylist(at: IndexSet(integer: index))
                                }
                            }
                        }
                    }
                    .onMove(perform: model.movePlaylist)
                    .onDelete(perform: model.removePlaylist)
                }
            }.listStyle(.plain).scrollContentBackground(.hidden).environment(\.editMode, $editing)
            Divider()
            HStack {
                Button("Add Files", systemImage: "plus", action: addFiles)
                Spacer(); Text("\(model.playlist.count) items").font(.caption).foregroundStyle(.secondary)
            }.font(.callout).frame(minHeight: 44).padding(.horizontal, 18).padding(.vertical, 6)
        }
        .sheet(isPresented: $showFolder) {
            FolderPicker { url in
                showFolder = false
                if let url { Task { await model.openFolder(url) } }
            }
        }
        .sheet(isPresented: $showLibrary) { SavedPlaylistsView(model: model) }
        .alert("Save Playlist", isPresented: $saving) {
            TextField("Playlist name", text: $playlistName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                let name = playlistName
                playlistName = ""
                Task { await model.savePlaylist(named: name) }
            }
        } message: { Text("Files stay in their original locations. IINA remembers access to the selected files and folders.") }
    }
}

private struct SavedPlaylistsView: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.savedPlaylists.isEmpty { Text("No saved playlists.").foregroundStyle(.secondary) }
                ForEach(model.savedPlaylists) { value in
                    Button {
                        Task { await model.loadPlaylist(value); if model.failure == nil { dismiss() } }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(value.name).foregroundStyle(.primary)
                            Text("\(value.media.count) items · \(value.savedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }.disabled(model.readingPlaylist)
                }.onDelete { offsets in
                    let values = offsets.map { model.savedPlaylists[$0] }
                    Task { for value in values { await model.deleteSavedPlaylist(value) } }
                }
            }
            .navigationTitle("Saved Playlists")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await model.refreshSavedPlaylists() }
        }
    }
}

private struct FolderPicker: UIViewControllerRepresentable {
    let selected: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) { }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let selected: (URL?) -> Void
        init(selected: @escaping (URL?) -> Void) { self.selected = selected }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { selected(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { selected(nil) }
    }
}

struct RepeatToolsMenu: View {
    @ObservedObject var model: PlayerModel
    var titled = false
    var body: some View {
        Menu {
            Picker("Repeat", selection: $model.repeatMode) {
                ForEach(RepeatMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Divider()
            Button(model.loopStart.map { "Set A again (\(playbackTime($0)))" } ?? "Set Loop Point A", action: model.markLoopStart)
            Button(model.loopEnd.map { "Set B again (\(playbackTime($0)))" } ?? "Set Loop Point B", action: model.markLoopEnd)
                .disabled(model.loopStart == nil)
            Button("Clear A–B Loop", action: model.clearLoop).disabled(model.loopStart == nil)
            Divider()
            Button("Jump to Time…", systemImage: "clock") { model.showingJumpToTime = true }
            Button("Previous Frame", systemImage: "backward.frame") { model.stepFrame(forward: false) }
                .disabled(!model.canStepBackward || model.loading || model.videoID == "no")
            Button("Next Frame", systemImage: "forward.frame") { model.stepFrame(forward: true) }
                .disabled(!model.canStepForward || model.loading || model.videoID == "no")
            Button("Capture Frame…", systemImage: "camera", action: model.captureFrame)
                .disabled(model.videoTracks.isEmpty || model.capturingFrame || model.loading || model.videoID == "no")
        } label: {
            if titled { Label("Repeat and Playback Tools", systemImage: "repeat") }
            else {
                Image(systemName: model.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(model.repeatMode != .off || model.loopEnd != nil ? .blue : .primary)
                    .frame(width: 44, height: 44)
            }
        }
        .accessibilityLabel("Repeat and playback tools")
        .accessibilityIdentifier(titled ? "fileMenuPlaybackTools" : "playbackToolsMenu")
        .disabled(!model.hasMedia || model.duration <= 0)
    }
}

struct JumpToTimeView: View {
    @ObservedObject var model: PlayerModel
    @State private var text = ""
    @State private var validationMessage = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Position") {
                    TextField("HH:MM:SS or seconds", text: $text).keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("jumpTimestamp").onSubmit(apply)
                    Text("Current \(playbackTime(model.position)) · Duration \(playbackTime(model.duration))")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !validationMessage.isEmpty { Text(validationMessage).font(.footnote).foregroundStyle(.red) }
                }
            }.navigationTitle("Jump to Time")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Jump", action: apply) }
                }
                .onAppear { text = playbackTime(model.position) }
        }.presentationDetents([.medium])
    }
    private func apply() {
        if let target = PlaybackTimestamp.parse(text), model.duration > 0, target <= model.duration {
            model.seek(to: target); dismiss()
        } else { validationMessage = "Enter seconds, MM:SS, or HH:MM:SS between 0 and \(playbackTime(model.duration))." }
    }
}

struct FrameCaptureView: View {
    let frame: CapturedFrame
    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Image(uiImage: frame.image).resizable().scaledToFit().frame(maxHeight: .infinity)
                Text("\(playbackTime(frame.time)) · \(Int(frame.image.size.width)) × \(Int(frame.image.size.height))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button("Save or Share", systemImage: "square.and.arrow.up") { sharing = true }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }.padding(20).navigationTitle("Captured Frame")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $sharing) { FrameShareView(image: frame.image) }
        }
    }
}

private struct FrameShareView: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

struct ControlSettingsSections: View {
    @ObservedObject var model: PlayerModel
    private var preferences: ControlPreferences { model.controlPreferences }
    var body: some View {
        Section("Touch controls") {
            Stepper("Seek interval: \(Int(preferences.seekSeconds)) seconds", value: binding(\.seekSeconds), in: 1...120, step: 1)
            Toggle("Swipe to seek", isOn: binding(\.swipeEnabled))
            Toggle("Hold to change speed", isOn: binding(\.holdEnabled))
            Picker("Hold speed", selection: binding(\.holdSpeed)) {
                ForEach([0.5, 1, 1.5, 2, 3, 4, 8], id: \.self) { Text("\($0.formatted())×").tag($0) }
            }.disabled(!preferences.holdEnabled)
        }
        Section("Controls and panels") {
            Toggle("Keep controls visible", isOn: binding(\.keepControlsVisible))
            Toggle("Dock playback controls", isOn: binding(\.dockControls))
            Toggle("Dock sidebar beside video", isOn: binding(\.dockSidebar))
            VStack(alignment: .leading) {
                Text("Sidebar width: \(Int(preferences.sidebarWidth)) points")
                Slider(value: binding(\.sidebarWidth), in: 280...520, step: 1).accessibilityLabel("Sidebar width")
            }
        }
        Section("Seek previews") {
            Toggle("Preview Files / network media", isOn: binding(\.allowRemotePreviews))
            Text("Previews use small cached images. External documents may be on SMB or iCloud; enabling previews adds reads while scrubbing.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        Section("Keyboard shortcuts") {
            ForEach(PlayerControlAction.allCases) { action in
                Picker(action.rawValue, selection: Binding(get: { preferences.shortcut(for: action) }, set: { shortcut in
                    var value = preferences; value.shortcuts[action.rawValue] = shortcut
                    model.updateControlPreferences(value)
                })) {
                    ForEach(PlayerShortcut.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            Button("Reset Controls and Layout") { model.updateControlPreferences(ControlPreferences()) }
        }
    }
    private func binding<Value>(_ path: WritableKeyPath<ControlPreferences, Value>) -> Binding<Value> {
        Binding(get: { preferences[keyPath: path] }, set: { value in
            var updated = preferences; updated[keyPath: path] = value; model.updateControlPreferences(updated)
        })
    }
}

struct PlaybackDiagnosticsView: View {
    @ObservedObject var model: PlayerModel
    private var value: PlaybackDiagnostics { model.diagnostics }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Playback Diagnostics", systemImage: "chart.bar").font(.callout.weight(.semibold))
            row("Status", model.loading ? "Opening" : model.buffering ? "Buffering" : model.paused ? "Paused" : "Playing")
            row("Buffer ahead", value.bufferedSeconds.map {
                "\($0.formatted(.number.precision(.fractionLength(1)))) media s (\(($0 / model.speed).formatted(.number.precision(.fractionLength(1)))) s at \(model.speed.formatted())×)"
            } ?? "Unavailable")
            row("Cache in memory", value.cacheBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? "Unavailable")
            row("Dropped video frames", value.droppedFrames.map { String(Int($0)) } ?? "Unavailable")
            if let dropped = value.decoderDroppedFrames { row("Decoder drops", String(Int(dropped))) }
            if let stalls = value.stalls { row("Recorded stalls", String(Int(stalls))) }
            if let bitrate = value.observedBitrate { row("Observed transfer rate", "\((bitrate / 1_000_000).formatted(.number.precision(.fractionLength(2)))) Mb/s") }
            if let size = value.renderedSize, size.width > 0 { row("IINA rendered output", "\(Int(size.width))×\(Int(size.height))") }
            if let milliseconds = value.renderingMilliseconds { row("Last frame rendering", "\(milliseconds.formatted(.number.precision(.fractionLength(1)))) ms") }
            if let frames = value.renderedFrames { row("Rendered frames", String(frames)) }
            if let drops = value.rendererDroppedFrames { row("IINA renderer drops", String(drops)) }
            if !value.waitingReason.isEmpty { row("Waiting reason", value.waitingReason) }
            Text("Unavailable metrics are not exposed by this engine or source. Files / SMB transfer rates may be hidden by the file provider.")
                .font(.caption).foregroundStyle(.secondary)
        }.accessibilityIdentifier("playbackDiagnostics")
    }
    private func row(_ name: String, _ text: String) -> some View {
        LabeledContent(name) { Text(text).multilineTextAlignment(.trailing) }.font(.caption).foregroundStyle(.secondary)
    }
}

struct SeekThumbnailView: View {
    @ObservedObject var preview: SeekPreview
    var body: some View {
        VStack(spacing: 5) {
            if let image = preview.image {
                Image(uiImage: image).resizable().scaledToFit().frame(width: 160, height: 90)
                Text(playbackTime(preview.time)).font(.caption.monospacedDigit())
            } else if !preview.message.isEmpty {
                Text(preview.message).font(.caption2).multilineTextAlignment(.center).frame(width: 180)
            } else { ProgressView().frame(width: 160, height: 60) }
        }.padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityIdentifier("seekPreview")
    }
}
