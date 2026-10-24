//
//  ThumbnailPeekView.swift
//  iina
//
//  Created by lhc on 12/6/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

final class SeekPreviewHoverController {
  static let showDelay: TimeInterval = 0.10
  static let hideDelay: TimeInterval = 0.15
  static let fadeDuration: TimeInterval = 0.15

  private var showTimer: Timer?
  private var hideTimer: Timer?
  private var fadeTimer: Timer?
  private var position: NSPoint?
  private var isVisible = false
  private let canShow: (NSPoint) -> Bool
  private let show: (NSPoint) -> Void
  private let hide: () -> Void
  private let setOpacity: (CGFloat) -> Void
  private let shouldAnimate: () -> Bool

  init(canShow: @escaping (NSPoint) -> Bool, show: @escaping (NSPoint) -> Void, hide: @escaping () -> Void,
       setOpacity: @escaping (CGFloat) -> Void = { _ in }, shouldAnimate: @escaping () -> Bool = { true }) {
    self.canShow = canShow
    self.show = show
    self.hide = hide
    self.setOpacity = setOpacity
    self.shouldAnimate = shouldAnimate
  }

  func hover(at point: NSPoint) {
    position = point
    hideTimer?.invalidate()
    hideTimer = nil
    fadeTimer?.invalidate()
    fadeTimer = nil
    setOpacity(1)
    if isVisible {
      show(point)
    } else if showTimer == nil {
      let timer = Timer(timeInterval: Self.showDelay, repeats: false) { [weak self] timer in
        guard let self, self.showTimer === timer else { return }
        self.showTimer = nil
        guard let point = self.position, self.canShow(point) else { self.cancel(); return }
        self.isVisible = true
        self.show(point)
      }
      showTimer = timer
      RunLoop.main.add(timer, forMode: .common)
    }
  }

  func leave() {
    position = nil
    showTimer?.invalidate()
    showTimer = nil
    guard isVisible, hideTimer == nil, fadeTimer == nil else { return }
    let timer = Timer(timeInterval: Self.hideDelay, repeats: false) { [weak self] timer in
      guard let self, self.hideTimer === timer else { return }
      self.hideTimer = nil
      self.fadeOut()
    }
    hideTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func fadeOut() {
    guard shouldAnimate() else { cancel(); return }
    let startedAt = ProcessInfo.processInfo.systemUptime
    let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
      guard let self, self.fadeTimer === timer else { return }
      let progress = (ProcessInfo.processInfo.systemUptime - startedAt) / Self.fadeDuration
      if progress >= 1 || !self.shouldAnimate() {
        self.cancel()
      } else {
        self.setOpacity(CGFloat(1 - progress))
      }
    }
    fadeTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func cancel(hidePreview: Bool = true) {
    showTimer?.invalidate()
    hideTimer?.invalidate()
    fadeTimer?.invalidate()
    showTimer = nil
    hideTimer = nil
    fadeTimer = nil
    position = nil
    isVisible = false
    if hidePreview { hide() }
    setOpacity(1)
  }

  deinit {
    showTimer?.invalidate()
    hideTimer?.invalidate()
    fadeTimer?.invalidate()
  }
}

class ThumbnailPeekView: NSView {

  var imageView: NSImageView!

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setup()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private func setup() {
    wantsLayer = true
    layer?.cornerRadius = 4
    layer?.masksToBounds = true
    layer?.borderWidth = 1
    layer?.borderColor = CGColor(gray: 0.6, alpha: 0.5)

    let s = NSShadow()
    s.shadowBlurRadius = 2
    s.shadowColor = .black
    shadow = s

    imageView = NSImageView()
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.wantsLayer = true
    imageView.layer?.cornerRadius = 4
    imageView.layer?.masksToBounds = true
    imageView.imageScaling = .scaleAxesIndependently
    addSubview(imageView)
    imageView.padding(.all(0))
  }

}
