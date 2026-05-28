//
//  LiveTextSupport.swift
//  iina
//
//  Created by Yuze Jiang on 5/26/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Cocoa
import VisionKit

fileprivate let subsystem = Logger.makeSubsystem("Live Text", ["viewfinder.text"])
fileprivate func liveTextLog(_ str: String, level: Logger.Level = .debug) {
  Logger.log(str, level: level, subsystem: subsystem)
}

@available(macOS 13, *)
extension MainWindowController: ImageAnalysisOverlayViewDelegate {

  func setupLiveTextOverlay() {
    let overlayView = ImageAnalysisOverlayView()
    overlayView.preferredInteractionTypes = .automatic
    overlayView.delegate = self
    overlayView.translatesAutoresizingMaskIntoConstraints = false
    liveTextOverlayView = overlayView
    updateLiveTextOverlayInsets()
    if Preference.bool(for: .enableLiveText) && Preference.bool(for: .liveTextOverlay) {
      videoView.addSubview(overlayView)
    }
  }

  @MainActor func contentView(for overlayView: ImageAnalysisOverlayView) -> NSView? {
    return videoView
  }

  @MainActor func contentsRect(for overlayView: ImageAnalysisOverlayView) -> CGRect {
    return videoView.videoLayer.contentsRect
  }

  func clearAnalysis() {
    guard let overlay = liveTextOverlayView as? ImageAnalysisOverlayView else { return }
    overlay.analysis = nil
    updateLiveTextOverlay()
    liveTextLog("Image analysis invalidated")
  }

  func requestLiveTextAnalysis() {
    guard player.info.state == .paused, Preference.bool(for: .enableLiveText) else { return }
    player.mpv.asyncCommand(.screenshotRaw, replyUserdata: MPVController.UserData.screenshot_raw)
    // showAnalysis(with: image)
    liveTextLog("Image analysis requested")
  }

  func updateLiveTextOverlayInsets() {
    guard let view = liveTextOverlayView as? ImageAnalysisOverlayView else { return }
    let isBottom = Preference.enum(for: .oscPosition) as Preference.OSCPosition == .bottom
    view.supplementaryInterfaceContentInsets = NSEdgeInsets(top: 8, left: 8, bottom: isBottom ? 48 : 8, right: 8)
  }

  func updateLiveTextOverlay() {
    guard let overlayView = liveTextOverlayView else { return }
    let shouldShow = Preference.bool(for: .enableLiveText) && Preference.bool(for: .liveTextOverlay) && player.info.state == .paused
    if shouldShow && overlayView.superview == nil {
      overlayView.frame = videoView.bounds
      videoView.addSubview(overlayView)
      overlayView.padding(.all(0))
      liveTextLog("Image analysis overlay view inserted to video view")
    } else if !shouldShow {
      overlayView.removeFromSuperview()
      liveTextLog("Image analysis overlay view removed from video view")
    }
  }

  func showAnalysis(with image: NSImage) {
    guard let overlayView = liveTextOverlayView as? ImageAnalysisOverlayView else { return }
    let analyzer = ImageAnalyzer()
    Task { [weak self, overlayView] in
      do {
        let analysis = try await analyzer.analyze(image, orientation: .up, configuration: .init([.text]))
        liveTextLog("Image analysis results acquired")
        await MainActor.run {
          guard let self else { return }
          overlayView.analysis = analysis
          self.updateLiveTextOverlay()
        }
      } catch {
        fatalError("Error")
      }
    }
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
