// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import AVFoundation
import Combine
import Foundation
import UIKit
import SwiftUI

struct PlaylistEntry: Identifiable {
    let id = UUID()
    let url: URL
    var title: String { url.lastPathComponent.isEmpty ? url.host ?? "Stream" : url.lastPathComponent }
}

struct PlayerFailure: Identifiable {
    let id = UUID()
    let message: String
}

@MainActor
final class PlayerModel: ObservableObject {
    @Published var playlist: [PlaylistEntry] = []
    @Published var currentID: UUID?
    @Published var title = "IINA"
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var paused = true
    @Published var buffering = false
    @Published var loading = false
    // The user's selected rate survives buffering and asynchronous engine updates.
    @Published private(set) var speed = 1.0
    @Published private(set) var touchSpeedBoostActive = false
    @Published var volume = 100.0
    @Published var subtitleDelay = 0.0
    @Published var secondarySubtitleDelay = 0.0
    @Published var audioDelay = 0.0
    @Published var fillVideo = false
    @Published var audioID = "auto"
    @Published var videoID = "auto"
    @Published var subtitleID = "auto"
    @Published var secondarySubtitleID = "no"
    @Published var subtitleStyle = SubtitleStyle()
    @Published var musicMode = false
    @Published var artist = ""
    @Published var album = ""
    @Published var tracks: [MediaTrack] = []
    @Published var chapters: [MediaChapter] = []
    @Published var decoder = ""
    @Published var codec = ""
    @Published var videoSettings = VideoSettings()
    @Published private(set) var appliedVideoSettings = VideoSettings()
    @Published private(set) var outputVideoSize = CGSize.zero
    @Published var failure: PlayerFailure?
    @Published private(set) var backend: PlaybackBackend?
    @Published private(set) var routingReason = ""
    @Published var pictureInPicturePossible = false
    @Published private(set) var pictureInPictureActive = false
    @Published private(set) var controlPreferences = ControlPreferences()
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var loopStart: Double?
    @Published private(set) var loopEnd: Double?
    @Published private(set) var diagnostics = PlaybackDiagnostics()
    @Published private(set) var canStepForward = false
    @Published private(set) var canStepBackward = false
    @Published private(set) var capturingFrame = false
    @Published var capturedFrame: CapturedFrame?
    @Published var showingJumpToTime = false
    @Published private(set) var savedPlaylists: [SavedPlaylist] = []
    @Published private(set) var readingPlaylist = false
    let seekPreview = SeekPreview()
    private let playlistStore: PlaylistStore
    private var playlistFolders: Set<URL> = []
    private var folderRequest = UUID()

    private var engine: PlaybackEngine?
    private var shuttingDownEngine = false
    private var pendingEngineStart: (() -> Void)?
    private weak var surface: VideoSurfaceView?
    private var pictureInPicture: PictureInPicture?
    private var pictureInPictureStarting = false
    private var afterPictureInPicture: (() -> Void)?
    private var generation = UUID()
    private var nativeFailure: String?
    private var pendingActions: [() -> Void] = []
    private var restoreSelection: (audio: MediaTrack?, video: MediaTrack?, subtitle: MediaTrack?, subtitlesOff: Bool)?
    private var videoSize = CGSize(width: 640, height: 360)
    private var pictureInPictureSize: CGSize?
    private var pendingSeek: (target: Double, completion: () -> Void)?
    private var seekTimeout: Task<Void, Never>?
    private var scopedURLs: Set<URL> = []
    private var pendingSecondarySubtitle: String?
    private var inBackground = false
    private var reachedEnd = false
    private var lastVolume = 100.0
    private var selectedVideoID = "auto"
    private var videoOutputSelection: String?
    private var videoSettingsTask: Task<Void, Never>?
    private var speedBeforeTouchBoost: Double?
    private lazy var mediaSession = MediaSession(player: self)

    init(playlistStore: PlaylistStore = PlaylistStore()) {
        self.playlistStore = playlistStore
        do { subtitleStyle = try SubtitleStyle.load() }
        catch { failure = PlayerFailure(message: "Unable to read saved subtitle settings: \(error.localizedDescription)") }
        do { controlPreferences = try ControlPreferences.load() }
        catch { failure = PlayerFailure(message: "Unable to read saved controls: \(error.localizedDescription)") }
    }

    var currentIndex: Int? { playlist.firstIndex { $0.id == currentID } }
    var hasMedia: Bool { currentID != nil }
    var currentURL: URL? { currentIndex.map { playlist[$0].url } }
    var isAudioOnly: Bool { !tracks.isEmpty && !tracks.contains { $0.kind == "video" && !$0.albumArt } }
    var videoTracks: [MediaTrack] { tracks.filter { $0.kind == "video" && !$0.albumArt } }
    var selectedVideoTrack: MediaTrack? {
        videoTracks.first { String($0.id) == videoID } ?? (videoID == "auto" ? videoTracks.first : nil)
    }
    var canGoBack: Bool { (currentIndex ?? 0) > 0 || (repeatMode == .all && playlist.count > 1) }
    var canGoForward: Bool { currentIndex.map { $0 + 1 < playlist.count || (repeatMode == .all && playlist.count > 1) } ?? false }
    var canUsePlaybackGestures: Bool {
        hasMedia && !paused && !loading && !musicMode && !inBackground &&
        !pictureInPictureActive && !pictureInPictureStarting && !reachedEnd
    }

    func attach(to surface: VideoSurfaceView) {
        guard self.surface == nil else { return }
        self.surface = surface
        surface.onResize = { [weak self] _ in self?.resizeVideo() }
        _ = mediaSession
        if let url = currentURL { startEngine(backend ?? .native, url: url, position: position, paused: paused) }
    }

    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        for url in urls {
            if !scopedURLs.contains(url), url.startAccessingSecurityScopedResource() { scopedURLs.insert(url) }
        }
        let entries = urls.map { PlaylistEntry(url: $0) }
        playlist.append(contentsOf: entries)
        play(entries[0].id)
    }

    func movePlaylist(from offsets: IndexSet, to destination: Int) {
        playlist.move(fromOffsets: offsets, toOffset: destination)
    }

    func removePlaylist(at offsets: IndexSet) {
        let oldIndex = currentIndex ?? 0
        let removedCurrent = offsets.contains(oldIndex) && currentID != nil
        playlist.remove(atOffsets: offsets)
        if removedCurrent {
            if playlist.isEmpty { closeMedia() }
            else { play(playlist[min(oldIndex, playlist.count - 1)].id) }
        }
    }

    func sortPlaylist() {
        playlist.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func shufflePlaylist() { playlist.shuffle() }

    func openFolder(_ folder: URL) async {
        let ticket = UUID(); folderRequest = ticket
        readingPlaylist = true
        retainAccess(folder)
        do {
            let urls = try await playlistStore.mediaInFolder(folder)
            guard ticket == folderRequest else { return }
            guard !urls.isEmpty else { throw PlaybackToolError.unavailable("No supported audio or video files were found in this folder.") }
            playlistFolders = [folder]
            playlist = urls.map { PlaylistEntry(url: $0) }
            play(playlist[0].id)
        } catch { if ticket == folderRequest { report("Unable to open folder: \(error.localizedDescription)") } }
        if ticket == folderRequest { readingPlaylist = false }
    }

    func refreshSavedPlaylists() async {
        do { savedPlaylists = try await playlistStore.list() }
        catch { report("Unable to read saved playlists: \(error.localizedDescription)") }
    }

    func savePlaylist(named name: String) async {
        do {
            let urls = playlist.map(\.url)
            let folders = playlistFolders.filter { folder in urls.contains { $0.path.hasPrefix(folder.path + "/") } }
            let value = try await playlistStore.save(name: name, media: urls, folders: Array(folders))
            savedPlaylists.insert(value, at: 0)
        } catch { report("Unable to save playlist: \(error.localizedDescription)") }
    }

    func loadPlaylist(_ saved: SavedPlaylist) async {
        let ticket = UUID(); folderRequest = ticket; readingPlaylist = true
        do {
            let value = try await playlistStore.restore(saved)
            guard ticket == folderRequest else { return }
            guard !value.media.isEmpty else { throw PlaybackToolError.unavailable("This saved playlist is empty.") }
            value.folders.forEach(retainAccess)
            value.media.forEach(retainAccess)
            playlistFolders = Set(value.folders)
            playlist = value.media.map { PlaylistEntry(url: $0) }
            play(playlist[0].id)
        } catch { if ticket == folderRequest { report("Unable to reopen playlist: \(error.localizedDescription)") } }
        if ticket == folderRequest { readingPlaylist = false }
    }

    func deleteSavedPlaylist(_ value: SavedPlaylist) async {
        do {
            try await playlistStore.remove(value.id)
            savedPlaylists.removeAll { $0.id == value.id }
        } catch { report("Unable to delete saved playlist: \(error.localizedDescription)") }
    }

    private func retainAccess(_ url: URL) {
        if url.isFileURL, !scopedURLs.contains(url), url.startAccessingSecurityScopedResource() { scopedURLs.insert(url) }
    }

    private func closeMedia() {
        if pictureInPictureActive || pictureInPictureStarting {
            afterPictureInPicture = { [weak self] in self?.closeMedia() }
            pictureInPicture?.stop(); return
        }
        endTouchSpeedBoost(); seekPreview.cancel(); clearLoop()
        generation = UUID(); pendingEngineStart = nil; pendingActions = []
        let previous = engine
        previous?.set("pause", "yes"); engine = nil
        if let previous {
            shuttingDownEngine = true
            previous.requestShutdown { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.shuttingDownEngine = false
                    self.startPendingEngine()
                }
            }
        }
        surface?.nativeLayer.player = nil; surface?.sampleLayer.flushAndRemoveImage()
        currentID = nil; backend = nil; title = "IINA"; position = 0; duration = 0
        paused = true; loading = false; buffering = false; tracks = []; chapters = []
        diagnostics = PlaybackDiagnostics(); capturedFrame = nil
        canStepForward = false; canStepBackward = false
        finishPendingSeek(); updateIdleTimer(); mediaSession.update(force: true)
    }

    func openStream(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http", "rtsp", "rtmp"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
            report("Enter a complete HTTP, HTTPS, RTSP, or RTMP media URL.")
            return false
        }
        add([url])
        return true
    }

    func openIncoming(_ url: URL) {
        if url.scheme == "iinapad" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let text = components.queryItems?.first(where: { $0.name == "url" })?.value,
                  let media = URL(string: text) else {
                report("This media link is incomplete.")
                return
            }
            if media.isFileURL { add([media]) }
            else { _ = openStream(text) }
        } else if url.isFileURL { add([url]) }
        else { _ = openStream(url.absoluteString) }
    }

    func play(_ id: UUID) {
        guard let entry = playlist.first(where: { $0.id == id }) else { return }
        folderRequest = UUID(); readingPlaylist = false
        endTouchSpeedBoost()
        if pictureInPictureActive || pictureInPictureStarting {
            afterPictureInPicture = { [weak self] in self?.play(id) }
            pictureInPicture?.stop()
            return
        }
        do { try mediaSession.activate() }
        catch { report("Unable to activate audio: \(error.localizedDescription)"); return }
        mediaSession.cancelInterruptionResume()
        pendingSecondarySubtitle = nil
        pendingActions = []
        restoreSelection = nil
        finishPendingSeek()
        nativeFailure = nil
        failure = nil
        seekPreview.cancel()
        clearLoop()
        diagnostics = PlaybackDiagnostics()
        canStepForward = false; canStepBackward = false
        capturingFrame = false; capturedFrame = nil
        currentID = id
        title = entry.title
        position = 0
        duration = 0
        tracks = []
        chapters = []
        decoder = ""
        codec = ""
        videoID = "auto"
        selectedVideoID = "auto"
        videoSize = CGSize(width: 640, height: 360)
        outputVideoSize = .zero
        appliedVideoSettings = VideoSettings()
        videoSettingsTask?.cancel()
        artist = ""
        album = ""
        musicMode = false
        audioID = "auto"
        subtitleID = "auto"
        secondarySubtitleID = "no"
        reachedEnd = false
        loading = true
        paused = false
        if audioDelay != 0 || subtitleDelay != 0 || secondarySubtitleDelay != 0 || videoSettings.requiresMPV {
            routingReason = videoSettings.requiresMPV ? "Custom video settings" : "Saved timing adjustment"
            startEngine(.mpv, url: entry.url, position: 0, paused: false)
        } else { startEngine(.native, url: entry.url, position: 0, paused: false) }
        updateIdleTimer()
        mediaSession.update(force: true)
    }

    func next() {
        guard let index = currentIndex, !playlist.isEmpty else { return }
        if index + 1 < playlist.count { play(playlist[index + 1].id) }
        else if repeatMode == .all { play(playlist[0].id) }
    }

    func previous() {
        guard let index = currentIndex, !playlist.isEmpty else { return }
        if index > 0 { play(playlist[index - 1].id) }
        else if repeatMode == .all { play(playlist[playlist.count - 1].id) }
    }

    func togglePause() {
        setPaused(!paused)
    }

    func setPaused(_ value: Bool, userInitiated: Bool = true) {
        guard hasMedia else { return }
        if value { endTouchSpeedBoost() }
        if userInitiated { mediaSession.cancelInterruptionResume() }
        if !value {
            do { try mediaSession.activate() }
            catch { report("Unable to activate audio: \(error.localizedDescription)"); return }
        }
        if reachedEnd && !value {
            seek(to: 0)
            reachedEnd = false
        }
        if let engine { engine.set("pause", value ? "yes" : "no") }
        else { paused = value; updateIdleTimer() }
    }

    func seek(to seconds: Double, completion: (() -> Void)? = nil) {
        guard hasMedia, seconds.isFinite else { completion?(); return }
        let target = max(0, min(seconds, duration > 0 ? duration : seconds))
        finishPendingSeek()
        if let completion {
            pendingSeek = (target, completion)
            seekTimeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(10)) }
                catch { return }
                guard let self, self.pendingSeek != nil else { return }
                self.report("Seeking did not finish in time.")
                self.finishPendingSeek()
            }
        }
        if backend == .mpv { surface?.sampleLayer.flush() }
        engine?.command(["seek", String(target), "absolute+exact"])
        reachedEnd = false
    }

    func skip(_ seconds: Double) { seek(to: position + seconds) }
    func jump(to text: String) -> Bool {
        guard let target = PlaybackTimestamp.parse(text), duration > 0, target <= duration else {
            report("Enter seconds, MM:SS, or HH:MM:SS between 0 and \(playbackTime(duration))."); return false
        }
        seek(to: target)
        return true
    }

    func markLoopStart() {
        guard hasMedia, duration > 0 else { return }
        loopStart = position; loopEnd = nil; engine?.setLoop(nil)
    }

    func markLoopEnd() {
        guard let start = loopStart, position > start + 0.1 else {
            report("Set point A first, then move at least 0.1 seconds forward to set point B."); return
        }
        loopEnd = position
        engine?.setLoop(start...position)
    }

    func clearLoop() {
        loopStart = nil; loopEnd = nil; engine?.setLoop(nil)
    }

    func stepFrame(forward: Bool) {
        guard hasMedia, !loading, videoID != "no", forward ? canStepForward : canStepBackward else {
            report("This media does not support stepping in that direction."); return
        }
        setPaused(true)
        engine?.command([forward ? "frame-step" : "frame-back-step"])
    }

    func captureFrame() {
        guard hasMedia, !loading, !capturingFrame, !videoTracks.isEmpty, videoID != "no", let engine else { return }
        capturingFrame = true
        let token = generation, time = position, name = title
        engine.captureFrame { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.capturingFrame = false
                switch result {
                case .success(let image): self.capturedFrame = CapturedFrame(image: image, time: time, title: name)
                case .failure(let error): self.report("Unable to capture frame: \(error.localizedDescription)")
                }
            }
        }
    }

    func updateControlPreferences(_ value: ControlPreferences, save: Bool = true) {
        guard value.isValid else { report("Choose distinct keyboard shortcuts and settings within the supported range."); return }
        endTouchSpeedBoost()
        controlPreferences = value
        if save {
            do { try value.save() }
            catch { report("Unable to save controls: \(error.localizedDescription)") }
        }
    }

    func performControl(_ action: PlayerControlAction) {
        switch action {
        case .pause: togglePause()
        case .backward: skip(-controlPreferences.seekSeconds)
        case .forward: skip(controlPreferences.seekSeconds)
        case .frameBackward: stepFrame(forward: false)
        case .frameForward: stepFrame(forward: true)
        case .screenshot: captureFrame()
        case .jump: if duration > 0 { showingJumpToTime = true }
        }
    }
    func setSpeed(_ value: Double) {
        guard value.isFinite, PlaybackRates.range.contains(value) else {
            report("Playback speed must be between 0.25× and 16×."); return
        }
        // An explicit speed choice supersedes a temporary touch hold.
        speedBeforeTouchBoost = nil
        touchSpeedBoostActive = false
        applySpeed(value)
    }

    @discardableResult
    func beginTouchSpeedBoost() -> Bool {
        guard canUsePlaybackGestures, controlPreferences.holdEnabled, speedBeforeTouchBoost == nil else { return false }
        speedBeforeTouchBoost = speed
        touchSpeedBoostActive = true
        applySpeed(controlPreferences.holdSpeed)
        return true
    }

    func endTouchSpeedBoost() {
        guard let previous = speedBeforeTouchBoost else { return }
        speedBeforeTouchBoost = nil
        touchSpeedBoostActive = false
        applySpeed(previous)
    }

    private func applySpeed(_ value: Double) {
        speed = value
        if let native = engine as? NativeEngine, !native.supportsRate(value) {
            withMPV("AVPlayer cannot play this item at \(value.formatted())×.") { [weak self] in
                guard let self else { return }
                self.engine?.set("speed", String(self.speed))
            }
        } else { engine?.set("speed", String(value)) }
        mediaSession.update(force: true)
    }

    func selectVideo(_ id: String) {
        selectedVideoID = id
        if backend == .mpv { updateMPVVideoSelection() }
        else { engine?.set("vid", id) }
    }

    func updateVideoSettings(_ value: VideoSettings, debounce: Bool = false) {
        guard value.isValid else { report("These video settings are outside the supported range."); return }
        videoSettings = value
        videoSettingsTask?.cancel()
        if debounce {
            videoSettingsTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(120)) }
                catch { return }
                self?.applyRequestedVideoSettings()
            }
        } else { applyRequestedVideoSettings() }
    }

    private func applyRequestedVideoSettings() {
        guard backend == .mpv || videoSettings.requiresMPV else { return }
        withMPV(videoSettings.hardwareDecoding ? "Custom video settings" : "Software decoding requested") { [weak self] in
            guard let self else { return }
            (self.engine as? MPVEngine)?.applyVideoSettings(self.videoSettings)
        }
    }
    func setVolume(_ value: Double) { engine?.set("volume", String(value)) }
    func setSubtitleDelay(_ value: Double) {
        guard value != subtitleDelay else { return }
        withMPV("Subtitle timing") { [weak self] in self?.engine?.set("sub-delay", String(value)) }
    }
    func setSecondarySubtitleDelay(_ value: Double) {
        guard value != secondarySubtitleDelay else { return }
        withMPV("Dual subtitle timing") { [weak self] in self?.engine?.set("secondary-sub-delay", String(value)) }
    }
    func setAudioDelay(_ value: Double) {
        guard value != audioDelay else { return }
        withMPV("Audio timing") { [weak self] in self?.engine?.set("audio-delay", String(value)) }
    }
    func selectAudio(_ id: String) { engine?.set("aid", id) }
    func selectSubtitle(_ id: String, target: SubtitleTarget = .primary) {
        if target == .secondary, id == "no", secondarySubtitleID == "no" { return }
        if target == .primary {
            if id != "no", id == secondarySubtitleID, backend == .mpv { engine?.set("secondary-sid", "no") }
            engine?.set("sid", id)
        } else {
            withMPV("Dual subtitles") { [weak self] in
                guard let self else { return }
                if id != "no", id == self.subtitleID { self.engine?.set("sid", "no") }
                self.engine?.set("secondary-sid", id)
            }
        }
    }

    func updateSubtitleStyle(_ value: SubtitleStyle) {
        let previous = subtitleStyle
        subtitleStyle = value
        if backend == .native, hasMedia, !isAudioOnly, value != previous {
            withMPV("Custom subtitle appearance") { [weak self] in self?.applySubtitleStyle() }
        } else { applySubtitleStyle(previous: previous) }
        do { try value.save() }
        catch { report("Unable to save subtitle settings: \(error.localizedDescription)") }
    }

    private func applySubtitleStyle(previous: SubtitleStyle? = nil) {
        guard backend == .mpv else { return }
        let old = Dictionary(uniqueKeysWithValues: previous?.properties ?? [])
        for (name, value) in subtitleStyle.properties where old[name] != value { engine?.set(name, value) }
    }

    func reloadExternalSubtitles() {
        for track in tracks where track.kind == "sub" && !track.externalPath.isEmpty {
            engine?.command(["sub-reload", String(track.id)])
        }
    }

    func toggleMusicMode() {
        endTouchSpeedBoost()
        if pictureInPictureActive || pictureInPictureStarting {
            afterPictureInPicture = { [weak self] in self?.toggleMusicMode() }
            pictureInPicture?.stop()
            return
        }
        musicMode.toggle()
        updateVideoVisibility()
        pictureInPicture?.update()
        updateIdleTimer()
    }

    func toggleFit() {
        fillVideo.toggle()
        if let backend { surface?.show(backend, fill: fillVideo) }
    }

    func toggleMute() {
        if volume > 0 {
            lastVolume = volume
            setVolume(0)
        } else { setVolume(lastVolume) }
    }

    func addSubtitle(_ url: URL, target: SubtitleTarget = .primary) {
        guard hasMedia else { report("Open a video before adding subtitles."); return }
        if !scopedURLs.contains(url), url.startAccessingSecurityScopedResource() { scopedURLs.insert(url) }
        withMPV("External subtitles") { [weak self] in self?.addMPVSubtitle(url, target: target) }
    }

    private func addMPVSubtitle(_ url: URL, target: SubtitleTarget) {
        let path = url.isFileURL ? url.path : url.absoluteString
        if target == .secondary {
            if let existing = tracks.first(where: { $0.kind == "sub" && $0.externalPath == path }) {
                selectSubtitle(String(existing.id), target: .secondary)
                return
            }
            pendingSecondarySubtitle = path
        }
        engine?.command(["sub-add", path, target == .primary ? "select" : "auto"])
    }

    func enterBackground() {
        endTouchSpeedBoost()
        inBackground = true
        updateVideoVisibility()
        UIApplication.shared.isIdleTimerDisabled = false
        mediaSession.update(force: true)
    }

    func enterForeground() {
        inBackground = false
        updateVideoVisibility()
        updateIdleTimer()
        mediaSession.update(force: true)
    }

    func report(_ message: String) {
        failure = PlayerFailure(message: message)
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = !inBackground && hasMedia && !paused && !musicMode
    }

    private func startEngine(_ backend: PlaybackBackend, url: URL, position: Double, paused: Bool) {
        generation = UUID()
        let token = generation
        let previous = engine
        previous?.set("pause", "yes")
        engine = nil
        videoOutputSelection = nil
        pictureInPicture = nil
        pictureInPicturePossible = false
        self.backend = backend
        diagnostics = PlaybackDiagnostics()
        canStepForward = false; canStepBackward = false
        self.paused = paused
        surface?.nativeLayer.player = nil
        surface?.sampleLayer.flushAndRemoveImage()
        surface?.show(backend, fill: fillVideo)
        pendingEngineStart = { [weak self] in
            guard let self, self.generation == token else { return }
            self.finishStartingEngine(backend, url: url, position: position, token: token)
        }
        // mpv's iOS audio output deactivates the shared AVAudioSession on
        // destruction. Never let an old client stop a replacement's audio.
        // A newer open request replaces the pending start during teardown.
        guard !shuttingDownEngine else { return }
        if let previous {
            shuttingDownEngine = true
            previous.requestShutdown { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.shuttingDownEngine = false
                    self.startPendingEngine()
                }
            }
        } else { startPendingEngine() }
    }

    private func startPendingEngine() {
        let start = pendingEngineStart
        pendingEngineStart = nil
        start?()
    }

    private func finishStartingEngine(_ backend: PlaybackBackend, url: URL, position: Double, token: UUID) {
        guard let surface else { return }
        do { try mediaSession.activate() }
        catch {
            loading = false
            report("Unable to activate audio after changing playback engines: \(error.localizedDescription)")
            return
        }
        let events: (PlayerEvent) -> Void = { [weak self] event in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.receive(event)
            }
        }
        if backend == .native {
            routingReason = ""
            let native = NativeEngine(deliver: events)
            engine = native
            surface.nativeLayer.player = native.player
        } else {
            let mpv = MPVEngine(timebase: surface.timebase, frame: { [weak self] frame in
                guard let self, self.generation == token else { return }
                self.surface?.enqueue(frame)
            }, deliver: events)
            engine = mpv
            mpv.applyVideoSettings(videoSettings)
            applySubtitleStyle()
            engine?.set("sub-delay", String(subtitleDelay))
            engine?.set("secondary-sub-delay", String(secondarySubtitleDelay))
            engine?.set("audio-delay", String(audioDelay))
            updateMPVVideoSelection()
            resizeVideo()
        }
        engine?.set("speed", String(speed))
        engine?.set("volume", String(volume))
        if let a = loopStart, let b = loopEnd { engine?.setLoop(a...b) }
        synchronizeTimebase()
        pictureInPicture = PictureInPicture(player: self, surface: surface, backend: backend)
        engine?.open(url, start: position, paused: self.paused)
        updateVideoVisibility()
    }

    /// Feature requests select mpv once for the current item.
    /// Compatible native media keeps AVPlayer when entering and leaving PiP.
    private func withMPV(_ reason: String, action: @escaping () -> Void) {
        guard hasMedia else { return }
        if backend == .mpv {
            if loading { pendingActions.append(action) }
            else { action() }
            return
        }
        if pictureInPictureActive || pictureInPictureStarting {
            afterPictureInPicture = { [weak self] in self?.withMPV(reason, action: action) }
            pictureInPicture?.stop()
            return
        }
        guard let url = currentURL else { return }
        let audio = tracks.first { $0.kind == "audio" && String($0.id) == audioID }
        let video = selectedVideoTrack
        let subtitle = tracks.first { $0.kind == "sub" && String($0.id) == subtitleID }
        restoreSelection = (audio, video, subtitle, subtitleID == "no")
        selectedVideoID = videoID == "no" ? "no" : "auto"
        videoID = selectedVideoID
        outputVideoSize = .zero
        let start = position, wasPaused = paused
        loading = true
        buffering = false
        pendingActions.append(action)
        routingReason = reason
        codec = ""
        decoder = ""
        tracks = []
        chapters = []
        startEngine(.mpv, url: url, position: start, paused: wasPaused)
    }

    private func matchingTrack(_ previous: MediaTrack?, in tracks: [MediaTrack], kind: String) -> MediaTrack? {
        guard let previous else { return nil }
        let candidates = tracks.filter { $0.kind == kind }
        if !previous.language.isEmpty, let match = candidates.first(where: {
            $0.language == previous.language || $0.language.prefix(2) == previous.language.prefix(2)
        }) { return match }
        if !previous.title.isEmpty, let match = candidates.first(where: { $0.title == previous.title }) { return match }
        if kind == "video", let match = candidates.first(where: {
            $0.codec == previous.codec && $0.width == previous.width && $0.height == previous.height
        }) { return match }
        return candidates.first { $0.id == previous.id }
    }

    private var videoEnabled: Bool {
        !musicMode && (!inBackground || pictureInPictureActive || pictureInPictureStarting)
    }

    private func updateVideoVisibility() {
        updateMPVVideoSelection()
        if let native = engine as? NativeEngine {
            surface?.nativeLayer.player = videoEnabled ? native.player : nil
        }
        pictureInPicture?.update()
    }

    private func updateMPVVideoSelection() {
        guard backend == .mpv else { return }
        let selection = videoEnabled ? selectedVideoID : "no"
        guard selection != videoOutputSelection else { return }
        videoOutputSelection = selection
        engine?.set("vid", selection)
    }

    private func synchronizeTimebase() {
        guard backend == .mpv, let base = surface?.timebase else { return }
        CMTimebaseSetTime(base, time: CMTime(seconds: position, preferredTimescale: 600))
        CMTimebaseSetRate(base, rate: paused ? 0 : speed)
    }

    private func resizeVideo() {
        guard let engine = engine as? MPVEngine else { return }
        var source = outputVideoSize.width > 0 && outputVideoSize.height > 0 ? outputVideoSize : videoSize
        source = CGSize(width: max(2, source.width), height: max(2, source.height))
        source = videoSettings.renderSize(from: source)
        let box = pictureInPictureSize ?? surface?.bounds.size ?? CGSize(width: 1280, height: 720)
        let limit = pictureInPictureSize == nil ? CGSize(width: 1280, height: 720) : CGSize(width: 960, height: 540)
        let width = min(limit.width, max(2, box.width * 2))
        let height = min(limit.height, max(2, box.height * 2))
        let scale = min(1, min(width / source.width, height / source.height))
        engine.resize(CGSize(width: floor(source.width * scale / 2) * 2,
                             height: floor(source.height * scale / 2) * 2))
    }

    func togglePictureInPicture() {
        if pictureInPictureActive || pictureInPictureStarting { pictureInPicture?.stop() }
        else { pictureInPicture?.start() }
    }

    func pictureInPictureWillStart() {
        endTouchSpeedBoost()
        pictureInPictureStarting = true
        updateVideoVisibility()
    }

    func pictureInPictureDidStart() {
        pictureInPictureStarting = false
        pictureInPictureActive = true
        updateVideoVisibility()
    }

    func pictureInPictureDidStop() {
        pictureInPictureStarting = false
        pictureInPictureActive = false
        pictureInPictureSize = nil
        resizeVideo()
        updateVideoVisibility()
        let action = afterPictureInPicture
        afterPictureInPicture = nil
        action?()
    }

    func resizePictureInPicture(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        pictureInPictureSize = size
        resizeVideo()
    }

    private func finishPendingSeek() {
        seekTimeout?.cancel()
        seekTimeout = nil
        let completion = pendingSeek?.completion
        pendingSeek = nil
        completion?()
    }

    private func receive(_ event: PlayerEvent) {
        switch event {
        case let .number(name, value):
            switch name {
            case "time-pos": position = value
            case "duration": duration = value
            case "volume": volume = value
            case "sub-delay": subtitleDelay = value
            case "secondary-sub-delay": secondarySubtitleDelay = value
            case "audio-delay": audioDelay = value
            case "video-params/w": videoSize.width = value; resizeVideo()
            case "video-params/h": videoSize.height = value; resizeVideo()
            case "video-out-params/w": outputVideoSize.width = value; resizeVideo()
            case "video-out-params/h": outputVideoSize.height = value; resizeVideo()
            default: break
            }
        case let .flag(name, value):
            if name == "pause" {
                paused = value
                if value { endTouchSpeedBoost() }
                updateIdleTimer()
            }
            if name == "paused-for-cache" { buffering = value }
        case let .text(name, value):
            switch name {
            case "aid": audioID = value
            case "vid": videoID = value
            case "sid": subtitleID = value
            case "secondary-sid": secondarySubtitleID = value
            case "media-title": if hasMedia, !value.isEmpty { title = value }
            case "hwdec-current": decoder = value
            case "video-codec": codec = value
            default: break
            }
        case let .tracks(value):
            tracks = value
            if isAudioOnly { musicMode = true }
            if backend == .native, value.contains(where: { $0.kind == "sub" }),
               subtitleStyle != SubtitleStyle() {
                withMPV("Saved subtitle appearance") {}
                return
            }
            if backend == .mpv, let selection = restoreSelection {
                restoreSelection = nil
                if let audio = matchingTrack(selection.audio, in: value, kind: "audio") { engine?.set("aid", String(audio.id)) }
                if let video = matchingTrack(selection.video, in: value, kind: "video") {
                    selectedVideoID = String(video.id)
                    updateMPVVideoSelection()
                }
                if selection.subtitlesOff { engine?.set("sid", "no") }
                else if let subtitle = matchingTrack(selection.subtitle, in: value, kind: "sub") {
                    engine?.set("sid", String(subtitle.id))
                }
            }
            updateVideoVisibility()
            updateIdleTimer()
            if let path = pendingSecondarySubtitle,
               let track = value.first(where: { $0.kind == "sub" && $0.externalPath == path }) {
                pendingSecondarySubtitle = nil
                selectSubtitle(String(track.id), target: .secondary)
            }
        case let .metadata(artist, album): self.artist = artist; self.album = album
        case let .diagnostics(value): diagnostics = value
        case let .stepping(forward, backward): canStepForward = forward; canStepBackward = backward
        case let .toolFailure(message): report(message)
        case let .videoSettingsApplied(value): appliedVideoSettings = value; resizeVideo()
        case let .requiresMPV(reason): withMPV(reason) {}
        case let .seekFinished(value):
            if let value { position = value }
            if let pendingSeek, abs(position - pendingSeek.target) < 0.5 { finishPendingSeek() }
        case let .chapters(value): chapters = value
        case .loaded:
            loading = false
            let actions = pendingActions
            pendingActions = []
            actions.forEach { $0() }
        case .ended:
            guard !reachedEnd else { return }
            endTouchSpeedBoost()
            reachedEnd = true
            if let a = loopStart, loopEnd != nil {
                seek(to: a); setPaused(false, userInitiated: false)
            } else if repeatMode == .one {
                seek(to: 0); setPaused(false, userInitiated: false)
            } else if canGoForward || repeatMode == .all { next() }
        case let .failure(message):
            if backend == .native, currentURL != nil {
                nativeFailure = message
                withMPV(message) {}
                return
            }
            loading = false
            buffering = false
            finishPendingSeek()
            report(nativeFailure.map { "Native playback: \($0)\nmpv: \(message)" } ?? message)
        }
        synchronizeTimebase()
        pictureInPicture?.update()
        mediaSession.update(force: { if case .number("time-pos", _) = event { return false }; return true }())
    }

    deinit {
        videoSettingsTask?.cancel()
        seekTimeout?.cancel()
        pendingSeek?.completion()
        engine?.requestShutdown()
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
    }
}

func playbackTime(_ seconds: Double) -> String {
    let value = Int(max(0, seconds.isFinite ? seconds : 0))
    let hours = value / 3600
    let minutes = (value % 3600) / 60
    let remainder = value % 60
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
                     : String(format: "%02d:%02d", minutes, remainder)
}
