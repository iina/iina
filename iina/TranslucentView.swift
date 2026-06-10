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
  var style: Style
  private var appliedStyle: Style?

  init(liquidGlassCornerRadius: CGFloat = 16, vevCornerRadius: CGFloat = 8, padding: (CGFloat, CGFloat)) {
    self.liquidGlassCornerRadius = liquidGlassCornerRadius
    self.vevCornerRadius = vevCornerRadius
    self.padding = padding
    self.style = if #available(macOS 26, *) {
      .liquidGlass
    } else {
      .visualEffect
    }
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
    self.style = newStyle
    let force = force || (appliedStyle != newStyle)
    guard let content, force else { return }

    let wrapper = NSView()
    wrapper.translatesAutoresizingMaskIntoConstraints = false

    // [    [         [--padding--[      ]]]]
    // self container wrapper     content
    //
    // We can't control the padding between the container (Glass/VE View)
    // and its content, so we need the wrapper

    wrapper.addSubview(content)
    addContentPadding()

    switch newStyle {
    case .liquidGlass:
      if #available(macOS 26.0, *) {
        let view = NSGlassEffectView()
        view.cornerRadius = liquidGlassCornerRadius
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentView = wrapper
        container = view
      } else {
        fatalError()
      }
    case .visualEffect:
      let view = NSVisualEffectView()
      view.translatesAutoresizingMaskIntoConstraints = false
      view.blendingMode = .withinWindow
      view.material = .popover
      view.addSubview(wrapper)
      wrapper.padding(.all)
      view.wantsLayer = true
      view.layer?.cornerRadius = vevCornerRadius
      container = view
    }

    subviews.forEach { $0.removeFromSuperview() }
    addSubview(container!)
    container!.padding(.all)

    appliedStyle = style
  }

  func addContentPadding() {
    content!.padding(.horizontal(padding.0), .vertical(padding.1))
  }

  func setCornerRadius(liquidGlass: CGFloat, vev: CGFloat) {
    liquidGlassCornerRadius = liquidGlass
    vevCornerRadius = vev
    switch appliedStyle {
    case .liquidGlass:
      if #available(macOS 26.0, *) {
        let view = container as! NSGlassEffectView
        view.cornerRadius = liquidGlassCornerRadius
      } else {
        fatalError()
      }
    case .visualEffect:
      let view = container as! NSVisualEffectView
      view.layer?.cornerRadius = vevCornerRadius
    default:
      break
    }
  }
}
