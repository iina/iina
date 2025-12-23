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
  
  private let previousLabel = NSTextField(labelWithString: "")
  private let currentLabel  = NSTextField(labelWithString: "")
  private let nextLabel     = NSTextField(labelWithString: "")
  
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
      $0.lineBreakMode = .byTruncatingTail
      $0.maximumNumberOfLines = 1
    }
    
    // Current line (focus)
    currentLabel.textColor = NSColor.white
    currentLabel.alignment = .center
    currentLabel.lineBreakMode = .byTruncatingTail
    currentLabel.maximumNumberOfLines = 2
  }
  
  private func setupLayout() {
    stackView.orientation = .vertical
    stackView.alignment = .centerX
    stackView.distribution = .fill
    stackView.spacing = 4
    
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
    
    // ✅ Corrected: center lyrics vertically instead of bottom-anchoring
    NSLayoutConstraint.activate([
      stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
      stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
      stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
      stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
    ])
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
    
    let applyText = {
      self.previousLabel.stringValue = state.previous?.text ?? ""
      self.currentLabel.stringValue  = state.current?.text  ?? ""
      self.nextLabel.stringValue     = state.next?.text     ?? ""
    }
    
    let shouldShow = state.current != nil
    
    if animated {
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = isSameLine ? 0.0 : 0.25
        ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        self.animator().alphaValue = shouldShow ? 1.0 : 0.0
      }
      applyText()
    } else {
      alphaValue = shouldShow ? 1.0 : 0.0
      applyText()
    }
  }
}

#if DEBUG
extension LyricsOverlayView {
    func debugPreview() {
        let fake = LyricsOverlayState(
            previous: LyricsLine(time: 10, text: "I can hold my liquor"),
            current:  LyricsLine(time: 12, text: "But this man can't handle his weed"),
            next:     LyricsLine(time: 15, text: "Dark and lonely now")
        )
        update(state: fake, animated: false)
    }
}
#endif
