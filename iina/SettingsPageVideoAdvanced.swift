//
//  SettingsPageVideoAdvanced.swift
//  iina
//
//  SPEC mpv-config-driven-refactor Phase 7: GPU / scale / colour / HDR options.
//

import Foundation

class SettingsPageVideoAdvanced: SettingsPage {
  override var identifier: String {
    "video_advanced"
  }

  override var title: String {
    return NSLocalizedString("preference.video_advanced", comment: "Video (Advanced)")
  }

  override var image: NSImage {
    return .sf("wand.and.rays", withConfiguration: symbolConfiguration)!
  }

  override var localizationTable: String {
    "SettingsVideoAdvancedLocalizable"
  }

  override func content() -> [SettingsSection] {
    return sections {
      sectionScaling()
      sectionColorHDR()
      sectionDecoder()
    }
  }

  private func sectionScaling() -> SettingsSection {
    return section {
      SettingsList(title: .text_Scaling) {
        SettingsItem.PopupButton()
          .bindTo(.scale, ofType: Preference.ScaleOption.self)
          .mpvName("scale")
          .hasDescription()
        SettingsItem.PopupButton()
          .bindTo(.cscale, ofType: Preference.ScaleOption.self)
          .mpvName("cscale")
        SettingsItem.PopupButton()
          .bindTo(.dscale, ofType: Preference.ScaleOption.self)
          .mpvName("dscale")
        SettingsItem.Input(title: .scaleAntiringLabel, step: 0.05)
          .bindTo(.scaleAntiring)
          .mpvName("scale-antiring")
          .hasDescription()
        SettingsItem.Switch(title: .correctDownscalingLabel)
          .bindTo(.correctDownscaling)
          .mpvName("correct-downscaling")
        SettingsItem.Switch(title: .linearDownscalingLabel)
          .bindTo(.linearDownscaling)
          .mpvName("linear-downscaling")
        SettingsItem.Switch(title: .sigmoidUpscalingLabel)
          .bindTo(.sigmoidUpscaling)
          .mpvName("sigmoid-upscaling")
        SettingsItem.PopupButton()
          .bindTo(.dither, ofType: Preference.DitherOption.self)
          .mpvName("dither")
          .hasDescription()
        SettingsItem.Switch(title: .blendSubtitlesLabel)
          .bindTo(.blendSubtitles)
          .mpvName("blend-subtitles")
      }
    }
  }

  private func sectionColorHDR() -> SettingsSection {
    return section {
      SettingsList(title: .text_ColorHDR) {
        SettingsItem.Switch(title: .hdrComputePeakLabel)
          .bindTo(.hdrComputePeak)
          .mpvName("hdr-compute-peak")
        SettingsItem.Input(title: .hdrPeakPercentileLabel)
          .bindTo(.hdrPeakPercentile)
          .mpvName("hdr-peak-percentile")
          .hasDescription()
        SettingsItem.Input(title: .hdrContrastRecoveryLabel)
          .bindTo(.hdrContrastRecovery)
          .mpvName("hdr-contrast-recovery")
          .hasDescription()
        SettingsItem.Input(title: .iccForceContrastLabel)
          .bindTo(.iccForceContrast)
          .mpvName("icc-force-contrast")
          .hasDescription()
        SettingsItem.Switch(title: .targetColorspaceHintLabel)
          .bindTo(.targetColorspaceHint)
          .mpvName("target-colorspace-hint")
        SettingsItem.PopupButton()
          .bindTo(.targetTrc, ofType: Preference.TargetTrcOption.self)
          .mpvName("target-trc")
          .hasDescription()
        SettingsItem.Input(title: .targetPeakLabel)
          .bindTo(.targetPeak)
          .mpvName("target-peak")
          .hasDescription()
        SettingsItem.LongInput()
          .bindTo(.gpuContext)
          .mpvName("gpu-context")
          .hasDescription()
        SettingsItem.LongInput()
          .bindTo(.libplaceboOpts)
          .mpvName("libplacebo-opts")
          .hasDescription()
      }
    }
  }

  private func sectionDecoder() -> SettingsSection {
    return section {
      SettingsList(title: .text_VADecoding) {
        SettingsItem.Switch(title: .vdLavcDrLabel)
          .bindTo(.vdLavcDr)
          .mpvName("vd-lavc-dr")
        SettingsItem.Input()
          .bindTo(.vdLavcSoftwareFallback)
          .mpvName("vd-lavc-software-fallback")
          .hasDescription()
        SettingsItem.Input()
          .bindTo(.forceWindow)
          .mpvName("force-window")
          .hasDescription()
        SettingsItem.LongInput()
          .bindTo(.demuxerLavfFormat)
          .mpvName("demuxer-lavf-format")
          .hasDescription()
        SettingsItem.Switch(title: .forceSeekableLabel)
          .bindTo(.forceSeekable)
          .mpvName("force-seekable")
      }
    }
  }
}
