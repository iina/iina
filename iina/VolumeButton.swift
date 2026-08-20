//
//  VolumeButton.swift
//  iina
//
//  Created by Hechen Li on 2026-07-04.
//  Copyright © 2026 lhc. All rights reserved.
//


class VolumeButton: NSView {
  let imageView: NSImageView
  weak var player: PlayerCore!

  var target: Any?
  var action: Selector?

  private var previousIcon: String?
  private var isPressed = false
  private var eventMonitor: Any?

  init(player: PlayerCore, target: Any? = nil, action: Selector? = nil) {
    self.target = target
    self.action = action
    self.player = player

    self.imageView = NSImageView()
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.imageScaling = .scaleProportionallyDown

    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false
    addSubview(imageView)
    imageView.padding(.all)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
    }
  }

  override func mouseDown(with event: NSEvent) {
    guard eventMonitor == nil else { return }
    setPressed(true)
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) {
      [weak self] event in
      guard let self, event.window === window else { return event }

      let location = convert(event.locationInWindow, from: nil)
      switch event.type {
      case .leftMouseDragged:
        setPressed(bounds.contains(location))
      case .leftMouseUp:
        let shouldTrigger = bounds.contains(location)
        if let eventMonitor {
          NSEvent.removeMonitor(eventMonitor)
          self.eventMonitor = nil
        }
        setPressed(false)
        if shouldTrigger, let target, let action {
          NSApp.sendAction(action, to: target, from: self)
        }
      default:
        break
      }
      return nil
    }
  }

  private func setPressed(_ pressed: Bool) {
    guard isPressed != pressed else { return }
    isPressed = pressed
    guard !Preference.bool(for: .disableAnimations) else {
      imageView.alphaValue = pressed ? 0.55 : 1
      return
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = pressed ? 0.06 : 0.14
      context.timingFunction = CAMediaTimingFunction(name: pressed ? .easeInEaseOut : .easeOut)
      imageView.animator().alphaValue = pressed ? 0.55 : 1
    }
  }

  func update() {
    let res = volumeIcon()
    guard let icon = res.image, res.name != previousIcon else { return }
    let useReplace = (previousIcon?.contains("slash") ?? false) || (res.name.contains("slash"))
    if #available(macOS 15.0, *), useReplace {
      imageView.setSymbolImage(icon, contentTransition: .replace.offUp)
    } else {
      imageView.image = icon
    }
    previousIcon = res.name
  }

  private func volumeIcon() -> (image: NSImage?, name: String) {
    guard let player, !player.info.isMuted else {
      let name = "speaker.slash.fill"
      return (.sf(name), name)
    }
    let volume = Int(player.info.volume)
    guard volume >= 0 else {
      return (nil, "")
    }
    let symbol = switch Int(player.info.volume) {
    case 0: "speaker.fill"
    case 1...33: "speaker.wave.1.fill"
    case 34...66: "speaker.wave.2.fill"
    default: "speaker.wave.3.fill"
    }
    let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
    return (.sf(symbol, withConfiguration: configuration), symbol)
  }
}
