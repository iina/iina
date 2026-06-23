//
//  LiveTextSupport.swift
//  iina
//
//  Created by Yuze Jiang on 5/26/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Cocoa
import VisionKit

fileprivate let subsystem = Logger.makeSubsystem("livetext", ["text.viewfinder"])
fileprivate func liveTextLog(_ str: @autoclosure () -> String, level: Logger.Level = .debug) {
  Logger.log(str, level: level, subsystem: subsystem)
}


@preconcurrency
@MainActor
class LiveTextController {
  private weak var mainWindow: MainWindowController!

  var overlayView: NSView?
  var analysisTask: Task<Void, Never>?

  var isSelected: Bool = false
  var isMenuOpen: Bool = false
  var isHighlighted: Bool = false
  var isActive: Bool {
    isSelected || isMenuOpen || isHighlighted
  }

  init(mainWindow: MainWindowController) {
    self.mainWindow = mainWindow
  }

  func updateOverlayInsets() {
    guard #available(macOS 13.0, *) else { return }
    guard let view = overlayView as? ImageAnalysisOverlayView else { return }
    let isBottom = Preference.enum(for: .oscPosition) as Preference.OSCPosition == .bottom
    view.supplementaryInterfaceContentInsets = NSEdgeInsets(top: 8, left: 8, bottom: isBottom ? 48 : 8, right: 8)
  }

  func requestAnalysis() {
    guard #available(macOS 13.0, *), Preference.isLiveTextEnabled else { return }
    requestAnalysisImpl()
  }

  func clearAnalysis() {
    guard #available(macOS 13.0, *), Preference.isLiveTextEnabled else { return }
    clearAnalysisImpl()
  }

  func refreshUI() {
    if isActive {
      mainWindow.hideUI(force: true)
    } else {
      mainWindow.showUI()
    }
  }
}


@available(macOS 13.0, *)
extension LiveTextController: ImageAnalysisOverlayViewDelegate {
  @discardableResult
  func setupLiveTextOverlay() -> ImageAnalysisOverlayView {
    let view = ImageAnalysisOverlayView()
    view.preferredInteractionTypes = .automatic
    view.delegate = self
    view.translatesAutoresizingMaskIntoConstraints = false
    overlayView = view
    updateOverlayInsets()
    return view
  }

  func requestAnalysisImpl() {
    guard mainWindow.player.info.state == .paused, Preference.isLiveTextEnabled else { return }
    liveTextLog("Image analysis requested")
    analysisTask?.cancel()

    let videoView = mainWindow.videoView
    analysisTask = Task { [weak self] in
      guard let self else { return }
      do {
        guard let image = await videoView.videoLayer.captureSnapshot() else {
          liveTextLog("Failed to capture frame for image analysis", level: .warning)
          return
        }
        try Task.checkCancellation()
        let analysis = try await ImageAnalyzer().analyze(image, orientation: .up, configuration: .init([.text]))
        liveTextLog("Image analysis results acquired")
        await MainActor.run {
          let overlay = self.setupLiveTextOverlay()
          overlay.analysis = analysis
          overlay.frame = videoView.bounds
          videoView.addSubview(overlay)
          overlay.padding(.all(0))
          liveTextLog("Image analysis overlay view inserted to video view")
          self.refreshUI()
        }
      } catch is CancellationError {
        liveTextLog("Image analysis cancelled")
      } catch {
        liveTextLog("Image analysis failed: \(error)", level: .warning)
      }
    }
  }

  func clearAnalysisImpl() {
    analysisTask?.cancel()
    analysisTask = nil
    (overlayView as? ImageAnalysisOverlayView)?.analysis = nil
    overlayView?.removeFromSuperview()
    overlayView = nil
    isHighlighted = false
    liveTextLog("Image analysis invalidated and overlay view removed from video view")
    refreshUI()
  }

  func overlayView(_ overlayView: ImageAnalysisOverlayView,
                   shouldBeginAt point: CGPoint,
                   forAnalysisType analysisType: ImageAnalysisOverlayView.InteractionTypes) -> Bool {
    return true
  }

  func overlayView(_ overlayView: ImageAnalysisOverlayView, willOpen menu: NSMenu) {
    isMenuOpen = true
    refreshUI()
  }

  func overlayView(_ overlayView: ImageAnalysisOverlayView, didClose menu: NSMenu) {
    isMenuOpen = false
    refreshUI()
  }

  func textSelectionDidChange(_ overlayView: ImageAnalysisOverlayView) {
    isSelected = overlayView.hasActiveTextSelection
    refreshUI()
  }

  func overlayView(_ overlayView: ImageAnalysisOverlayView, highlightSelectedItemsDidChange highlightSelectedItems: Bool) {
    isHighlighted = highlightSelectedItems
    refreshUI()
  }
}
