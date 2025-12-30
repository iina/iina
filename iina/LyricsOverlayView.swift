//
//  LyricsOverlayView.swift
//  iina
//
//  Created by Erik Molina on 12/21/25.
//

import Cocoa

final class LyricsOverlayView: NSView {
  
  // MARK: - UI Elements
  
  private let stackView = NSStackView()
  private let backdropView = NSVisualEffectView()
  
  // Legacy labels (kept for backward compatibility during transition)
  private let previousLabel = NSTextField(labelWithString: "")
  private let currentLabel  = NSTextField(labelWithString: "")
  private let nextLabel     = NSTextField(labelWithString: "")
  
  // New: Dynamic labels for scrollable view
  private var lineLabels: [NSTextField] = []
  
  // MARK: - State
  
  private var currentState: LyricsOverlayState?
  
  // MARK: - Init
  
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setupView()
    setupLabels()
    setupLayout()
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
    setupLabels()
    setupLayout()
  }
  
  // MARK: - View setup
  
  private func setupView() {
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    alphaValue = 0.0
    
    backdropView.material = .hudWindow
    backdropView.blendingMode = .withinWindow
    backdropView.state = .active
    backdropView.wantsLayer = true
    backdropView.layer?.cornerRadius = 8
    backdropView.layer?.masksToBounds = true
    
    addSubview(backdropView, positioned: .below, relativeTo: stackView)
  }
  
  private func setupLabels() {
    // Previous / next (dim)
    [previousLabel, nextLabel].forEach {
      $0.textColor = NSColor.white.withAlphaComponent(0.55)
      $0.alignment = .center
      $0.lineBreakMode = .byWordWrapping
      $0.maximumNumberOfLines = 2
    }
    
    // Current line (focus)
    currentLabel.textColor = NSColor.white
    currentLabel.alignment = .center
    currentLabel.lineBreakMode = .byWordWrapping
    currentLabel.maximumNumberOfLines = 2
  }
  
  private func setupLayout() {
    stackView.orientation = .vertical
    stackView.alignment = .centerX
    stackView.distribution = .fill
    stackView.spacing = 4
    
    // Add legacy labels (will be replaced by dynamic labels when allLines is available)
    stackView.addArrangedSubview(previousLabel)
    stackView.addArrangedSubview(currentLabel)
    stackView.addArrangedSubview(nextLabel)
    
    addSubview(stackView)
    
    stackView.translatesAutoresizingMaskIntoConstraints = false
    backdropView.translatesAutoresizingMaskIntoConstraints = false
    
    // Backdrop hugs the text stack
    NSLayoutConstraint.activate([
      backdropView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: -8),
      backdropView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: 8),
      backdropView.topAnchor.constraint(equalTo: stackView.topAnchor, constant: -6),
      backdropView.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 6)
    ])
    
    // Center lyrics vertically and constrain width to prevent window resizing
    NSLayoutConstraint.activate([
      stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
      stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
      stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
      stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
      stackView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48) // Max width with 24pt margins on each side
    ])
  }
  
  // MARK: - Dynamic line labels
  
  private func ensureLabelCount(_ count: Int) {
    // Remove excess labels
    while lineLabels.count > count {
      let label = lineLabels.removeLast()
      label.removeFromSuperview()
    }
    
    // Add missing labels
    while lineLabels.count < count {
      let label = NSTextField(labelWithString: "")
      label.alignment = .center
      label.lineBreakMode = .byWordWrapping
      label.maximumNumberOfLines = 2
      label.translatesAutoresizingMaskIntoConstraints = false
      lineLabels.append(label)
    }
  }
  
  private func updateLabelsWithAllLines(_ allLines: [LyricsLine], currentIndex: Int) {
    // Remove legacy labels from stack if they're still there
    if stackView.views.contains(previousLabel) {
      stackView.removeView(previousLabel)
    }
    if stackView.views.contains(currentLabel) {
      stackView.removeView(currentLabel)
    }
    if stackView.views.contains(nextLabel) {
      stackView.removeView(nextLabel)
    }
    
    // Ensure we have enough labels
    ensureLabelCount(allLines.count)
    
    // Add all labels to stack
    for label in lineLabels {
      if !stackView.views.contains(label) {
        stackView.addArrangedSubview(label)
      }
    }
    
    // Update label text and styling
    for (index, line) in allLines.enumerated() {
      guard index < lineLabels.count else { continue }
      let label = lineLabels[index]
      label.stringValue = line.text
      
      // Apply visual hierarchy
      let distanceFromCurrent = abs(index - currentIndex)
      let baseSize = max(min(bounds.height * 0.045, 36), 14)
      
      if index == currentIndex {
        // Current line: full opacity, larger, semibold
        label.textColor = NSColor.white
        label.font = NSFont.systemFont(ofSize: baseSize, weight: .semibold)
        label.alphaValue = 1.0
      } else {
        // Other lines: reduced opacity and size based on distance
        let opacity: CGFloat
        let sizeMultiplier: CGFloat
        
        switch distanceFromCurrent {
        case 1:
          opacity = 0.7
          sizeMultiplier = 0.85
        case 2:
          opacity = 0.5
          sizeMultiplier = 0.70
        default:
          opacity = 0.3
          sizeMultiplier = 0.60
        }
        
        label.textColor = NSColor.white.withAlphaComponent(opacity)
        label.font = NSFont.systemFont(ofSize: max(baseSize * sizeMultiplier, 11), weight: .regular)
        label.alphaValue = opacity
      }
    }
  }
  
  // MARK: - Responsive fonts
  
  private func updateFonts(for height: CGFloat) {
    let baseSize = max(min(height * 0.045, 36), 14)
    
    previousLabel.font = NSFont.systemFont(
      ofSize: max(baseSize * 0.7, 11),
      weight: .regular
    )
    
    currentLabel.font = NSFont.systemFont(
      ofSize: baseSize,
      weight: .semibold
    )
    
    nextLabel.font = NSFont.systemFont(
      ofSize: max(baseSize * 0.7, 11),
      weight: .regular
    )
  }
  
  override func layout() {
    super.layout()
    
#if DEBUG
    print("🎵 LyricsOverlayView layout — height =", bounds.height)
#endif
    
    updateFonts(for: bounds.height)
    
    // Update label preferred max width for proper text wrapping
    let maxLabelWidth = max(bounds.width - 48, 200) // 24pt margins on each side, minimum 200pt
    for label in lineLabels {
      label.preferredMaxLayoutWidth = maxLabelWidth
    }
    // Also update legacy labels
    previousLabel.preferredMaxLayoutWidth = maxLabelWidth
    currentLabel.preferredMaxLayoutWidth = maxLabelWidth
    nextLabel.preferredMaxLayoutWidth = maxLabelWidth
  }
  
  override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()

      guard let superview = superview else { return }

      translatesAutoresizingMaskIntoConstraints = false

      NSLayoutConstraint.activate([
          leadingAnchor.constraint(equalTo: superview.leadingAnchor),
          trailingAnchor.constraint(equalTo: superview.trailingAnchor),
          topAnchor.constraint(equalTo: superview.topAnchor),
          bottomAnchor.constraint(equalTo: superview.bottomAnchor)
      ])
  }
  
  override var intrinsicContentSize: NSSize {
      return NSSize(width: NSView.noIntrinsicMetric,
                    height: NSView.noIntrinsicMetric)
  }



  
  // MARK: - Public API
  
  func update(state: LyricsOverlayState, animated: Bool = true) {
    let isSameLine = currentState?.current?.time == state.current?.time
    currentState = state
    
    let shouldShow = state.current != nil
    
    // Use new allLines if available, otherwise fall back to legacy 3-line display
    if !state.allLines.isEmpty && state.currentIndex >= 0 {
      // New scrollable view mode
      updateLabelsWithAllLines(state.allLines, currentIndex: state.currentIndex)
    } else {
      // Clear dynamic labels if they exist
      for label in lineLabels {
        if stackView.views.contains(label) {
          stackView.removeView(label)
        }
        label.stringValue = ""
      }
      
      // Restore legacy labels if they're not in the stack
      if !stackView.views.contains(previousLabel) {
        stackView.insertArrangedSubview(previousLabel, at: 0)
      }
      if !stackView.views.contains(currentLabel) {
        let insertIndex = stackView.views.contains(previousLabel) ? 1 : 0
        stackView.insertArrangedSubview(currentLabel, at: insertIndex)
      }
      if !stackView.views.contains(nextLabel) {
        stackView.addArrangedSubview(nextLabel)
      }
      
      // Legacy 3-line mode (fallback)
      let applyText = {
        self.previousLabel.stringValue = state.previous?.text ?? ""
        self.currentLabel.stringValue  = state.current?.text  ?? ""
        self.nextLabel.stringValue     = state.next?.text     ?? ""
      }
      applyText()
    }
    
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
}
