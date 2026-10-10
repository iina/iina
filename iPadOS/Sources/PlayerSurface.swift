// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import AVFoundation
import SwiftUI
import UIKit

final class VideoSurfaceView: UIView {
    let nativeLayer = AVPlayerLayer()
    let sampleLayer = AVSampleBufferDisplayLayer()
    let timebase: CMTimebase
    var onResize: ((CGSize) -> Void)?
    var onFramePresented: ((CMSampleBuffer) -> Void)?
    var onSingleTap: (() -> Void)?
    var onDoubleTap: (() -> Void)?
    var onSpeedHold: ((Bool) -> Void)?
    var onSeekSwipe: ((Double) -> Void)?
    var onControlKey: ((PlayerControlAction) -> Void)?
    var controlPreferences = ControlPreferences()
    var keyboardEnabled = false
    private let speedHold = UILongPressGestureRecognizer()
    private let forwardSwipe = UISwipeGestureRecognizer()
    private let backwardSwipe = UISwipeGestureRecognizer()
    var seekSeconds = 10.0
    var holdEnabled = true { didSet { updateGestures() } }
    var swipeEnabled = true { didSet { updateGestures() } }
    var playbackGesturesEnabled = false {
        didSet { updateGestures() }
    }
    private func updateGestures() {
        let hold = playbackGesturesEnabled && holdEnabled
        let swipe = playbackGesturesEnabled && swipeEnabled
        // Assigning isEnabled even to its current value can reset an active
        // recognizer. Playback updates must not cancel a finger being held.
        if speedHold.isEnabled != hold { speedHold.isEnabled = hold }
        if forwardSwipe.isEnabled != swipe { forwardSwipe.isEnabled = swipe }
        if backwardSwipe.isEnabled != swipe { backwardSwipe.isEnabled = swipe }
    }
    private(set) var presentedFrames = 0
    private(set) var presentedSize = CGSize.zero

    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? {
        guard keyboardEnabled else { return [] }
        return PlayerControlAction.allCases.map { action in
            let shortcut = controlPreferences.shortcut(for: action)
            let command = UIKeyCommand(input: shortcut.input, modifierFlags: shortcut.modifierFlags,
                                       action: #selector(controlKeyPressed))
            command.discoverabilityTitle = action.rawValue
            return command
        }
    }

    @objc private func controlKeyPressed(_ command: UIKeyCommand) {
        guard keyboardEnabled, window?.rootViewController?.presentedViewController == nil else { return }
        if let action = PlayerControlAction.allCases.first(where: {
            let shortcut = controlPreferences.shortcut(for: $0)
            return command.input == shortcut.input && command.modifierFlags == shortcut.modifierFlags
        }) { onControlKey?(action) }
    }

    func focusPlaybackKeyboard() {
        guard keyboardEnabled, !isFirstResponder, let window,
              window.rootViewController?.presentedViewController == nil else { return }
        func typing(in view: UIView) -> Bool {
            if view.isFirstResponder && view is UITextInput { return true }
            return view.subviews.contains { typing(in: $0) }
        }
        if !typing(in: window) { becomeFirstResponder() }
    }

    override init(frame: CGRect) {
        var base: CMTimebase?
        let status = CMTimebaseCreateWithSourceClock(allocator: nil, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &base)
        guard status == noErr, let base else { fatalError("Unable to create the video timebase: \(status).") }
        timebase = base
        super.init(frame: frame)
        backgroundColor = .black
        nativeLayer.videoGravity = .resizeAspect
        sampleLayer.videoGravity = .resizeAspect
        sampleLayer.controlTimebase = timebase
        sampleLayer.isOpaque = true
        sampleLayer.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(nativeLayer)
        layer.addSublayer(sampleLayer)
        nativeLayer.isHidden = true
        sampleLayer.isHidden = true
        isAccessibilityElement = false
        accessibilityIdentifier = "videoSurface"
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
        doubleTap.numberOfTapsRequired = 2
        speedHold.addTarget(self, action: #selector(speedHeld))
        speedHold.minimumPressDuration = 0.4
        speedHold.allowableMovement = 24
        forwardSwipe.direction = .right
        backwardSwipe.direction = .left
        for swipe in [forwardSwipe, backwardSwipe] {
            swipe.addTarget(self, action: #selector(swiped))
            swipe.require(toFail: speedHold)
        }
        for tap in [singleTap, doubleTap] {
            tap.require(toFail: speedHold)
            tap.require(toFail: forwardSwipe)
            tap.require(toFail: backwardSwipe)
        }
        singleTap.require(toFail: doubleTap)
        for gesture in [singleTap, doubleTap, speedHold, forwardSwipe, backwardSwipe] {
            addGestureRecognizer(gesture)
        }
        speedHold.isEnabled = false
        forwardSwipe.isEnabled = false
        backwardSwipe.isEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("VideoSurfaceView uses programmatic initialization.") }

    @objc private func singleTapped(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended { focusPlaybackKeyboard(); onSingleTap?() }
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended { onDoubleTap?() }
    }

    @objc private func speedHeld(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began: onSpeedHold?(true)
        case .ended, .cancelled, .failed: onSpeedHold?(false)
        default: break
        }
    }

    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .ended else { return }
        onSeekSwipe?(gesture.direction == .right ? seekSeconds : -seekSeconds)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        nativeLayer.frame = bounds
        sampleLayer.frame = bounds
        CATransaction.commit()
        onResize?(bounds.size)
    }

    func show(_ backend: PlaybackBackend, fill: Bool) {
        nativeLayer.isHidden = backend != .native
        sampleLayer.isHidden = backend != .mpv
        nativeLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        sampleLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }

    func enqueue(_ frame: CMSampleBuffer) {
        if sampleLayer.status == .failed { sampleLayer.flush() }
        guard sampleLayer.isReadyForMoreMediaData else { return }
        sampleLayer.enqueue(frame)
        if let format = CMSampleBufferGetFormatDescription(frame) {
            let size = CMVideoFormatDescriptionGetDimensions(format)
            presentedSize = CGSize(width: Int(size.width), height: Int(size.height))
        }
        presentedFrames += 1
        onFramePresented?(frame)
    }
}

struct PlayerSurface: UIViewRepresentable {
    let model: PlayerModel
    var onSingleTap: (() -> Void)? = nil
    var onDoubleTap: (() -> Void)? = nil
    var onSeekSwipe: ((Double) -> Void)? = nil
    var onControlKey: ((PlayerControlAction) -> Void)? = nil

    func makeUIView(context: Context) -> VideoSurfaceView {
        let surface = VideoSurfaceView(frame: .zero)
        // Engine readiness publishes state; start after SwiftUI's view-update transaction.
        DispatchQueue.main.async { [weak surface, weak model] in
            guard let surface, let model else { return }
            model.attach(to: surface)
        }
        return surface
    }

    func updateUIView(_ uiView: VideoSurfaceView, context: Context) {
        uiView.onSingleTap = onSingleTap
        uiView.onDoubleTap = onDoubleTap
        uiView.onSpeedHold = { [weak model] holding in
            if holding { model?.beginTouchSpeedBoost() }
            else { model?.endTouchSpeedBoost() }
        }
        uiView.onSeekSwipe = { [weak model] seconds in
            guard let model, model.canUsePlaybackGestures else { return }
            model.skip(seconds)
            onSeekSwipe?(seconds)
        }
        uiView.playbackGesturesEnabled = model.canUsePlaybackGestures
        uiView.holdEnabled = model.controlPreferences.holdEnabled
        uiView.swipeEnabled = model.controlPreferences.swipeEnabled
        uiView.seekSeconds = model.controlPreferences.seekSeconds
        uiView.controlPreferences = model.controlPreferences
        uiView.keyboardEnabled = model.hasMedia && !model.showingJumpToTime && model.capturedFrame == nil
        uiView.onControlKey = onControlKey
    }

    static func dismantleUIView(_ uiView: VideoSurfaceView, coordinator: ()) {
        uiView.onSpeedHold?(false)
        uiView.onSingleTap = nil
        uiView.onDoubleTap = nil
        uiView.onSpeedHold = nil
        uiView.onSeekSwipe = nil
        uiView.onControlKey = nil
    }
}

private extension PlayerShortcut {
    var input: String {
        switch self {
        case .space: return " "
        case .left: return UIKeyCommand.inputLeftArrow
        case .right: return UIKeyCommand.inputRightArrow
        case .up: return UIKeyCommand.inputUpArrow
        case .down: return UIKeyCommand.inputDownArrow
        case .j, .commandJ: return "j"
        case .k: return "k"
        case .l: return "l"
        case .a: return "a"
        case .b: return "b"
        case .r: return "r"
        case .comma: return ","
        case .period: return "."
        case .commandS: return "s"
        }
    }
    var modifierFlags: UIKeyModifierFlags { self == .commandS || self == .commandJ ? .command : [] }
}
