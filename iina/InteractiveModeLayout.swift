import Foundation

enum InteractiveModeLayout {
  static let defaultTopPadding: CGFloat = 20
  static let defaultSidePadding: CGFloat = 20
  static let defaultBottomMargin: CGFloat = 20

  static func reservedBottomHeight(controlBarHeight: CGFloat, bottomMargin: CGFloat = defaultBottomMargin) -> CGFloat {
    controlBarHeight + bottomMargin * 2
  }

  static func maxVideoSize(container: CGSize,
                           topPadding: CGFloat = defaultTopPadding,
                           reservedBottom: CGFloat,
                           sidePadding: CGFloat = defaultSidePadding) -> CGSize {
    CGSize(
      width: max(1, container.width - sidePadding * 2),
      height: max(1, container.height - topPadding - reservedBottom)
    )
  }
}
