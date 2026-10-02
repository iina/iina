//
//  VolumeButton.swift
//  iina
//
//  Created by Hechen Li on 2026-07-04.
//  Copyright © 2026 lhc. All rights reserved.
//


class VolumeButton: NSButton {
  weak var player: PlayerCore!

  private var previousIcon: String?
  private var usesQuickTimeStyle = false

  init(player: PlayerCore, target: AnyObject? = nil, action: Selector? = nil) {
    self.player = player
    super.init(frame: .zero)
    self.target = target
    self.action = action
    translatesAutoresizingMaskIntoConstraints = false
    bezelStyle = .shadowlessSquare
    isBordered = false
    imagePosition = .imageOnly
    imageScaling = .scaleProportionallyDown
    setButtonType(.momentaryPushIn)
    refusesFirstResponder = true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func update() {
    let res = volumeIcon()
    guard let icon = res.image, res.name != previousIcon else { return }
    image = icon
    previousIcon = res.name
  }

  func setQuickTimeStyle(_ enabled: Bool) {
    usesQuickTimeStyle = enabled
    previousIcon = nil
    update()
  }

  private func volumeIcon() -> (image: NSImage?, name: String) {
    let pointSize: CGFloat = usesQuickTimeStyle ? 17 : 13
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    guard let player, !player.info.isMuted else {
      let name = "speaker.slash.fill"
      return (.sf(name, withConfiguration: configuration), name)
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
    return (.sf(symbol, withConfiguration: configuration), symbol)
  }
}
