//
//  VR2DSubtitleView.swift
//  iina
//
//  Subtitles for a reprojected video.
//
//  mpv composites subtitles into the same framebuffer as the video, and the
//  render API offers no way to separate them, so with reprojection on they get
//  warped onto the sphere along with the picture: magnified past reading at the
//  centre of the view, smeared around the pole at the bottom of the frame,
//  where mpv puts them.
//
//  So mpv is told not to draw them, and they are drawn here instead — as an
//  ordinary view over the flattened picture, where they sit still, stay
//  legible, and land where subtitles are supposed to land.
//
//  The styling comes from mpv, via `PlayerCore.vr2dSubtitleStyle()`. mpv holds
//  the effective values — IINA has already pushed its settings there, and so has
//  `mpv.conf` — so reading them back beats keeping a second copy of that
//  mapping, and it catches settings that never went through the preferences.
//
//  This only works for subtitles that have text. Picture-based ones (PGS,
//  VobSub) have none to read, and are left to mpv.
//

import Cocoa

/// How mpv would have drawn a subtitle. Gathered by `PlayerCore`, because only
/// `VideoView` and `MPVController` may read mpv directly.
struct VR2DSubtitleStyle {
  var fontName: String
  var fontSize: Double
  var scale: Double
  var scaleByWindow: Bool
  var bold: Bool
  var italic: Bool
  var color: NSColor?
  var borderColor: NSColor?
  var borderSize: Double
  var backColor: NSColor?
  var shadowColor: NSColor?
  var shadowOffset: Double
  var blur: Double
  var spacing: Double
  var alignX: String
  var marginX: Double
  var marginY: Double
  var position: Double
}

class VR2DSubtitleView: NSView {

  private let label = NSTextField(labelWithString: "")
  private var bottomConstraint: NSLayoutConstraint!
  private var leadingConstraint: NSLayoutConstraint!
  private var trailingConstraint: NSLayoutConstraint!
  /// Only one of these is active at a time, chosen by `sub-align-x`.
  private var alignLeftConstraint: NSLayoutConstraint!
  private var alignCentreConstraint: NSLayoutConstraint!
  private var alignRightConstraint: NSLayoutConstraint!

  /// The player whose subtitle settings are being mirrored.
  weak var player: PlayerCore?

  var text: String = "" {
    didSet {
      guard text != oldValue else { return }
      isHidden = text.isEmpty
      render()
    }
  }

  init() {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    isHidden = true

    label.translatesAutoresizingMaskIntoConstraints = false
    label.maximumNumberOfLines = 0
    label.lineBreakMode = .byWordWrapping
    label.isSelectable = false
    label.cell?.wraps = true
    label.drawsBackground = false
    addSubview(label)

    bottomConstraint = label.bottomAnchor.constraint(equalTo: bottomAnchor)
    leadingConstraint = label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor)
    trailingConstraint = trailingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor)
    alignLeftConstraint = label.leadingAnchor.constraint(equalTo: leadingAnchor)
    alignCentreConstraint = label.centerXAnchor.constraint(equalTo: centerXAnchor)
    alignRightConstraint = trailingAnchor.constraint(equalTo: label.trailingAnchor)
    NSLayoutConstraint.activate([bottomConstraint, leadingConstraint, trailingConstraint,
                                 alignCentreConstraint])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Clicks belong to the video underneath — panning must not stop because the
  /// pointer happened to be over a subtitle.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    // Size and margins are all fractions of the height, so a resize restyles.
    render()
  }

  /// Re-read the settings and redraw. Called when the text changes, when the
  /// view resizes, and when a subtitle setting changes.
  func render() {
    guard !text.isEmpty, let style = player?.vr2dSubtitleStyle() else { return }

    // mpv sizes subtitles against a 720-line window and scales by the window
    // height unless told not to. `sub-scale` multiplies on top of both.
    let heightScale = style.scaleByWindow ? max(bounds.height, 1) / 720 : 1
    let pointSize = max(6, CGFloat(style.fontSize) * heightScale
                           * CGFloat(style.scale > 0 ? style.scale : 1))

    var font = NSFont(name: style.fontName, size: pointSize)
      ?? NSFont.systemFont(ofSize: pointSize)
    var traits: NSFontTraitMask = []
    if style.bold { traits.insert(.boldFontMask) }
    if style.italic { traits.insert(.italicFontMask) }
    if !traits.isEmpty { font = NSFontManager.shared.convert(font, toHaveTrait: traits) }

    var attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: style.color ?? .white,
      .paragraphStyle: applyAlignment(style),
    ]

    // `.strokeWidth` is a percentage of the font size, not a width in points,
    // and negative strokes *and* fills, which is how an outline is drawn.
    let borderSize = CGFloat(style.borderSize) * heightScale
    if borderSize > 0 {
      attributes[.strokeColor] = style.borderColor ?? .black
      attributes[.strokeWidth] = -min(12, borderSize / pointSize * 100)
    }
    if style.spacing != 0 { attributes[.kern] = CGFloat(style.spacing) * heightScale }
    if let back = style.backColor, back.alphaComponent > 0 {
      attributes[.backgroundColor] = back
    }

    let shadowOffset = CGFloat(style.shadowOffset) * heightScale
    if shadowOffset > 0, let shadowColor = style.shadowColor, shadowColor.alphaComponent > 0 {
      let shadow = NSShadow()
      shadow.shadowColor = shadowColor
      shadow.shadowOffset = NSSize(width: shadowOffset, height: -shadowOffset)
      shadow.shadowBlurRadius = CGFloat(style.blur) * heightScale
      attributes[.shadow] = shadow
    }

    label.attributedStringValue = NSAttributedString(string: text, attributes: attributes)
    applyPlacement(style, heightScale: heightScale)
  }

  /// Horizontal alignment. Moves the label as well as setting the paragraph
  /// style, because a label that hugs its own text is centred whatever its
  /// paragraph alignment says.
  private func applyAlignment(_ style: VR2DSubtitleStyle) -> NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    alignLeftConstraint.isActive = false
    alignCentreConstraint.isActive = false
    alignRightConstraint.isActive = false

    switch style.alignX {
    case "left":
      paragraph.alignment = .left
      alignLeftConstraint.isActive = true
    case "right":
      paragraph.alignment = .right
      alignRightConstraint.isActive = true
    default:
      paragraph.alignment = .center
      alignCentreConstraint.isActive = true
    }
    return paragraph
  }

  /// Where the text sits. `sub-pos` is a percentage down the frame — 100 is the
  /// bottom, the default — so it becomes an inset from the bottom edge.
  private func applyPlacement(_ style: VR2DSubtitleStyle, heightScale: CGFloat) {
    let marginX = CGFloat(style.marginX) * heightScale
    leadingConstraint.constant = marginX
    trailingConstraint.constant = marginX
    alignLeftConstraint.constant = marginX
    alignRightConstraint.constant = marginX

    let fromBottom = bounds.height * max(0, 100 - CGFloat(style.position)) / 100
    bottomConstraint.constant = -(CGFloat(style.marginY) * heightScale + fromBottom)
  }

}
