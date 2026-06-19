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

@available(macOS 13, *)
extension MainWindowController: ImageAnalysisOverlayViewDelegate {

  @discardableResult
  func setupLiveTextOverlay() -> ImageAnalysisOverlayView {
    let overlayView = ImageAnalysisOverlayView()
    overlayView.preferredInteractionTypes = .automatic
    overlayView.delegate = self
    overlayView.translatesAutoresizingMaskIntoConstraints = false
    liveTextOverlayView = overlayView
    updateLiveTextOverlayInsets()
    return overlayView
  }

  func updateLiveTextOverlayInsets() {
    guard let view = liveTextOverlayView as? ImageAnalysisOverlayView else { return }
    let isBottom = Preference.enum(for: .oscPosition) as Preference.OSCPosition == .bottom
    view.supplementaryInterfaceContentInsets = NSEdgeInsets(top: 8, left: 8, bottom: isBottom ? 48 : 8, right: 8)
  }

  func requestLiveTextAnalysis() {
    guard player.info.state == .paused, Preference.bool(for: .enableLiveText) else { return }
    liveTextLog("Image analysis requested")
    liveTextAnalysisTask?.cancel()
    liveTextAnalysisTask = Task { [weak self] in
      guard let self else { return }
      do {
        guard let image = await self.videoView.videoLayer.captureSnapshot() else {
          liveTextLog("Failed to capture frame for image analysis", level: .warning)
          return
        }
        try Task.checkCancellation()
        let analysis = try await ImageAnalyzer().analyze(image, orientation: .up, configuration: .init([.text]))
        liveTextLog("Image analysis results acquired")
        await MainActor.run {
          let overlay = self.setupLiveTextOverlay()
          overlay.analysis = analysis
          overlay.frame = self.videoView.bounds
          self.videoView.addSubview(overlay)
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

  func clearLiveTextAnalysis() {
    liveTextAnalysisTask?.cancel()
    liveTextAnalysisTask = nil
    (liveTextOverlayView as? ImageAnalysisOverlayView)?.analysis = nil
    liveTextOverlayView?.removeFromSuperview()
    liveTextOverlayView = nil
    isLiveTextHighlighted = false
    liveTextLog("Image analysis invalidated and overlay view removed from video view")
    refreshUI()
  }

  func overlayView(_ overlayView: ImageAnalysisOverlayView,
                   shouldBeginAt point: CGPoint,
                   forAnalysisType analysisType: ImageAnalysisOverlayView.InteractionTypes) -> Bool {
    return true
  }

  func overlayView(_ overlayView: ImageAnalysisOverlayView, willOpen menu: NSMenu) {
    isLiveTextMenuOpen = true
    refreshUI()
  }

  func overlayView(_ overlayView: ImageAnalysisOverlayView, didClose menu: NSMenu) {
    isLiveTextMenuOpen = false
    refreshUI()
  }

  func textSelectionDidChange(_ overlayView: ImageAnalysisOverlayView) {
    isLiveTextSelected = overlayView.hasActiveTextSelection
    refreshUI()
  }

  func overlayView(_ overlayView: ImageAnalysisOverlayView, highlightSelectedItemsDidChange highlightSelectedItems: Bool) {
    isLiveTextHighlighted = highlightSelectedItems
    refreshUI()
  }

  func refreshUI() {
    if isLiveTextUserInteractionActive {
      hideUI(force: true)
    } else {
      showUI()
    }
  }
}
