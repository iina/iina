//
//  TranslucentView.swift
//  iina
//
//  Created by Hechen Li on 2026-05-27.
//  Copyright © 2026 lhc. All rights reserved.
//

class TranslucentView: NSView {
  enum Style {
    @available(macOS 26.0, *)
    case liquidGlass
    case visualEffect
  }

  private var liquidGlassCornerRadius: CGFloat
  private var vevCornerRadius: CGFloat
  private var padding: (CGFloat, CGFloat)
  private var content: NSView?
  private var container: NSView?
  private var style: Style = .visualEffect

  init(liquidGlassCornerRadius: CGFloat = 16, vevCornerRadius: CGFloat = 8, padding: (CGFloat, CGFloat)) {
    self.liquidGlassCornerRadius = liquidGlassCornerRadius
    self.vevCornerRadius = vevCornerRadius
    self.padding = padding
    super.init(frame: .zero)

    self.translatesAutoresizingMaskIntoConstraints = false
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidMoveToWindow() {
    if let vev = container as? NSVisualEffectView {
      vev.state = .active
    }
  }

  func setContent(_ content: NSView) {
    self.content = content
    content.translatesAutoresizingMaskIntoConstraints = false
    setStyle(style, force: true)
  }

  func setStyle(_ newStyle: Style, force: Bool = false) {
    let force = force || (style != newStyle)
    guard let content, force else { return }

    let wrapper = NSView()
    wrapper.translatesAutoresizingMaskIntoConstraints = false

    switch newStyle {
    case .liquidGlass:
      if #available(macOS 26.0, *) {
        let view = NSGlassEffectView()
        view.cornerRadius = liquidGlassCornerRadius
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentView = content
        container = view
      } else {
        fatalError()
      }
    case .visualEffect:
      let view = NSVisualEffectView()
      view.translatesAutoresizingMaskIntoConstraints = false
      view.blendingMode = .withinWindow
      view.material = .popover
      view.addSubview(content)
      view.wantsLayer = true
      view.layer?.cornerRadius = vevCornerRadius
      container = view
    }

    // [    [         [--padding--[      ]]]]
    // self container wrapper     content
    //
    // We can't control the padding between the container (Glass/VE View)
    // and its content, so we need the wrapper

    wrapper.addSubview(content)
    content.padding(.horizontal(padding.0), .vertical(padding.1))

    container!.addSubview(wrapper)
    wrapper.padding(.all)

    subviews.forEach { $0.removeFromSuperview() }
    addSubview(container!)
    container!.padding(.all)
  }
}
