//
//  LyricsOverlayView.swift
//  iina
//
//  Created by Erik Molina on 12/21/25.
//

import Cocoa

final class LyricsOverlayView: NSView {
  
  // MARK: - Metrics
  
  private enum Metrics {
    static let backdropInsetRatio: CGFloat = 0.10 // Keep overlay inset so lyrics avoid window edges.
    static let cornerRadiusMin: CGFloat = 8
    static let cornerRadiusRatio: CGFloat = 0.03 // Scale radius a bit with height for large overlays.
    static let stackSpacing: CGFloat = 4
    static let horizontalMargin: CGFloat = 24
    static let widthPadding: CGFloat = horizontalMargin * 2
    static let fontScale: CGFloat = 0.045 // Base font tied to view height for consistent sizing.
    static let fontMin: CGFloat = 14
    static let fontMax: CGFloat = 36
    static let nonCurrentFontMin: CGFloat = 11 // Floor to keep distant lines readable.
    static let sizeMultiplierNear: CGFloat = 0.85
    static let sizeMultiplierMid: CGFloat = 0.70
    static let sizeMultiplierFar: CGFloat = 0.60
    static let opacityNear: CGFloat = 0.7
    static let opacityMid: CGFloat = 0.5
    static let opacityFar: CGFloat = 0.3
    static let lineHeightFactor: CGFloat = 1.35 // NSTextField line height ~1.3–1.4x font size.
    static let maxLabelCount = 21 // Defensive cap; engine currently sends a 7-line window.
    static let visibleMin = 5
    static let visibleMax = 21
    static let visibleDefault = 7
    static let maxLabelWidthFallback: CGFloat = 200
  }
  
  // MARK: - UI Elements
  
  private let stackView = NSStackView()
  private let backdropView = NSVisualEffectView()
  private var backdropLeading: NSLayoutConstraint!
  private var backdropTrailing: NSLayoutConstraint!
  private var backdropTop: NSLayoutConstraint!
  private var backdropBottom: NSLayoutConstraint!
  private var lineLabels: [NSTextField] = []
  
  // MARK: - State
  
  private var currentState: LyricsOverlayState?
  private var lastRenderedBoundsSize: NSSize = .zero
  
  // MARK: - Init
  
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setupView()
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }
  
  // MARK: - View setup
  
  private func setupView() {
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    alphaValue = 0.0
    
    stackView.orientation = .vertical
    stackView.alignment = .centerX
    stackView.distribution = .fill
    stackView.spacing = Metrics.stackSpacing
    stackView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stackView)
    
    backdropView.material = .hudWindow
    backdropView.blendingMode = .withinWindow
    backdropView.state = .active
    backdropView.wantsLayer = true
    backdropView.layer?.masksToBounds = true
    backdropView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(backdropView, positioned: .below, relativeTo: stackView)
    
    backdropLeading = backdropView.leadingAnchor.constraint(equalTo: leadingAnchor)
    backdropTrailing = backdropView.trailingAnchor.constraint(equalTo: trailingAnchor)
    backdropTop = backdropView.topAnchor.constraint(equalTo: topAnchor)
    backdropBottom = backdropView.bottomAnchor.constraint(equalTo: bottomAnchor)

    NSLayoutConstraint.activate([
      backdropLeading,
      backdropTrailing,
      backdropTop,
      backdropBottom,
      stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
      stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
      stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Metrics.horizontalMargin),
      stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Metrics.horizontalMargin),
      stackView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -Metrics.widthPadding)
    ])
  }
  
  // MARK: - Dynamic line labels

  // Ensure we have enough labels for the given line count, capped at max.
  private func ensureLabelCount(for lineCount: Int) {
    let cappedCount = min(lineCount, Metrics.maxLabelCount)
    while lineLabels.count > cappedCount {
      let label = lineLabels.removeLast()
      stackView.removeArrangedSubview(label)
      label.removeFromSuperview()
    }
    while lineLabels.count < cappedCount {
      let label = NSTextField(labelWithString: "")
      label.alignment = .center
      label.lineBreakMode = .byWordWrapping
      label.maximumNumberOfLines = 2
      label.translatesAutoresizingMaskIntoConstraints = false
      lineLabels.append(label)
    }
  }
  
  private func syncArrangedSubviews() {
    for view in stackView.arrangedSubviews where !lineLabels.contains(where: { $0 === view }) {
      stackView.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
    for label in lineLabels where !stackView.arrangedSubviews.contains(label) {
      stackView.addArrangedSubview(label)
    }
  }
  
  private func render(allLines: [LyricsLine], currentIndex: Int) {
    ensureLabelCount(for: allLines.count)
    syncArrangedSubviews()
    guard !lineLabels.isEmpty else { return }
    lastRenderedBoundsSize = bounds.size
    let baseSize = max(min(bounds.height * Metrics.fontScale, Metrics.fontMax), Metrics.fontMin)
    let clampedCurrentIndex = min(currentIndex, lineLabels.count - 1)
    for (index, line) in allLines.enumerated() {
      guard index < lineLabels.count else { continue }
      let label = lineLabels[index]
      label.stringValue = line.text
      let distanceFromCurrent = abs(index - clampedCurrentIndex)
      if index == clampedCurrentIndex {
        label.textColor = .white
        label.font = NSFont.systemFont(ofSize: baseSize, weight: .semibold)
        label.alphaValue = 1.0
      } else {
        let opacity: CGFloat
        let sizeMultiplier: CGFloat
        switch distanceFromCurrent {
        case 1:
          opacity = Metrics.opacityNear
          sizeMultiplier = Metrics.sizeMultiplierNear
        case 2:
          opacity = Metrics.opacityMid
          sizeMultiplier = Metrics.sizeMultiplierMid
        default:
          opacity = Metrics.opacityFar
          sizeMultiplier = Metrics.sizeMultiplierFar
        }
        label.textColor = NSColor.white.withAlphaComponent(opacity)
        label.font = NSFont.systemFont(ofSize: max(baseSize * sizeMultiplier, Metrics.nonCurrentFontMin), weight: .regular)
        label.alphaValue = opacity
      }
    }
  }
  
  private func clearLabels() {
    ensureLabelCount(for: 0)
  }
  
  // MARK: - Layout
  
  override func layout() {
    super.layout()
    let insetX = bounds.width * Metrics.backdropInsetRatio
    let insetY = bounds.height * Metrics.backdropInsetRatio
    backdropLeading.constant = insetX
    backdropTrailing.constant = -insetX
    backdropTop.constant = insetY
    backdropBottom.constant = -insetY
    backdropView.layer?.cornerRadius = max(Metrics.cornerRadiusMin, bounds.height * Metrics.cornerRadiusRatio)
    let maxLabelWidth = max(bounds.width - insetX * 2, Metrics.maxLabelWidthFallback)
    for label in lineLabels {
      label.preferredMaxLayoutWidth = maxLabelWidth
    }
    if let currentState,
       bounds.size != lastRenderedBoundsSize,
       !currentState.allLines.isEmpty,
       currentState.currentIndex >= 0 {
      render(allLines: currentState.allLines, currentIndex: currentState.currentIndex)
    }
  }
  
  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
  }
  
  // MARK: - Public API
  
  func update(state: LyricsOverlayState, animated: Bool = true) {
    let isSameLine = currentState?.current?.time == state.current?.time
    currentState = state
    if !state.allLines.isEmpty && state.currentIndex >= 0 {
      render(allLines: state.allLines, currentIndex: state.currentIndex)
    } else {
      clearLabels()
    }
    let shouldShow = state.current != nil
    if animated {
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = isSameLine ? 0.0 : 0.25
        ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        self.animator().alphaValue = shouldShow ? 1.0 : 0.0
      }
    } else {
      alphaValue = shouldShow ? 1.0 : 0.0
    }
  }

  // MARK: - Visible line calculation

  /// Estimates how many single-line rows fit; labels allow two lines but we size conservatively.
  func visibleLineCount() -> Int {
    guard bounds.height > 0 else { return Metrics.visibleDefault }
    let insetY = bounds.height * Metrics.backdropInsetRatio
    let availableHeight = max(bounds.height - insetY * 2, 0)
    let baseFontSize = max(min(bounds.height * Metrics.fontScale, Metrics.fontMax), Metrics.fontMin)
    let estimatedLineHeight = baseFontSize * Metrics.lineHeightFactor
    let effectiveLineHeight = estimatedLineHeight + Metrics.stackSpacing
    guard effectiveLineHeight > 0 else { return Metrics.visibleDefault }
    let rawCount = Int(availableHeight / effectiveLineHeight)
    let clamped = max(Metrics.visibleMin, min(rawCount, Metrics.visibleMax))
    let oddAligned = clamped % 2 == 0 ? clamped - 1 : clamped
    return max(Metrics.visibleMin, oddAligned)
  }

}
