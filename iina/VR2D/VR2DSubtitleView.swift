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
//  The styling is read back out of mpv rather than out of IINA's preferences.
//  mpv holds the effective values: IINA has already pushed twenty-odd settings
//  into it, and anything from `mpv.conf`, a user script or a runtime change is
//  in there too. Reading the preferences instead would mean maintaining a
//  second copy of that mapping, and it would silently miss everything set by
//  any other route.
//
//  This only works for subtitles that have text. Picture-based ones (PGS,
//  VobSub) have none to read, and are left to mpv.
//

import Cocoa

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
    guard !text.isEmpty, let mpv = player?.mpv else { return }

    // mpv sizes subtitles against a 720-line window and then scales by the
    // window height unless told not to, which is what `sub-scale-by-window`
    // controls. `sub-scale` multiplies on top of both.
    let scaleByWindow = mpv.getFlag(MPVOption.Subtitles.subScaleByWindow)
    let heightScale = scaleByWindow ? max(bounds.height, 1) / 720 : 1
    let scale = CGFloat(mpv.getDouble(MPVOption.Subtitles.subScale))
    let pointSize = max(6, CGFloat(mpv.getDouble(MPVOption.Subtitles.subFontSize))
                           * heightScale * (scale > 0 ? scale : 1))

    var font = NSFont(name: mpv.getString(MPVOption.Subtitles.subFont) ?? "sans-serif",
                      size: pointSize) ?? NSFont.systemFont(ofSize: pointSize)
    var traits: NSFontTraitMask = []
    if mpv.getFlag(MPVOption.Subtitles.subBold) { traits.insert(.boldFontMask) }
    if mpv.getFlag(MPVOption.Subtitles.subItalic) { traits.insert(.italicFontMask) }
    if !traits.isEmpty {
      font = NSFontManager.shared.convert(font, toHaveTrait: traits)
    }

    let colour = color(mpv, MPVOption.Subtitles.subColor) ?? .white
    let borderColour = color(mpv, MPVOption.Subtitles.subBorderColor) ?? .black
    let backColour = color(mpv, MPVOption.Subtitles.subBackColor)
    let shadowColour = color(mpv, MPVOption.Subtitles.subShadowColor)

    var attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: colour,
      .paragraphStyle: applyAlignment(mpv),
    ]

    // `.strokeWidth` is a percentage of the font size, not a width in points,
    // and negative strokes *and* fills, which is how an outline is drawn.
    let borderSize = CGFloat(mpv.getDouble(MPVOption.Subtitles.subBorderSize)) * heightScale
    if borderSize > 0 {
      attributes[.strokeColor] = borderColour
      attributes[.strokeWidth] = -min(12, borderSize / pointSize * 100)
    }

    let spacing = CGFloat(mpv.getDouble(MPVOption.Subtitles.subSpacing))
    if spacing != 0 { attributes[.kern] = spacing * heightScale }

    if let backColour, backColour.alphaComponent > 0 {
      attributes[.backgroundColor] = backColour
    }

    let shadowOffset = CGFloat(mpv.getDouble(MPVOption.Subtitles.subShadowOffset)) * heightScale
    if shadowOffset > 0, let shadowColour, shadowColour.alphaComponent > 0 {
      let shadow = NSShadow()
      shadow.shadowColor = shadowColour
      shadow.shadowOffset = NSSize(width: shadowOffset, height: -shadowOffset)
      // mpv blurs the whole glyph rather than only the shadow, but this is the
      // closest AppKit gets without drawing the text twice.
      shadow.shadowBlurRadius = CGFloat(mpv.getDouble(MPVOption.Subtitles.subBlur)) * heightScale
      attributes[.shadow] = shadow
    }

    label.attributedStringValue = NSAttributedString(string: text, attributes: attributes)
    applyPlacement(mpv, heightScale: heightScale)
  }

  /// Horizontal alignment, from `sub-align-x`. Moves the label as well as
  /// setting the paragraph style, because a label that hugs its own text is
  /// centred whatever its paragraph alignment says.
  private func applyAlignment(_ mpv: MPVController) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    alignLeftConstraint.isActive = false
    alignCentreConstraint.isActive = false
    alignRightConstraint.isActive = false

    switch mpv.getString(MPVOption.Subtitles.subAlignX) {
    case "left":
      style.alignment = .left
      alignLeftConstraint.isActive = true
    case "right":
      style.alignment = .right
      alignRightConstraint.isActive = true
    default:
      style.alignment = .center
      alignCentreConstraint.isActive = true
    }
    return style
  }

  /// Where the text sits, from `sub-pos`, `sub-align-y` and the margins.
  ///
  /// `sub-pos` is a percentage down the frame — 100 is the bottom, which is the
  /// default — so it is turned into an inset from whichever edge the text is
  /// anchored to.
  private func applyPlacement(_ mpv: MPVController, heightScale: CGFloat) {
    let marginX = CGFloat(mpv.getDouble(MPVOption.Subtitles.subMarginX)) * heightScale
    let marginY = CGFloat(mpv.getDouble(MPVOption.Subtitles.subMarginY)) * heightScale
    leadingConstraint.constant = marginX
    trailingConstraint.constant = marginX
    alignLeftConstraint.constant = marginX
    alignRightConstraint.constant = marginX

    let position = CGFloat(mpv.getDouble(MPVOption.Subtitles.subPos))
    // Below 100 the text moves up the frame by that percentage of the height.
    let fromBottom = bounds.height * max(0, 100 - position) / 100
    bottomConstraint.constant = -(marginY + fromBottom)
  }

  private func color(_ mpv: MPVController, _ name: String) -> NSColor? {
    guard let string = mpv.getString(name) else { return nil }
    return NSColor(mpvColorString: string)
  }
}
