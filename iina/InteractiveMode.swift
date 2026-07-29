//
//  InteractiveMode.swift
//  iina
//
//  Created by Hechen Li on 2026-06-22.
//  Copyright © 2026 lhc. All rights reserved.
//

fileprivate let ui = UIHelper.shared


class InteractiveModeController: NSObject {
  enum Mode {
    case crop, delogo
  }

  weak var mainWindow: MainWindowController!

  private var cropx: Int = 0
  private var cropy: Int = 0  // in flipped coord
  private var cropw: Int = 0
  private var croph: Int = 0

  private var readableCropString: String {
    return "(\(cropx), \(cropy)) (\(cropw)\u{d7}\(croph))"
  }

  var isActive: Bool = false
  var currentMode: Mode?
  private var isPausedPriorToInteractiveMode = false

  private lazy var cropRectLabel: NSTextField = {
    let label = NSTextField(labelWithString: "")
    label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    label.textColor = .secondaryLabelColor
    return label
  }()

  private lazy var predefinedAspectSegment: NSSegmentedControl = {
    let seg = NSSegmentedControl(
      labels: ["4:3", "16:9", "16:10", "21:9", "3:2", "5:4"],
      trackingMode: .selectOne,
      target: self,
      action: #selector(predefinedAspectValueAction)
    )
    seg.translatesAutoresizingMaskIntoConstraints = false
    return seg
  }()

  private lazy var controlBar: NSView = {
    let doneButton = ui.button("general.done", target: self, action: #selector(doneAction))
    let cancelButton = ui.button("general.cancel", target: self, action: #selector(cancelAction))
    return ui.vStack(
      spacing: 8,
      cropRectLabel,
      ui.hStack(predefinedAspectSegment, ui.space(width: 8), cancelButton, doneButton)
    )
  }()

  private lazy var cropBoxView: CropBoxView = CropBoxView(callback: {
    [unowned self] in selectedRectUpdated()
  })

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow
    super.init()
  }

  func enter(mode: Mode, selectWholeVideoByDefault: Bool = false) {
    guard let window = mainWindow.window else { return }
    let player = mainWindow.player

    let (ow, oh) = player.originalVideoSize
    guard ow != 0 && oh != 0 else {
      Utility.showAlert("no_video_track")
      return
    }

    window.backgroundColor = .windowBackgroundColor
    mainWindow.standardWindowButtons.forEach { $0.isEnabled = false }

    isPausedPriorToInteractiveMode = player.info.state == .paused
    player.pause()
    isActive = true
    currentMode = mode

    mainWindow.hideUI(force: true)
    mainWindow.liveText.clearAnalysis()

    // horizontal padding 20, top padding 20
    let aspect = NSSize(width: player.videoSizeForDisplay.0, height: player.videoSizeForDisplay.1)
    let containerSize = mainWindow.videoViewContainer.frame.size
    let maxSize = NSSize(width: containerSize.width - 40, height: containerSize.height - 108)
    let newSize = aspect.shrink(toSize: maxSize)
    let horizontalPadding = (containerSize.width - newSize.width) / 2
    let topPadding = CGFloat(20)
    let bottomPadding = containerSize.height - topPadding - newSize.height

    mainWindow.updateVideoViewConstraints([
      .top: topPadding, .bottom: bottomPadding,
      .leading: horizontalPadding, .trailing: horizontalPadding
    ])

    let shadow = NSShadow()
    shadow.shadowBlurRadius = 10
    shadow.shadowColor = .black.withAlphaComponent(0.5)
    mainWindow.videoView.shadow = shadow
    mainWindow.videoView.needsLayout = true
    mainWindow.videoView.layoutSubtreeIfNeeded()
    mainWindow.forceDraw("interactive cropping")

    mainWindow.videoViewContainer.addSubview(controlBar)
    controlBar.padding(.bottom(20)).center(.x)

    let origVideoSize = NSSize(width: ow, height: oh)
    let selectedRect: NSRect = selectWholeVideoByDefault ? NSRect(origin: .zero, size: origVideoSize) : .zero

    mainWindow.videoView.addSubview(cropBoxView)
    cropBoxView.padding(.all)
    cropBoxView.videoSize = origVideoSize
    cropBoxView.selectedRect = selectedRect
  }

  func exit(then: @escaping () -> Void = {}) {
    guard isActive, let window = mainWindow.window else { return }
    let player = mainWindow.player
    isActive = false
    currentMode = nil

    cropBoxView.removeFromSuperview()
    controlBar.removeFromSuperview()

    window.backgroundColor = .black
    mainWindow.standardWindowButtons.forEach { $0.isEnabled = true }

    mainWindow.videoView.shadow = nil
    mainWindow.updateVideoViewConstraints([
      .top: 0, .bottom: 0, .leading: 0, .trailing: 0
    ])

    then()
    if !isPausedPriorToInteractiveMode {
      player.resume()
    }
  }

  func selectedRectUpdated() {
    guard mainWindow.interactiveMode.isActive else { return }
    let rect = cropBoxView.selectedRect
    cropx = Int(rect.minX)
    cropy = Int(CGFloat(mainWindow.player.info.videoHeight!) - rect.height - rect.minY)
    cropw = Int(rect.width)
    croph = Int(rect.height)
    cropRectLabel.stringValue = readableCropString
  }

  @objc private func predefinedAspectValueAction(_ sender: NSSegmentedControl) {
    guard let str = sender.label(forSegment: sender.selectedSegment) else { return }
    guard let aspect = Aspect(string: str) else { return }

    let videoSize = cropBoxView.videoSize
    let croppedSize = videoSize.crop(withAspect: aspect)
    let cropped = NSMakeRect((videoSize.width - croppedSize.width) / 2,
                             (videoSize.height - croppedSize.height) / 2,
                             croppedSize.width,
                             croppedSize.height)

    cropBoxView.setSelectedRect(to: cropped)
  }

  @objc private func doneAction(_ sender: AnyObject) {
    switch currentMode {
    case .crop:
      cropAction()
    case .delogo:
      delogoAction()
    case nil:
      break
    }
  }

  private func cropAction() {
    let player = mainWindow.player
    exit {
      if self.cropx == 0 && self.cropy == 0 &&
        self.cropw == player.info.videoWidth &&
        self.croph == player.info.videoHeight {
        // if no crop, remove the crop filter
        player.removeCropFilter()
        return
      }
      // else, set the filter
      let filter = MPVFilter.crop(w: self.cropw, h: self.croph, x: self.cropx, y: self.cropy)
      player.setCrop(fromFilter: filter)
      // custom crop has no corresponding menu entry
      player.info.unsureCrop = ""
      player.sendOSD(.crop(self.readableCropString))
    }
  }

  private func delogoAction() {
    let player = mainWindow.player
    exit {
      let filter = MPVFilter.init(lavfiName: "delogo", label: Constants.FilterName.delogo, paramDict: [
        "x": String(self.cropx),
        "y": String(self.cropy),
        "w": String(self.cropw),
        "h": String(self.croph)
      ])
      if let existingFilter = player.info.delogoFilter {
        let _ = player.removeVideoFilter(existingFilter)
      }
      if !player.addVideoFilter(filter) {
        Utility.showAlert("filter.incorrect")
        return
      }
      player.info.delogoFilter = filter
    }
  }

  @objc private func cancelAction(_ sender: AnyObject) {
    exit()
  }
}


class CropBoxView: NSView {
  private let boxStrokeColor = NSColor.controlAccentColor
  private let boxFillColor = NSColor.cropBoxFill

  var rectUpdatedCallback: (() -> Void)?

  /** Original video size. */
  var videoSize: NSSize = NSSize()
  /** Crop box's frame. */
  var boxRect: NSRect = NSRect()

  var selectedRect: NSRect = NSRect() {
    didSet {
      updateBoxRect()
      updateCursorRects()
      rectUpdatedCallback?()
    }
  }

  private var firstDraw = true
  private var isDragging = false
  private var dragSide: DragSide = .top
  private var isFreeSelecting = false
  private var lastMousePos: NSPoint?

  private enum DragSide {
    case top, bottom, left, right
  }

  // top and bottom are related to view's coordinate
  private var rectTop: NSRect!
  private var rectBottom: NSRect!
  private var rectLeft: NSRect!
  private var rectRight: NSRect!

  init(callback: (() -> Void)?) {
    self.rectUpdatedCallback = callback
    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Rect size settings

  func resized() {
    updateBoxRect()
    updateCursorRects()
    needsDisplay = true
  }

  // set boxRect, and update selectedRect
  func boxRectChanged(to rect: NSRect) {
    boxRect = rect
    updateSelectedRect()
  }

  // set selectedRect, and update boxRect
  func setSelectedRect(to rect: NSRect) {
    selectedRect = rect
    updateBoxRect()
    updateCursorRects()
    needsDisplay = true
  }

  // update selectedRect from boxRect
  private func updateSelectedRect() {
    let xScale = videoSize.width / frame.width
    let yScale = videoSize.height / frame.height

    var ix = (boxRect.origin.x - frame.origin.x) * xScale
    var iy = (boxRect.origin.y - frame.origin.y) * xScale
    var iw = boxRect.width * xScale
    var ih = boxRect.height * yScale

    if abs(ix) <= 4 { ix = 0 }
    if abs(iy) <= 4 { iy = 0 }
    if abs(iw + ix - videoSize.width) <= 4 { iw = videoSize.width - ix }
    if abs(ih + iy - videoSize.height) <= 4 { ih = videoSize.height - iy }

    selectedRect = NSMakeRect(ix, iy, iw, ih)
  }

  // update boxRect from (videoRect * selectedRect)
  private func updateBoxRect() {
    let xScale =  frame.width / videoSize.width
    let yScale =  frame.height / videoSize.height

    let ix = selectedRect.minX * xScale + frame.minX
    let iy = selectedRect.minY * xScale + frame.minY
    let iw = selectedRect.width * xScale
    let ih = selectedRect.height * yScale

    boxRect = NSMakeRect(ix, iy, iw, ih)
  }

  // MARK: - Mouse event to change boxRect

  override func mouseDown(with event: NSEvent) {
    let mousePos = convert(event.locationInWindow, from: nil)
    lastMousePos = mousePos

    if rectTop.contains(mousePos) {
      isDragging = true
      dragSide = .top
    } else if rectBottom.contains(mousePos) {
      isDragging = true
      dragSide = .bottom
    } else if rectLeft.contains(mousePos) {
      isDragging = true
      dragSide = .left
    } else if rectRight.contains(mousePos) {
      isDragging = true
      dragSide = .right
    } else if frame.contains(mousePos) {
      // free select
      isFreeSelecting = true
      window?.invalidateCursorRects(for: self)
    } else {
      super.mouseDown(with: event)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    let mousePos = convert(event.locationInWindow, from: nil).constrained(to: frame)

    if isDragging {
      // resizing selected box
      var newBoxRect = boxRect
      switch dragSide {
      case .top:
        let diff = mousePos.y - lastMousePos!.y
        newBoxRect.origin.y += diff
        newBoxRect.size.height -= diff

      case .bottom:
        let diff = mousePos.y - lastMousePos!.y
        newBoxRect.size.height += diff

      case .right:
        let diff = mousePos.x - lastMousePos!.x
        newBoxRect.size.width += diff

      case .left:
        let diff = mousePos.x - lastMousePos!.x
        newBoxRect.origin.x += diff
        newBoxRect.size.width -= diff
      }

      boxRectChanged(to: newBoxRect)
      needsDisplay = true
      updateCursorRects()
      lastMousePos = mousePos
    } else if isFreeSelecting {
      // free selecting
      let newBoxRect = NSRect(vertexPoint: lastMousePos!, and: mousePos)
      boxRectChanged(to: newBoxRect)
      needsDisplay = true
    } else {
      super.mouseDragged(with: event)
    }
  }

  override func mouseUp(with event: NSEvent) {
    if isDragging {
      isDragging = false
    } else if isFreeSelecting {
      isFreeSelecting = false
      updateCursorRects()
    } else {
      super.mouseUp(with: event)
    }
  }

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    if firstDraw {
      updateBoxRect()
      updateCursorRects()
    }

    boxStrokeColor.setStroke()
    boxFillColor.setFill()

    let path = NSBezierPath(rect: boxRect)
    path.lineWidth = 2
    path.fill()
    path.stroke()
  }

  // MARK: - Cursor rects

  override func resetCursorRects() {
    addCursorRect(rectTop, cursor: .resizeUpDown)
    addCursorRect(rectBottom, cursor: .resizeUpDown)
    addCursorRect(rectLeft, cursor: .resizeLeftRight)
    addCursorRect(rectRight, cursor: .resizeLeftRight)
  }

  private func updateCursorRects() {
    let x = boxRect.origin.x
    let y = boxRect.origin.y
    let w = boxRect.size.width
    let h = boxRect.size.height
    rectTop = NSMakeRect(x, y-2, w, 4).standardized
    rectBottom = NSMakeRect(x, y+h-2, w, 4).standardized
    rectLeft = NSMakeRect(x-2, y+2, 4, h-4).standardized
    rectRight = NSMakeRect(x+w-2, y+2, 4, h-4).standardized

    window?.invalidateCursorRects(for: self)
  }
}
