//
//  AccentSwitch.swift
//  iina
//

import Cocoa
import SwiftUI

/// A native SwiftUI switch with NSButton's Cocoa bindings and target/action contract.
/// NSSwitch has no public tint property, while SwiftUI's switch accepts any Color.
class AccentSwitch: NSButton {
  private final class Model: ObservableObject {
    @Published var isOn = false
    @Published var isEnabled = true
    @Published var controlSize = SwiftUI.ControlSize.regular
  }

  private struct Content: View {
    @ObservedObject var model: Model
    let changed: (Bool) -> Void

    var body: some View {
      Toggle("", isOn: Binding(get: { model.isOn }, set: changed))
        .toggleStyle(.switch)
        .labelsHidden()
        .controlSize(model.controlSize)
        .tint(Color(nsColor: AppAccentColor.color))
        .disabled(!model.isEnabled)
        .fixedSize()
        // The enclosing NSButton supplies the single Cocoa accessibility element.
        .accessibilityHidden(true)
    }
  }

  private let model = Model()
  private var hostingView: NSHostingView<Content>?
  private var colorsObserver: NSObjectProtocol?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  deinit {
    if let colorsObserver { NotificationCenter.default.removeObserver(colorsObserver) }
  }

  private func configure() {
    setButtonType(.switch)
    title = ""
    allowsMixedState = false
    setAccessibilityElement(true)
    setAccessibilityRole(.checkBox)
    setAccessibilitySubrole(.switch)
    setAccessibilityChildren([])

    let host = NSHostingView(rootView: Content(model: model) { [weak self] isOn in
      self?.hostedValueChanged(isOn)
    })
    host.translatesAutoresizingMaskIntoConstraints = false
    host.setAccessibilityElement(false)
    addSubview(host)
    NSLayoutConstraint.activate([
      host.leadingAnchor.constraint(equalTo: leadingAnchor),
      host.trailingAnchor.constraint(equalTo: trailingAnchor),
      host.topAnchor.constraint(equalTo: topAnchor),
      host.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    hostingView = host
    synchronizeModel()
    colorsObserver = NotificationCenter.default.addObserver(
      forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.model.objectWillChange.send()
    }
  }

  override var state: NSControl.StateValue {
    didSet { synchronizeModel() }
  }

  override var isEnabled: Bool {
    didSet { synchronizeModel() }
  }

  override var controlSize: NSControl.ControlSize {
    didSet {
      synchronizeModel()
      invalidateIntrinsicContentSize()
    }
  }

  override var intrinsicContentSize: NSSize {
    hostingView?.intrinsicContentSize ?? super.intrinsicContentSize
  }

  override func sizeToFit() {
    frame.size = intrinsicContentSize
  }

  // Keyboard focus belongs to the hosted native Toggle, avoiding two tab stops.
  override var acceptsFirstResponder: Bool { false }

  // Keep the inherited checkbox cell for value bindings and target/action.
  // Only the hosted native switch draws the control.
  override func draw(_ dirtyRect: NSRect) {}

  override func performClick(_ sender: Any?) {
    super.performClick(sender)
    synchronizeModel()
  }

  override func accessibilityValue() -> Any? {
    NSNumber(value: state == .on)
  }

  override func accessibilityPerformPress() -> Bool {
    guard isEnabled else { return false }
    performClick(nil)
    return true
  }

  override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
    synchronizeModel()
    defer { synchronizeModel() }
    return super.sendAction(action, to: target)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    model.objectWillChange.send()
  }

  private func hostedValueChanged(_ isOn: Bool) {
    guard isEnabled, isOn != (state == .on) else { return }
    // NSButton's normal click path writes the value binding and invokes the
    // target exactly once. The target may synchronously revert the state.
    super.performClick(nil)
    synchronizeModel()
  }

  private func synchronizeModel() {
    let isOn = state == .on
    if model.isOn != isOn { model.isOn = isOn }
    if model.isEnabled != isEnabled { model.isEnabled = isEnabled }
    let size: SwiftUI.ControlSize
    switch controlSize {
    case .mini: size = .mini
    case .small: size = .small
    case .large: size = .large
    default: size = .regular
    }
    if model.controlSize != size { model.controlSize = size }
  }
}
