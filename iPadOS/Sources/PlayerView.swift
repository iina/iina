// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import SwiftUI
import UniformTypeIdentifiers

enum SidePanel: String {
    case playlist = "Playlist", settings = "Quick Settings"
}

enum QuickSettingsTab: String, CaseIterable {
    case layout = "Layout", video = "Video", audio = "Audio", subtitles = "Subtitles"

    var symbol: String {
        switch self {
        case .layout: return "paintbrush"
        case .video: return "photo"
        case .audio: return "waveform"
        case .subtitles: return "captions.bubble"
        }
    }
}

private enum AppInfo {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
}

struct PlayerView: View {
    @StateObject private var model = PlayerModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var panel: SidePanel?
    @State private var quickTab: QuickSettingsTab = .video
    @State private var showImporter = false
    @State private var importSubtitle = false
    @State private var subtitleTarget: SubtitleTarget = .primary
    @State private var showSubtitleSearch = false
    @State private var showURL = false
    @State private var showAbout = false
    @State private var urlText = ""
    @State private var controlsVisible = true
    @State private var controlActivity = 0
    @State private var scrubbing = false
    @State private var pickingSpeed = false
    @State private var swipeFeedback: Double?
    @State private var swipeFeedbackActivity = 0
    @State private var sidebarResizeStart: Double?

    init() {}
    init(model: PlayerModel, showingVideoSettings: Bool = false) {
        _model = StateObject(wrappedValue: model)
        _panel = State(initialValue: showingVideoSettings ? .settings : nil)
    }

    var body: some View {
        GeometryReader { geometry in
            let sidebarWidth = min(CGFloat(model.controlPreferences.sidebarWidth), min(max(280, geometry.size.width - 340), geometry.size.width - 24))
            let reservedWidth = panel != nil && model.controlPreferences.dockSidebar && geometry.size.width >= 760 ? sidebarWidth : 0
            let playerWidth = geometry.size.width - reservedWidth

            ZStack(alignment: .trailing) {
                Color.black.ignoresSafeArea()
                PlayerSurface(model: model, onSingleTap: {
                    if model.hasMedia {
                        if model.controlPreferences.keepControlsVisible || model.controlPreferences.dockControls { revealControls() }
                        else { controlsVisible.toggle(); controlActivity += 1 }
                    }
                }, onDoubleTap: {
                    model.togglePause()
                    revealControls()
                }, onSeekSwipe: { seconds in
                    swipeFeedback = seconds
                    swipeFeedbackActivity += 1
                    revealControls()
                }, onControlKey: { action in
                    model.performControl(action); revealControls()
                })
                    .frame(width: playerWidth)
                    .padding(.top, model.controlPreferences.dockControls ? 48 : 0)
                    .padding(.bottom, model.controlPreferences.dockControls && !model.musicMode ? 120 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ignoresSafeArea(edges: model.controlPreferences.dockControls ? [] : .vertical)
                    .contentShape(Rectangle())
                    .onHover { hovering in if hovering { revealControls() } }

                if !model.hasMedia {
                    WelcomeView(openFiles: openMedia, openURL: { showURL = true })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.trailing, reservedWidth)
                }

                if model.hasMedia && model.musicMode {
                    MusicMiniPlayer(model: model, compact: playerWidth < 700, scrubbing: $scrubbing, pickingSpeed: $pickingSpeed,
                                    settings: { openSettings(.audio) }, playlist: { togglePanel(.playlist) },
                                    activity: revealControls)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.trailing, reservedWidth)
                }

                if model.loading || model.buffering {
                    ProgressView(model.loading ? "Opening media…" : "Buffering…")
                        .padding(22)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }

                if model.touchSpeedBoostActive || swipeFeedback != nil {
                    HStack(spacing: 10) {
                        Image(systemName: model.touchSpeedBoostActive ? "forward.fill" :
                                (swipeFeedback ?? 0) > 0 ? "goforward.10" : "gobackward.10")
                        Text(model.touchSpeedBoostActive ? "\(model.controlPreferences.holdSpeed.formatted())× speed · release to restore" :
                             (swipeFeedback ?? 0) > 0 ? "Fast forward \(Int(abs(swipeFeedback ?? 0))) seconds" : "Rewind \(Int(abs(swipeFeedback ?? 0))) seconds")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("touchPlaybackFeedback")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.trailing, reservedWidth)
                    .allowsHitTesting(false)
                }

                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    if model.hasMedia && !model.musicMode {
                        PlaybackControls(model: model, compact: playerWidth < 700,
                                         scrubbing: $scrubbing, pickingSpeed: $pickingSpeed,
                                         settings: { openSettings(.video) },
                                         playlist: { togglePanel(.playlist) }, activity: revealControls)
                            .frame(maxWidth: model.controlPreferences.dockControls ? .infinity : 680)
                            .padding(.horizontal, model.controlPreferences.dockControls ? 0 : 18)
                            .padding(.bottom, model.controlPreferences.dockControls ? 0 : 24)
                    }
                }
                .padding(.trailing, reservedWidth)
                .opacity(controlsVisible || model.controlPreferences.keepControlsVisible || model.controlPreferences.dockControls || !model.hasMedia || panel != nil ? 1 : 0)
                .allowsHitTesting(controlsVisible || model.controlPreferences.keepControlsVisible || model.controlPreferences.dockControls || !model.hasMedia || panel != nil)
                .animation(.easeInOut(duration: 0.2), value: controlsVisible)
                .frame(maxWidth: .infinity)

                if let panel {
                    PlayerSidebar(model: model, selection: panel, quickTab: $quickTab,
                                  close: { self.panel = nil; revealControls() },
                                  addFiles: openMedia, addSubtitle: { openSubtitles($0) },
                                  searchSubtitles: { showSubtitleSearch = true },
                                  about: { showAbout = true })
                        .frame(width: sidebarWidth)
                        .background(.regularMaterial)
                        .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.12)).frame(width: 0.5) }
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.4)).frame(width: 4, height: 44)
                                .frame(width: 44, height: 88).contentShape(Rectangle()).offset(x: -22)
                                .gesture(DragGesture(minimumDistance: 2)
                                    .onChanged { value in
                                        if sidebarResizeStart == nil { sidebarResizeStart = Double(sidebarWidth) }
                                        var preferences = model.controlPreferences
                                        preferences.sidebarWidth = max(280, min(520, (sidebarResizeStart ?? Double(sidebarWidth)) - Double(value.translation.width)))
                                        model.updateControlPreferences(preferences, save: false)
                                    }.onEnded { _ in
                                        sidebarResizeStart = nil
                                        model.updateControlPreferences(model.controlPreferences)
                                    })
                                .accessibilityLabel("Resize sidebar; width is adjustable in Layout")
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .tint(.white)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: importSubtitle ? [.data] : [.movie, .audio, .data],
                      allowsMultipleSelection: !importSubtitle) { result in
            switch result {
            case let .success(urls):
                if importSubtitle, let url = urls.first { model.addSubtitle(url, target: subtitleTarget) }
                else { model.add(urls) }
                revealControls()
            case let .failure(error): model.report("Unable to open the selected file: \(error.localizedDescription)")
            }
        }
        .sheet(isPresented: $showURL) { urlSheet }
        .sheet(isPresented: $showAbout) { aboutSheet }
        .sheet(isPresented: $showSubtitleSearch) { SubtitleSearchView(player: model) }
        .sheet(isPresented: $model.showingJumpToTime) { JumpToTimeView(model: model) }
        .sheet(item: $model.capturedFrame) { FrameCaptureView(frame: $0) }
        .alert(item: $model.failure) { failure in
            Alert(title: Text("IINA"), message: Text(failure.message), dismissButton: .default(Text("OK")))
        }
        .onOpenURL { model.openIncoming($0); revealControls() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.endTouchSpeedBoost() }
            if phase == .background { model.enterBackground() }
            if phase == .active { model.enterForeground() }
        }
        .onChange(of: model.paused) { _, _ in revealControls() }
        .onChange(of: model.speed) { _, _ in revealControls() }
        .onChange(of: model.musicMode) { _, _ in revealControls() }
        .onChange(of: model.controlPreferences) { _, _ in revealControls() }
        .onChange(of: model.currentID) { _, _ in swipeFeedback = nil }
        .onChange(of: scrubbing) { _, _ in revealControls() }
        .onChange(of: pickingSpeed) { _, _ in revealControls() }
        .onDisappear { model.endTouchSpeedBoost() }
        .task(id: swipeFeedbackActivity) {
            guard swipeFeedback != nil else { return }
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
            swipeFeedback = nil
        }
        .task(id: controlActivity) {
            // Cancellation is expected whenever another touch resets the hide timer.
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, model.hasMedia, !model.paused, !model.musicMode,
                  !model.controlPreferences.keepControlsVisible, !model.controlPreferences.dockControls,
                  !scrubbing, !pickingSpeed, !model.touchSpeedBoostActive, panel == nil,
                  !showURL, !showImporter, !showAbout, !showSubtitleSearch else { return }
            controlsVisible = false
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Open…", systemImage: "folder", action: openMedia)
                    .keyboardShortcut("o", modifiers: .command)
                Button("Open URL…", systemImage: "link") { showURL = true }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                if model.hasMedia {
                    RepeatToolsMenu(model: model, titled: true)
                    Button("Load External Subtitle…", systemImage: "captions.bubble", action: openSubtitles)
                    Button("Find Online Subtitles…", systemImage: "magnifyingglass") { showSubtitleSearch = true }
                    Button(model.musicMode ? "Video Mode" : "Music Mini-player", systemImage: "music.note") { model.toggleMusicMode() }
                    if !model.musicMode {
                        Button(model.pictureInPictureActive ? "Stop Picture in Picture" : "Picture in Picture",
                               systemImage: "pip") { model.togglePictureInPicture() }
                            .disabled(!model.pictureInPicturePossible && !model.pictureInPictureActive)
                    }
                }
                Divider()
                Button("Playlist and Chapters", systemImage: "list.bullet") { togglePanel(.playlist) }
                ForEach(QuickSettingsTab.allCases, id: \.self) { tab in
                    Button(tab.rawValue, systemImage: tab.symbol) { openSettings(tab) }
                }
                Divider()
                Button("About IINA", systemImage: "info.circle") { showAbout = true }
            } label: {
                Image(systemName: "folder").frame(width: 44, height: 44)
            }
            .accessibilityLabel("File and player menu")
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                if model.hasMedia { Image(systemName: "doc").foregroundStyle(.secondary) }
                Text(model.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .accessibilityIdentifier("mediaTitle")
            }
            Spacer(minLength: 0)
            Button { togglePanel(.playlist) } label: {
                Image(systemName: "list.bullet").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Playlist and chapters")
            Button { togglePanel(.settings) } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Quick settings")
        }
        .font(.system(size: 16))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5) }
    }

    private var urlSheet: some View {
        NavigationStack {
            Form {
                Section("Media URL") {
                    TextField("https://example.com/video.mkv", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit(openTypedURL)
                }
                Section {
                    Text("Enter a direct media or stream URL.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Open URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showURL = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Open", action: openTypedURL).disabled(urlText.isEmpty) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var aboutSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image("IINALogo").resizable().scaledToFit().frame(width: 104, height: 104)
                Text("IINA").font(.system(size: 28, weight: .bold))
                Text("Version \(AppInfo.version) · iPad").foregroundStyle(.secondary)
                Text("Experimental iPadOS contribution").font(.callout).foregroundStyle(.secondary)
                Text("GPLv3 · Provided without warranty").font(.caption).foregroundStyle(.secondary)
                Link("iPadOS source and license", destination: URL(string: "https://github.com/SleepAviator/iina/tree/ipados/iPadOS")!)
                Link("IINA project and original icon", destination: URL(string: "https://iina.io")!)
                Link("MPVKit playback library", destination: URL(string: "https://github.com/mpvkit/MPVKit")!)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAbout = false } } }
        }
        .presentationDetents([.medium])
    }

    private func revealControls() { controlsVisible = true; controlActivity += 1 }
    private func openMedia() { importSubtitle = false; showImporter = true; revealControls() }
    private func openSubtitles() { openSubtitles(.primary) }
    private func openSubtitles(_ target: SubtitleTarget) {
        subtitleTarget = target; importSubtitle = true; showImporter = true; revealControls()
    }
    private func openTypedURL() {
        if model.openStream(urlText) { showURL = false; revealControls() }
    }
    private func togglePanel(_ selection: SidePanel) {
        withAnimation(.easeInOut(duration: 0.2)) { panel = panel == selection ? nil : selection }
        revealControls()
    }
    private func openSettings(_ tab: QuickSettingsTab) {
        quickTab = tab
        withAnimation(.easeInOut(duration: 0.2)) { panel = .settings }
        revealControls()
    }
}

private struct WelcomeView: View {
    let openFiles: () -> Void
    let openURL: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 16) {
                Image("IINALogo").resizable().scaledToFit().frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 5) {
                    Text("IINA").font(.system(size: 28, weight: .bold))
                    Text("\(AppInfo.version) · iPad").font(.callout).foregroundStyle(.secondary)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { openButton; urlButton }
                VStack(alignment: .leading, spacing: 12) { openButton; urlButton }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("The modern media player.").font(.callout)
                Text("Open a file from Files, iCloud Drive, or external storage, or enter a media URL.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(28)
        .frame(maxWidth: 430)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.1), lineWidth: 0.5) }
        .padding(24)
    }

    private var openButton: some View {
        Button("Open…", systemImage: "folder", action: openFiles)
            .keyboardShortcut("o", modifiers: .command)
            .buttonStyle(.bordered).controlSize(.large)
    }

    private var urlButton: some View {
        Button("Open URL…", systemImage: "link", action: openURL)
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .buttonStyle(.bordered).controlSize(.large)
    }
}

private struct MusicMiniPlayer: View {
    @ObservedObject var model: PlayerModel
    let compact: Bool
    @Binding var scrubbing: Bool
    @Binding var pickingSpeed: Bool
    let settings: () -> Void
    let playlist: () -> Void
    let activity: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                Image("IINALogo").resizable().scaledToFit().frame(width: 100, height: 100)
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.title).font(.title3.weight(.semibold)).lineLimit(2)
                    if !model.artist.isEmpty { Text(model.artist).foregroundStyle(.secondary).lineLimit(1) }
                    if !model.album.isEmpty { Text(model.album).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                    Text("Music Mini-player").font(.caption).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 12)
            PlaybackControls(model: model, compact: compact, scrubbing: $scrubbing, pickingSpeed: $pickingSpeed,
                             settings: settings, playlist: playlist, activity: activity)
        }
        .padding(22).frame(maxWidth: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.1), lineWidth: 0.5) }
        .padding(18)
        .accessibilityIdentifier("musicMiniPlayer")
    }
}

private struct PlaybackControls: View {
    @ObservedObject var model: PlayerModel
    let compact: Bool
    @Binding var scrubbing: Bool
    @Binding var pickingSpeed: Bool
    let settings: () -> Void
    let playlist: () -> Void
    let activity: () -> Void
    @State private var seekValue = 0.0
    @State private var showRemainingTime = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                volumeControls.frame(maxWidth: .infinity, alignment: .leading)
                transportControls
                HStack(spacing: 0) {
                    if !compact && !model.musicMode {
                        control(model.fillVideo ? "Fit video" : "Fill screen", symbol: "arrow.up.left.and.arrow.down.right", action: model.toggleFit)
                    }
                    if !model.musicMode && !compact {
                        control(model.pictureInPictureActive ? "Stop Picture in Picture" : "Picture in Picture",
                                symbol: model.pictureInPictureActive ? "pip.exit" : "pip.enter",
                                enabled: model.pictureInPicturePossible || model.pictureInPictureActive,
                                action: model.togglePictureInPicture)
                    }
                    if !compact { control("Playlist and chapters", symbol: "list.bullet", action: playlist) }
                    RepeatToolsMenu(model: model)
                    control("Quick settings", symbol: "slider.horizontal.3", action: settings)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if let a = model.loopStart {
                Text("A \(playbackTime(a))" + (model.loopEnd.map { "  ·  B \(playbackTime($0))  ·  Looping" } ?? "  ·  Set B to loop"))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.blue)
            }
            timeline
        }
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.13), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.3), radius: 14, y: 4)
    }

    private var volumeControls: some View {
        HStack(spacing: 0) {
            control(model.volume == 0 ? "Unmute" : "Mute", symbol: model.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", action: model.toggleMute)
            if !compact {
                Button {
                    pickingSpeed = true
                    activity()
                } label: {
                    Text("\(model.speed.formatted(.number.precision(.fractionLength(0...2))))×")
                        .font(.caption.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Playback speed, \(model.speed.formatted()) times")
                .accessibilityIdentifier("playbackSpeedMenu")
                .popover(isPresented: $pickingSpeed, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Playback speed").font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(76)), count: 3), spacing: 8) {
                            ForEach(PlaybackRates.presets, id: \.self) { rate in
                                Button("\(rate.formatted())×") {
                                    model.setSpeed(rate)
                                    pickingSpeed = false
                                    activity()
                                }
                                .font(.body.weight(.semibold))
                                .frame(width: 76, height: 44)
                                .background(model.speed == rate ? Color.blue : Color.primary.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(model.speed == rate ? Color.white : Color.primary)
                            }
                        }.buttonStyle(.plain)
                    }
                    .padding(18)
                    .presentationCompactAdaptation(.popover)
                }
                Slider(value: Binding(get: { model.volume }, set: { model.setVolume($0); activity() }), in: 0...100)
                    .tint(.white.opacity(0.72))
                    .frame(width: 76).accessibilityLabel("Volume")
            }
        }
    }

    private var transportControls: some View {
        HStack(spacing: 0) {
            if !compact { control("Previous file", symbol: "backward.end.fill", enabled: model.canGoBack, action: model.previous) }
            control("Back \(Int(model.controlPreferences.seekSeconds)) seconds", symbol: "backward.fill") { model.skip(-model.controlPreferences.seekSeconds) }
            Button { model.togglePause(); activity() } label: {
                Image(systemName: model.paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 26, weight: .semibold)).frame(width: 52, height: 48)
            }
            .accessibilityLabel(model.paused ? "Play" : "Pause")
            control("Forward \(Int(model.controlPreferences.seekSeconds)) seconds", symbol: "forward.fill") { model.skip(model.controlPreferences.seekSeconds) }
            if !compact { control("Next file", symbol: "forward.end.fill", enabled: model.canGoForward, action: model.next) }
        }
    }

    private var timeline: some View {
        HStack(spacing: 10) {
            Text(playbackTime(scrubbing ? seekValue : model.position))
                .accessibilityIdentifier("playbackPosition")
            Slider(value: Binding(get: { scrubbing ? seekValue : min(model.position, max(model.duration, 1)) },
                                  set: { seekValue = $0 }),
                   in: 0...max(model.duration, 1)) { editing in
                if editing { seekValue = model.position; scrubbing = true }
                else { model.seek(to: seekValue); scrubbing = false }
                activity()
            }
            .tint(.white.opacity(0.72))
            .disabled(model.duration <= 0)
            .accessibilityLabel("Playback position")
            .overlay(alignment: .bottom) {
                if scrubbing && !model.isAudioOnly { SeekThumbnailView(preview: model.seekPreview).offset(y: -44).allowsHitTesting(false) }
            }
            Button {
                showRemainingTime.toggle(); activity()
            } label: {
                Text(showRemainingTime
                     ? "−" + playbackTime(max(0, model.duration - (scrubbing ? seekValue : model.position)))
                     : playbackTime(model.duration))
            }
            .accessibilityLabel(showRemainingTime ? "Remaining time; show duration" : "Duration; show remaining time")
        }
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(.secondary)
        .task(id: scrubbing ? "\(model.currentID?.uuidString ?? "")|\(Int(seekValue / max(1, model.duration / 120)))" : "idle") {
            guard scrubbing, !model.isAudioOnly else { model.seekPreview.cancel(); return }
            await model.seekPreview.show(url: model.currentURL, seconds: seekValue, duration: model.duration,
                                         allowRemote: model.controlPreferences.allowRemotePreviews)
        }
    }

    private func control(_ label: String, symbol: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button { action(); activity() } label: {
            Image(systemName: symbol).font(.system(size: 16)).frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
        .disabled(!enabled)
    }
}

private struct PlayerSidebar: View {
    @ObservedObject var model: PlayerModel
    let selection: SidePanel
    @Binding var quickTab: QuickSettingsTab
    let close: () -> Void
    let addFiles: () -> Void
    let addSubtitle: (SubtitleTarget) -> Void
    let searchSubtitles: () -> Void
    let about: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(selection.rawValue).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Close sidebar")
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.leading, 20).padding(.trailing, 8).padding(.top, 4)
            Divider()
            if selection == .playlist { PlaylistPanelView(model: model, addFiles: addFiles) }
            else {
                tabBar
                Divider()
                switch quickTab {
                case .layout: layoutPanel
                case .video: VideoSettingsView(model: model)
                case .audio: audioPanel
                case .subtitles: SubtitleSettingsView(model: model, openFile: addSubtitle, searchOnline: searchSubtitles)
                }
                Divider()
                Button("About IINA", action: about)
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(QuickSettingsTab.allCases, id: \.self) { tab in
                Button { quickTab = tab } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol).font(.system(size: 18))
                        if quickTab == tab { Text(tab.rawValue).font(.system(size: 13, weight: .semibold)) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .foregroundStyle(quickTab == tab ? .primary : .secondary)
                    .background(quickTab == tab ? Color.white.opacity(0.12) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityIdentifier("quickSettingsTab_\(tab.rawValue.lowercased())")
                .accessibilityAddTraits(quickTab == tab ? .isSelected : [])
            }
        }
        .padding(10)
    }

    private var layoutPanel: some View {
        Form {
            Section("Video framing") {
                Picker("Framing", selection: Binding(get: { model.fillVideo }, set: { _ in model.toggleFit() })) {
                    Text("Fit").tag(false)
                    Text("Fill").tag(true)
                }.pickerStyle(.segmented)
                Text("Fit shows the whole frame. Fill crops its edges to cover the player.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.disabled(!model.hasMedia)
            Section("Player") {
                Toggle("Music Mini-player", isOn: Binding(get: { model.musicMode }, set: { _ in model.toggleMusicMode() }))
                Text("Audio-only files open in the mini-player automatically. Audio continues when IINA is in the background.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.disabled(!model.hasMedia)
            ControlSettingsSections(model: model)
        }.scrollContentBackground(.hidden)
    }

    private var audioPanel: some View {
        Form {
            Section("Audio tracks") {
                if model.tracks.filter({ $0.kind == "audio" }).isEmpty { Text("No audio tracks.").foregroundStyle(.secondary) }
                ForEach(model.tracks.filter { $0.kind == "audio" }) { track in
                    trackButton(track.label, selected: model.audioID == String(track.id)) { model.selectAudio(String(track.id)) }
                }
            }
            Section("Playback speed") { PlaybackSpeedEditor(model: model).tint(.blue) }
                .disabled(!model.hasMedia)
            Section("Volume") {
                HStack {
                    Button { model.toggleMute() } label: {
                        Image(systemName: model.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 44, height: 44)
                    }.accessibilityLabel(model.volume == 0 ? "Unmute" : "Mute")
                    Slider(value: Binding(get: { model.volume }, set: model.setVolume), in: 0...100)
                        .accessibilityLabel("Volume")
                    Text("\(Int(model.volume))%").font(.caption.monospacedDigit())
                }
            }.disabled(!model.hasMedia)
            Section("Synchronization") {
                delayControl("Audio delay", value: model.audioDelay, update: model.setAudioDelay)
                Button("Reset Audio Delay") { model.setAudioDelay(0) }
            }.disabled(!model.hasMedia)
        }.scrollContentBackground(.hidden)
    }

    private func trackButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }.padding(.vertical, 5)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func delayControl(_ label: String, value: Double, update: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%+.1f s", value)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { value }, set: update), in: -10...10, step: 0.1)
                .accessibilityLabel(label)
        }.padding(.vertical, 5)
    }
}
