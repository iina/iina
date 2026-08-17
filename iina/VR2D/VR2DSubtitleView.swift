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
//  legible, and land where subtitles are supposed to land. The text comes from
//  mpv's `sub-text` property, and the styling from the same preferences mpv
//  would have used, so it looks like it always did.
//
//  This only works for subtitles that have text. Picture-based ones (PGS,
//  VobSub) have none to read, and are left to mpv.
//

import Cocoa

class VR2DSubtitleView: NSView {

  private let label = NSTextField(labelWithString: "")

  /// Fraction of the height kept clear below the text, so it does not sit on
  /// the edge of the picture. mpv's own `sub-margin-y` works out at about this.
  private static let bottomMarginFraction: CGFloat = 0.045

  private var bottomConstraint: NSLayoutConstraint!

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
    label.alignment = .center
    label.maximumNumberOfLines = 0
    label.lineBreakMode = .byWordWrapping
    label.isSelectable = false
    label.cell?.wraps = true
    addSubview(label)

    bottomConstraint = label.bottomAnchor.constraint(equalTo: bottomAnchor)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: centerXAnchor),
      bottomConstraint,
      label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
      label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Clicks belong to the video underneath — panning must not stop because the
  /// pointer happened to be over a subtitle.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  /// Draw what mpv would have drawn, from the same preferences.
  ///
  /// mpv sizes subtitles against a 720-line window, so the same scaling is
  /// applied here; otherwise the text comes out the wrong size on anything but
  /// a 720p window.
  private func render() {
    guard !text.isEmpty else { return }

    let scale = max(bounds.height, 1) / 720
    let size = max(8, CGFloat(Preference.float(for: .subTextSize)) * scale)
    let fontName = Preference.string(for: .subTextFont) ?? "sans-serif"
    let font = NSFont(name: fontName, size: size) ?? NSFont.systemFont(ofSize: size)

    let textColor = Preference.string(for: .subTextColorString)
      .flatMap(NSColor.init(mpvColorString:)) ?? .white
    let borderColor = Preference.string(for: .subBorderColorString)
      .flatMap(NSColor.init(mpvColorString:)) ?? .black
    // `.strokeWidth` is a percentage of the font size, not a width in points,
    // so mpv's border size has to be converted rather than passed through.
    let borderPoints = CGFloat(Preference.float(for: .subBorderSize)) * scale
    let strokePercent = min(12, borderPoints / size * 100)

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    label.attributedStringValue = NSAttributedString(string: text, attributes: [
      .font: font,
      .foregroundColor: textColor,
      .strokeColor: borderColor,
      // Negative strokes *and* fills, which is how an outline is drawn.
      .strokeWidth: -strokePercent,
      .paragraphStyle: paragraph,
    ])
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    // Both the font size and the margin are fractions of the height.
    bottomConstraint?.constant = -newSize.height * VR2DSubtitleView.bottomMarginFraction
    render()
  }
}
