//
//  SettingsLocalization.swift
//  iina
//
//  Created by Hechen Li on 6/22/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

struct SettingsLocalization {
  struct Key {
    let rawValue: String
    let isGeneral: Bool

    init(_ rawValue: String, isGeneral: Bool = false) {
      self.rawValue = rawValue
      self.isGeneral = isGeneral
    }

    static func general(_ rawValue: String) -> Key {
      Key(rawValue, isGeneral: true)
    }
  }
}


extension SettingsLocalization.Key {
  // VR video
  static let text_VRVideo = SettingsLocalization.Key("$VRVideo")
  static let text_LookingAround = SettingsLocalization.Key("$LookingAround")
  static let text_degrees = SettingsLocalization.Key("$degrees")
  static let vr2dEyeLabel = SettingsLocalization.Key("vr2dEye.label")

  // General
  static let text_Playlist = SettingsLocalization.Key("$Playlist")
  static let text_WhenMediaIsOpened = SettingsLocalization.Key("$WhenMediaIsOpened")
  static let text_CheckForUpdates = SettingsLocalization.Key("$CheckForUpdates")
  static let text_History = SettingsLocalization.Key("$History")
  static let text_Screenshots = SettingsLocalization.Key("$Screenshots")
  static let text_Behavior = SettingsLocalization.Key("$Behavior")
  static let pauseresumeWhen = SettingsLocalization.Key("pauseresumeWhen")

  // UI
  static let oscPositionItem0 = SettingsLocalization.Key("oscPosition.items.0")
  static let oscPositionItem1 = SettingsLocalization.Key("oscPosition.items.1")
  static let oscPositionItem2 = SettingsLocalization.Key("oscPosition.items.2")
  static let text_WhenEnteringPIP = SettingsLocalization.Key("$WhenEnteringPIP")
  static let text_Customize = SettingsLocalization.Key("$Customize")
  static let text_ofScreen = SettingsLocalization.Key("$ofScreen")
  static let text_MB = SettingsLocalization.Key("$MB")
  static let controlBarAutoHideTimeoutLabel = SettingsLocalization.Key("controlBarAutoHideTimeout.label")
  static let text_bottom = SettingsLocalization.Key("$bottom")
  static let text_Accessibility = SettingsLocalization.Key("$Accessibility")
  static let text_Window = SettingsLocalization.Key("$Window")
  static let text_Width = SettingsLocalization.Key("$Width")
  static let text_WhenMediaIsOpenedManually = SettingsLocalization.Key("$WhenMediaIsOpenedManually")
  static let text_OnScreenDisplay = SettingsLocalization.Key("$OnScreenDisplay")
  static let text_PictureinnPicture = SettingsLocalization.Key("$PictureinnPicture")
  static let text_sideOfTheScreen = SettingsLocalization.Key("$sideOfTheScreen")
  static let text_pt = SettingsLocalization.Key("$pt")
  static let text_YOffset = SettingsLocalization.Key("$YOffset")
  static let text_right = SettingsLocalization.Key("$right")
  static let text_s = SettingsLocalization.Key("$s")
  static let text_InitialWindowPosition = SettingsLocalization.Key("$InitialWindowPosition")
  static let text_SuppressMessagesFor = SettingsLocalization.Key("$SuppressMessagesFor")
  static let text_Height = SettingsLocalization.Key("$Height")
  static let text_point = SettingsLocalization.Key("$point")
  static let text_toThe = SettingsLocalization.Key("$toThe")
  static let text_XOffset = SettingsLocalization.Key("$XOffset")
  static let text_DoNotResize = SettingsLocalization.Key("$DoNotResize")
  static let text_OnScreenController = SettingsLocalization.Key("$OnScreenController")
  static let text_ThumbnailPreview = SettingsLocalization.Key("$ThumbnailPreview")
  static let text_Appearance = SettingsLocalization.Key("$Appearance")
  static let text_top = SettingsLocalization.Key("$top")
  static let text_left = SettingsLocalization.Key("$left")
  static let text_AlwaysWhenPlaying = SettingsLocalization.Key("$AlwaysWhenPlaying")
  static let text_InitialWindowSize = SettingsLocalization.Key("$InitialWindowSize")
  static let text_Layout = SettingsLocalization.Key("$Layout")
  static let text_Toolbar = SettingsLocalization.Key("$Toolbar")

  // Video
  static let hardwareDecoderLabel = SettingsLocalization.Key("hardwareDecoder.label")
  static let text_Decoding = SettingsLocalization.Key("$Decoding")
  static let text_ColorHDR = SettingsLocalization.Key("$ColorHDR")
  static let text_LiveText = SettingsLocalization.Key("$LiveText")
  static let videoThreadsLabel = SettingsLocalization.Key("videoThreads.label")
  static let videoThreadsDesc = SettingsLocalization.Key("videoThreads.desc")
  static let text_nits = SettingsLocalization.Key("$nits")

  // Audio
  static let audioDriverEnableAVFoundationLabel = SettingsLocalization.Key("audioDriverEnableAVFoundation.label")
  static let gaplessAudioLabel = SettingsLocalization.Key("gaplessAudio.label")
  static let preferredAudioDeviceLabel = SettingsLocalization.Key("preferredAudioDevice.label")
  static let text_SPDIFOutput = SettingsLocalization.Key("$SPDIFOutput")
  static let text_SPDIFOutputWarning = SettingsLocalization.Key("$SPDIFOutputWarning")
  static let text_PreferredLanguage = SettingsLocalization.Key("$PreferredLanguage")
  static let text_dB = SettingsLocalization.Key("$dB")
  static let text_Hardware = SettingsLocalization.Key("$Hardware")
  static let text_AudioOther = SettingsLocalization.Key("$Other")
  static let text_Volume = SettingsLocalization.Key("$Volume")

  // Subtitles
  static let subAutoLoadSearchPath = SettingsLocalization.Key("subAutoLoadSearchPath.label")
  static let text_AssrtAPIToken = SettingsLocalization.Key("$AssrtAPIToken")
  static let text_OnlineSubtitles = SettingsLocalization.Key("$OnlineSubtitles")
  static let text_Position = SettingsLocalization.Key("$Position")
  static let text_Font = SettingsLocalization.Key("$Font")
  static let text_Y = SettingsLocalization.Key("$Y")
  static let text_Shadow = SettingsLocalization.Key("$Shadow")
  static let text_X = SettingsLocalization.Key("$X")
  static let text_Advanced = SettingsLocalization.Key("$Advanced")
  static let text_Other = SettingsLocalization.Key("$Other")
  static let text_TextSubtitles = SettingsLocalization.Key("$TextSubtitles")
  static let text_Color = SettingsLocalization.Key("$Color")
  static let text_SubtitleSource = SettingsLocalization.Key("$SubtitleSource")
  static let text_SubtitleSource_desc = SettingsLocalization.Key("$SubtitleSource.desc")
  static let text_LegacyOpenSubAlert = SettingsLocalization.Key("$LegacyOpenSubAlert")
  static let text_SubtitleSourcePluginDesc = SettingsLocalization.Key("$SubtitleSourcePluginDesc")
  static let text_Size = SettingsLocalization.Key("$Size")
  static let text_Login = SettingsLocalization.Key("$Login")
  static let text_DefaultEncoding = SettingsLocalization.Key("$DefaultEncoding")
  static let text_NotLoggedIn = SettingsLocalization.Key("$NotLoggedIn")
  static let text_Offset = SettingsLocalization.Key("$Offset")
  static let text_OtherStyles = SettingsLocalization.Key("$OtherStyles")
  static let text_OverrideLevel = SettingsLocalization.Key("$OverrideLevel")
  static let text_Align = SettingsLocalization.Key("$Align")
  static let text_ASSSubtitles = SettingsLocalization.Key("$ASSSubtitles")
  static let text_Margin = SettingsLocalization.Key("$Margin")
  static let text_AutoLoad = SettingsLocalization.Key("$AutoLoad")
  static let text_Border = SettingsLocalization.Key("$Border")
  static let text_Percent = SettingsLocalization.Key("$Percent")

  // Network
  static let text_Cache = SettingsLocalization.Key("$Cache")
  static let text_Network = SettingsLocalization.Key("$Network")
  static let text_YTDL = SettingsLocalization.Key("$YTDL")
  static let text_ytdlWarning = SettingsLocalization.Key("$ytdlWarning")
  static let text_onlineMediaPluginAdvice = SettingsLocalization.Key("$onlineMediaPluginAdvice")

  // Control
  static let text_Trackpad = SettingsLocalization.Key("$Trackpad")
  static let text_Mouse = SettingsLocalization.Key("$Mouse")

  // Key Bindings
  static let text_ImportAnExistingConfigFile = SettingsLocalization.Key("$ImportAnExistingConfigFile")
  static let text_KeyBindingSet = SettingsLocalization.Key("$KeyBindingSet")
  static let text_ShowTheConfigFileIn = SettingsLocalization.Key("$ShowTheConfigFileIn")
  static let text_Settings = SettingsLocalization.Key("$Settings")
  static let text_NewKeyBindingSet = SettingsLocalization.Key("$NewKeyBindingSet")
  static let text_CreateAnEmptySet = SettingsLocalization.Key("$CreateAnEmptySet")
  static let text_DuplicateCurrentSet = SettingsLocalization.Key("$DuplicateCurrentSet")

  // Advanced
  static let text_AdditionalMpvOptions = SettingsLocalization.Key("$AdditionalMpvOptions")
  static let text_AdditionalMpvOptions_desc = SettingsLocalization.Key("$AdditionalMpvOptions.desc")
  static let text_OpenLogDirectory = SettingsLocalization.Key("$OpenLogDirectory")
  static let text_Logging = SettingsLocalization.Key("$Logging")
  static let text_MPVSettings = SettingsLocalization.Key("$MPVSettings")
  static let text_OpenLogWindow = SettingsLocalization.Key("$OpenLogWindow")

  // Plugin
  static let text_Author = SettingsLocalization.Key("$Author")
  static let text_Help = SettingsLocalization.Key("$Help")
  static let text_Website = SettingsLocalization.Key("$Website")
  static let text_ShowInFinder = SettingsLocalization.Key("$ShowInFinder")
  static let text_YouCanInstallANew = SettingsLocalization.Key("$YouCanInstallANew")
  static let text_Identifier = SettingsLocalization.Key("$Identifier")
  static let text_FailedToLoadThePage = SettingsLocalization.Key("$FailedToLoadThePage")
  static let text_Source = SettingsLocalization.Key("$Source")
  static let text_InstallLocalPackage = SettingsLocalization.Key("$InstallLocalPackage")
  static let text_Uninstall = SettingsLocalization.Key("$Uninstall")
  static let text_About = SettingsLocalization.Key("$About")
  static let text_GetPlugins = SettingsLocalization.Key("$GetPlugins")
  static let text_InputGithubURL = SettingsLocalization.Key("$InputGithubURL")
  static let text_Install = SettingsLocalization.Key("$Install")
  static let text_Installed = SettingsLocalization.Key("$Installed")
  static let text_Installing = SettingsLocalization.Key("$Installing")
  static let text_OrSelectFrom = SettingsLocalization.Key("$OrSelectFrom")
  static let text_ThisPluginIsNot = SettingsLocalization.Key("$ThisPluginIsNot")
  static let text_OfficialPlugins = SettingsLocalization.Key("$OfficialPlugins")
  static let text_NoSelection = SettingsLocalization.Key("$NoSelection")
  static let text_CommunityPlugins = SettingsLocalization.Key("$CommunityPlugins")

  // Utils
  static let text_ClearSavedPlaybackProgress = SettingsLocalization.Key("$ClearSavedPlaybackProgress")
  static let text_DeleteAllPlaybackHistories = SettingsLocalization.Key("$DeleteAllPlaybackHistories")
  static let text_OpenLinksOrCurrentWebpage = SettingsLocalization.Key("$OpenLinksOrCurrentWebpage")
  static let text_OK = SettingsLocalization.Key("$OK")
  static let text_ClearPlaybackHistory = SettingsLocalization.Key("$ClearPlaybackHistory")
  static let text_DefaultApplication = SettingsLocalization.Key("$DefaultApplication")
  static let text_ClearCache = SettingsLocalization.Key("$ClearCache")
  static let text_SetIINAAsTheDefault = SettingsLocalization.Key("$SetIINAAsTheDefault")
  static let text_Firefox = SettingsLocalization.Key("$Firefox")
  static let text_ClearThumbnailCache = SettingsLocalization.Key("$ClearThumbnailCache")
  static let text_Cancel = SettingsLocalization.Key("$Cancel")
  static let text_RestoreAlerts = SettingsLocalization.Key("$RestoreAlerts")
  static let text_RestoreSuppressedAlerts = SettingsLocalization.Key("$RestoreSuppressedAlerts")
  static let text_RestoreAllAlertsThat = SettingsLocalization.Key("$RestoreAllAlertsThat")
  static let text_PleaseSelectTheMediaTypes = SettingsLocalization.Key("$PleaseSelectTheMediaTypes")
  static let text_Chrome = SettingsLocalization.Key("$Chrome")
  static let text_BrowserExtensions = SettingsLocalization.Key("$BrowserExtensions")
  static let text_GetBrowserExtensionsForIINA = SettingsLocalization.Key("$GetBrowserExtensionsForIINA")
  static let text_DeleteAllWatchLater = SettingsLocalization.Key("$DeleteAllWatchLater")
  static let text_Safari = SettingsLocalization.Key("$Safari")
}
