//
//  LiveTextSupport.swift
//  iina
//
//  Created by Yuze Jiang on 5/26/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Cocoa
import VisionKit

@available(macOS 13, *)
extension MainWindowController: ImageAnalysisOverlayViewDelegate {

  func setupLiveTextOverlay() {
    let overlayView = ImageAnalysisOverlayView()
    overlayView.preferredInteractionTypes = .automatic
    overlayView.autoresizingMask = [.width, .height]
    overlayView.delegate = self
    overlayView.frame = videoView.bounds
    liveTextOverlayView = overlayView
    updateLiveTextOverlayInsets()
    if Preference.bool(for: .enableLiveText) && Preference.bool(for: .liveTextOverlay) {
      videoView.addSubview(overlayView)
    }
  }

  func clearAnalysis() {
    (liveTextOverlayView as? ImageAnalysisOverlayView)?.analysis = nil
  }

  func requestLiveTextAnalysis() {
    guard player.info.state == .paused, Preference.bool(for: .enableLiveText) else { return }
    player.mpv.asyncCommand(.screenshotRaw, replyUserdata: MPVController.UserData.screenshot_raw)
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
    } else if !shouldShow {
      overlayView.removeFromSuperview()
    }
  }

  func showAnalysis(with image: NSImage) {
    guard let overlayView = liveTextOverlayView as? ImageAnalysisOverlayView else { return }
    let analyzer = ImageAnalyzer()
    Task { [weak self, overlayView] in
      do {
        let analysis = try await analyzer.analyze(image, orientation: .up, configuration: .init([.text]))
        await MainActor.run {
          guard self != nil else { return }
          overlayView.analysis = analysis
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
    isLiveTextUserInteractionActive = true
    hideUI(force: true)
  }

  func overlayView(_ overlayView: ImageAnalysisOverlayView, didClose menu: NSMenu) {
    isLiveTextUserInteractionActive = false
    showUI()
  }

  func textSelectionDidChange(_ overlayView: ImageAnalysisOverlayView) {
    if overlayView.hasActiveTextSelection {
      isLiveTextUserInteractionActive = true
      hideUI(force: true)
    } else {
      isLiveTextUserInteractionActive = false
    }
  }

  func overlayView(_ overlayView: ImageAnalysisOverlayView, highlightSelectedItemsDidChange highlightSelectedItems: Bool) {
    isLiveTextUserInteractionActive = highlightSelectedItems
    if highlightSelectedItems {
      hideUI(force: true)
    } else {
      showUI()
    }
  }
}
