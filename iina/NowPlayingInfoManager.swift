//
//  NowPlayingInfoManager.swift
//  iina
//
//  Created by low-batt on 5/3/25.
//  Copyright © 2025 lhc. All rights reserved.
//

import Foundation
import MediaPlayer
import QuickLookThumbnailing

/// Manager that supports using the macOS
/// [Control Center](https://support.apple.com/guide/mac-help/quickly-change-settings-mchl50f94f8f/mac)
/// Now Playing module.
///
/// The macOS [Control Center](https://support.apple.com/guide/mac-help/quickly-change-settings-mchl50f94f8f/mac)
/// contains a Now Playing module. This module can also be configured to be directly accessible from the menu bar. Now Playing
/// displays the title of the media currently  playing and other information about the state of playback. It also can be used to control
/// playback.
///
/// The IINA setting `Use system media control` found on the `Key Bindings` tab of IINA's settings controls use of this
/// macOS feature. This class handles the use of the AppKit class
/// [MPNowPlayingInfoCenter](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
/// which allows IINA to populate the information shown in the Now Playing module. This class makes use of the IINA class
/// `RemoteCommandController` to address the other aspect of [becoming a now playable app](https://developer.apple.com/documentation/mediaplayer/becoming-a-now-playable-app)], handling
/// remote commands.
/// - Important: As IINA is assuming control over a shared macOS feature it is critical that IINA releases control when no media is
///     open. See issue [#4331](https://github.com/iina/iina/issues/4331).
class NowPlayingInfoManager {
  /// The `NowPlayingInfoManager` singleton object.
  static let shared = NowPlayingInfoManager()

  /// Minimum size for artwork.
  ///
  /// This is the size of the space the Now Playing module provides for displaying artwork..
  private let artworkDesiredSize = 768.0

  /// Portions of the work to update the artwork shown in Now Playing are performed in the background.
  private let artworkQueue: DispatchQueue = DispatchQueue(label: "com.colliderli.iina.artwork",
                                                          qos: .utility)

  /// Kind of artwork being shown in Now Playing.
  @Atomic private var artworkKind: ArtworkKind = .none

  /// The number of video tracks the last time the tracks were searched for artwork.
  private var artworkLastTrackCount = 0

  /// Maximum number of times to request  [QLThumbnailGenerator](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator)
  /// generate a thumbnail for the current media item.
  private let artworkQLGenerationMaxRetries = 3

  /// Number of times IINA has requested  [QLThumbnailGenerator](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator)
  /// generate a thumbnail for the current media item.
  private var artworkQLGenerationRetries = 0

  /// Ticket used to coordinate with background tasks performing work to update the artwork shown by Now Playing.
  private var artworkTicket = 0

  /// Whether work is currently being performed in the background to update the artwork shown by Now Playing.
  private var artworkUpdateInProgress = false

  /// Whether a request to update the artwork came in while an artwork update was being performed in the background.
  private var artworkUpdatePending = false

  /// Whether a Now Playing session is active.
  private var isActive = false

  /// Established notification observers.
  private var observers: [NSObjectProtocol] = []

  /// Playback position to obtain an On Screen Controller thumbnail at.
  ///
  /// This matches the default playback position used by
  /// [QuickLook Video](https://github.com/Marginal/QLVideo/tree/master) for creating thumbnails.
  private let oscThumbnailPosition = 60.0

  /// Size of thumbnail to request [QLThumbnailGenerator](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator)
  /// generate.
  ///
  /// This matches the size mpv uses. Using sizes larger than this can cause `QLThumbnailGenerator` to fail.
  private let qlThumbnailSize = CGSize(width: 2000, height: 2000)

  /// The URL of the media item in the Now Playing session.
  private var url: URL?

  /// Update the information shown by macOS in the
  /// [Control Center](https://support.apple.com/guide/mac-help/quickly-change-settings-mchl50f94f8f/mac)
  /// Now Playing module.
  /// - Important: This method **must** be run on the main thread because it references `PlayerCore.lastActive`.
  func updateInfo(withTitle: Bool = false) {
    guard RemoteCommandController.useSystemMediaControl else { return }

    let center = MPNowPlayingInfoCenter.default()
    let player = PlayerCore.lastActive
    guard player.info.state.active else {
      if isActive {
        RemoteCommandController.shared.disable()
        if let url {
          discardArtwork(url)
        }
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
        isActive = false
        url = nil
        log("Ended Now Playing session")
      }
      return
    }

    guard let currentURL = player.info.currentURL else {
      // Internal error, should not occur.
      log("Ignoring update request because currentURL is nil", level: .error)
      return
    }
    if currentURL != url {
      guard withTitle else {
        // Internal error, URL should only change when being told to change the title.
        log("Attempt to change URL to: \(currentURL.mpvStr) with title set to false", level: .error)
        return
      }
      if let url {
        log("Switching Now Playing session from: \(url.mpvStr)\n  to: \(currentURL.mpvStr)")
        // If the media item has changed then if artwork is being displayed or being worked on in
        // the background it must be discarded.
        discardArtwork(url)
      } else {
        log("Starting Now Playing session", currentURL)
      }
      url = currentURL
    }

    // Obtain a copy of the nowPlayingInfo dictionary. NOTE this MUST be done AFTER any calls to
    // discardArtwork as that method works directly on the nowPlayingInfo dictionary.
    var info = center.nowPlayingInfo ?? [String: Any]()
    if withTitle {
      if player.currentMediaIsAudio == .isAudio {
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        let (title, album, artist) = player.getMusicMetadata()
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyAlbumTitle] = album
        info[MPMediaItemPropertyArtist] = artist
      } else {
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        info[MPMediaItemPropertyTitle] = player.getMediaTitle(withExtension: false)
        info.removeValue(forKey: MPMediaItemPropertyAlbumTitle)
        info.removeValue(forKey: MPMediaItemPropertyArtist)
      }
    }

    info[MPNowPlayingInfoPropertyAssetURL] = url
    player.info.$playlist.withLock { playlist in
      info[MPNowPlayingInfoPropertyPlaybackQueueCount] = playlist.count
      if let index = playlist.firstIndex(where: { $0.filename == currentURL.mpvStr }) {
        info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
      } else {
        // This can occur when the playlist is still being populated.
        info.removeValue(forKey: MPNowPlayingInfoPropertyPlaybackQueueIndex)
      }
    }
    if player.info.chapters.isEmpty {
      info.removeValue(forKey: MPNowPlayingInfoPropertyChapterCount)
      info.removeValue(forKey: MPNowPlayingInfoPropertyChapterNumber)
    } else {
      info[MPNowPlayingInfoPropertyChapterCount] = player.info.chapters.count
      info[MPNowPlayingInfoPropertyChapterNumber] = player.info.chapter
    }

    let duration = player.info.videoDuration?.second ?? 0
    let time = player.info.videoPosition?.second ?? 0

    // When playback is paused Now Playing expects the playback rate to be set to zero. If this is
    // not done the slider in Now Playing may incorrectly display a playback time of zero.
    let paused = player.info.state == .paused
    let speed = paused ? 0 : player.info.playSpeed

    info[MPMediaItemPropertyPlaybackDuration] = duration
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
    info[MPNowPlayingInfoPropertyPlaybackRate] = speed
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1

    center.nowPlayingInfo = info

    // If under "When media is opened" the "Pause" setting is enabled then playback will be
    // initially paused. For reasons unknown changing the media and not initially playing causes
    // Now Playing to drop IINA and go back to showing the Music app. Workaround this problem by
    // setting playbackState initially to playing and then immediately set it to paused.
    if withTitle, paused {
      center.playbackState = .playing
    }
    center.playbackState = paused ? .paused : .playing

    // Because showing artwork is a complex operation there is an internal setting that can be
    // changed to disable this feature should any problems with it be discovered.
    if Preference.bool(for: .enableNowPlayingArtwork) {
      // If the best kind of artwork (front cover) is not being displayed then try and update
      // to a better kind of artwork.
      if artworkKind.need(.frontCover) {
        updateArtwork(player, currentURL, player.info.videoTracks)
      }
    } else {
      log("Showing cover artwork is disabled", level: .verbose)
    }

    let suffix = """
      set elapsed playback time: \(time) rate: \(speed) state: \(center.playbackState),
      """
    if isActive {
      log("Updated Now Playing information, \(suffix)", currentURL, level: .verbose)
    } else {
      isActive = true
      log("Started Now Playing session, \(suffix)", currentURL)
    }
    RemoteCommandController.shared.enable()
  }

  // MARK: - Artwork

  /// Indicate the current artwork update has completed and process any pending artwork update.
  /// - Important: This method **must** be run on the main thread because it references `PlayerCore.lastActive` and to
  ///         avoid data races.
  private func artworkUpdateComplete() {
    artworkUpdateInProgress = false
    guard artworkUpdatePending else { return }
    // An artwork update was requested while one was being processed in a background task.
    artworkUpdatePending = false
    // If we already have the best kind of artwork there is nothing to do.
    guard artworkKind.need(.frontCover) else { return }
    // Player could have changed while artwork was being processed in the background. Make certain
    // the current player is active. All other checks will be handled by updateInfo.
    guard PlayerCore.lastActive.info.state.active else { return }
    log("Processing pending artwork update", level: .verbose)
    updateInfo()
  }

  /// Construct an image for the artwork represented by the given video track.
  /// - Parameters:
  ///   - url: The URL of the media item.
  ///   - track: Video track representing the image.
  /// - Returns: The image or `nil` if the image could not be constructed.
  private func constructImage(_ url: URL, _ track: MPVTrack) -> NSImage? {
    guard track.isExternal else {
      // The album art is embedded in the track. At this time there is not an API to obtain the
      // image from mpv. Read the artwork from the file.
      guard let image = FFmpegController.readArtwork(from: url) else {
        // If this happens it means mpv has different criteria for what it considers cover art.
        log("Embedded front cover artwork not found", url, level: .warning)
        return nil
      }
      return image
    }
    // The album art is an external file.
    guard let filename = track.externalFilename else {
      // Internal error. This should not occur.
      log("External artwork track is missing external-filename", url, level: .error)
      return nil
    }
    guard let image = NSImage(contentsOfFile: filename) else {
      log("Unable to create an image for external artwork file: \(filename)", level: .error)
      return nil
    }
    return image
  }

  /// Discard any existing artwork and any artwork update that is in progress.
  ///
  /// This method:
  /// - Invalidates the ticket held by any background artwork update task
  /// - Resets `artworkKind` back to `none`, to indicate artwork is needed
  /// - Clears any pending artwork update
  /// - Discards any existing artwork set in `nowPlayingInfo`
  /// - Important: The `artworkUpdateInProgress` flag is intentionally not cleared to prevent multiple background
  ///     artwork updates from running at the same time. This could happen as background work does not only occur in the
  ///     `artworkQueue`.  [QLThumbnailGenerator](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator)
  ///     has its own threads. The background work is allowed to complete and the results are then discarded due to the change in
  ///     `artworkTicket`.
  /// - Important: This method **must** be run on the main thread to avoid data races.
  /// - Parameter url: The URL of the media item.
  private func discardArtwork(_ url: URL) {
    // Because showing artwork is a complex operation there is an internal setting that can be
    // changed to disable this feature should any problems with it be discovered.
    guard Preference.bool(for: .enableNowPlayingArtwork) else { return }
    // Changing artworkTicket will cause any background task to discard its work when it finishes.
    artworkTicket += 1
    artworkKind = .none
    artworkQLGenerationRetries = 0
    artworkUpdatePending = false
    artworkLastTrackCount = 0
    MPNowPlayingInfoCenter.default().nowPlayingInfo?.removeValue(
      forKey: MPMediaItemPropertyArtwork)
    guard artworkUpdateInProgress else { return }
    log("Will discard the results of the current in progress artwork update", url, level: .verbose)
  }

  /// Constructs a
  /// [MPMediaItemArtwork](https://developer.apple.com/documentation/mediaplayer/mpmediaitemartwork)
  /// object for the given image.
  /// - Parameters:
  ///   - player: The `PlayerCore` for which to find artwork for.
  ///   - image: Artwork image for the media item.
  /// - Returns: The constructed `MPMediaItemArtwork` object.
  private func formMPMediaItemArtwork(_ player: PlayerCore, _ image: CGImage) -> MPMediaItemArtwork {
    // If available, use the video size for the bounds size. Otherwise fall back to the image size.
    let size = image.size
    let boundsSize: CGSize = {
      guard size.width < artworkDesiredSize || size.height < artworkDesiredSize else {
        // The image size is equal to or larger than size of the area the Now Playing module
        // provides for artwork.
        return size
      }
      // The image is smaller than the size desired by the Now Playing module. If the image's size
      // is used for boundsSize then the Now Playing module will specify a small size for the new
      // size of the image and will then add grey bars around the image when displaying the artwork.
      // To avoid the grey bars our request handler below will crop and resize the image as needed,
      // but to get Now Playing to request the full size it can handle boundsSize must be large
      // enough. Scale up the image size.
      let width: Double
      let height: Double
      if size.width > size.height {
        height = artworkDesiredSize
        width = height * size.aspect
      } else {
        width = artworkDesiredSize
        height = width / size.aspect
      }
      log("Artwork scaled up bounds size: \(width)x\(height)", level: .verbose)
      return CGSize(width: width, height: height)
    }()
    return MPMediaItemArtwork(boundsSize: boundsSize) { [self] size in
      // Crop to aspect ratio of requested size, rather than stretching/squeezing. Then resize.
      let cropRect = image.size.getCropRect(withAspect: size.aspect)
      let suffix = """
        \(Int(image.width))x\(Int(image.height)) artwork image \
        to \(Int(size.width))x\(Int(size.height))
        """
      if let artwork = image.cropping(to: cropRect)?.resized(newWidth: size.widthInt,
                                                             newHeight: size.heightInt).nsImage {
        log("Cropped and resized \(suffix)", level: .verbose)
        return artwork
      }
      log("Unable to crop \(suffix)", level: .warning)
      return image.nsImage.resized(newWidth: size.widthInt, newHeight: size.heightInt)
    }
  }

  /// Display the given artwork image in Now Playing.
  ///
  /// This method constructs a [MPMediaItemArtwork](https://developer.apple.com/documentation/mediaplayer/mpmediaitemartwork)
  /// object and sets [MPMediaItemPropertyArtwork](https://developer.apple.com/documentation/mediaplayer/mpmediaitempropertyartwork)
  /// in [nowPlayingInfo](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter/nowplayinginfo).
  /// - Parameters:
  ///   - player: The `PlayerCore` that is playing the media item.
  ///   - url: The URL of the media item.
  ///   - image: The artwork image.
  ///   - artworkKind: The kind of artwork being displayed (front cover, Quick Look thumbnail, etc.).
  private func foundArtwork(_ player: PlayerCore, _ url: URL, _ image: NSImage,
                            _ artworkKind: ArtworkKind) {
    let center = MPNowPlayingInfoCenter.default()
    guard center.nowPlayingInfo != nil else {
      // This is an internal error. The artworkTicket should be checked before calling this method.
      // That should prevent this method from being called when there is no session.
      log("No active Now Playing session, discarded \(artworkKind)", url, level: .error)
      return
    }
    guard let cgImage = image.cgImage else {
      // This should not occur.
      log("Unable to construct a CGImage, discarded \(artworkKind)", url, level: .error)
      return
    }
    log("Found \(artworkKind)", url)
    center.nowPlayingInfo?[MPMediaItemPropertyArtwork] = formMPMediaItemArtwork(player, cgImage)
    self.artworkKind = artworkKind
  }

  /// Found front cover artwork.
  ///
  /// This method will check to see if this background work has been discarded and if not then it will display the given artwork
  /// image in Now Playing.
  /// - Parameters:
  ///   - player: The `PlayerCore` that is playing the media item.
  ///   - url: The URL of the media item.
  ///   - ticket: Value of `artworkTicket` when this update was initiated.
  ///   - image: The artwork image.
  private func foundFrontCoverArtwork(_ player: PlayerCore, _ url: URL, _ ticket: Int,
                                      _ image: NSImage) {
    // Must run this on the main thread to properly coordinate background work.
    DispatchQueue.main.async { [self] in
      defer { artworkUpdateComplete() }
      guard artworkTicket == ticket else {
        log("Discarded stale \(ArtworkKind.frontCover)", url, level: .verbose)
        return
      }
      foundArtwork(player, url, image, .frontCover)
    }
  }

  /// Generate a Quick Look thumbnail to use as artwork.
  ///
  /// This method requests
  /// [QLThumbnailGenerator](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator)
  /// generate a thumbnail. Generation occurs in the background and a handler is called upon completion. Generation may not be
  /// successful as by default `QLThumbnailGenerator` does not support many of the media files IINA does. The Quick Look
  /// system supports thumbnail extensions. If a user has installed [QuickLook Video](https://github.com/Marginal/QLVideo/tree/master)
  /// `QLThumbnailGenerator` will be able to generate thumbnails for most types of video files.
  /// - Parameters:
  ///   - player: The `PlayerCore` that is playing the media item.
  ///   - url: The URL of the media item.
  ///   - ticket: Value of `artworkTicket` when this update was initiated.
  private func generateQLThumbnail(_ player: PlayerCore, _ url: URL, _ ticket: Int) {
    log("Requesting QLThumbnailGenerator generate a thumbnail", url, level: .verbose)
    // Because the artwork display in Now Playing is so tiny a low quality thumbnail is sufficient.
    let request = QLThumbnailGenerator.Request(fileAt: url, size: qlThumbnailSize, scale: 1,
                                               representationTypes: .lowQualityThumbnail)
    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, error in
      DispatchQueue.main.async { [self] in
        defer { artworkUpdateComplete() }
        guard artworkTicket == ticket else {
          log("Discarded stale QLThumbnailGenerator results", url, level: .verbose)
          return
        }
        if let error {
          // This is intentionally not logged as an error because by default the generator does not
          // support many of the media files IINA does, so failures are expected.
          log("QLThumbnailGenerator failed: \(error)", level: .verbose)
        }
        guard let image = thumbnail?.nsImage else {
          log("QLThumbnailGenerator did not generate a thumbnail", url, level: .verbose)
          // Fall back to using an OSC thumbnail for the artwork.
          useOSCThumbnail(player, url)
          return
        }
        foundArtwork(player, url, image, .qlThumbnail)
      }
    }
  }

  /// Search the given video tracks for front cover art.
  ///
  /// Container formats such as Matroska support embedding cover art. An external file can be specified as cover art using the mpv
  /// option [cover-art-files](https://mpv.io/manual/stable/#options-cover-art-files). If the media being "played" is
  /// an image file then it will be used as the artwork.
  /// - Parameters:
  ///   - player: The `PlayerCore` that is playing the media item.
  ///   - url: The URL of the media item.
  ///   - ticket: Value of `artworkTicket` when this update was initiated.
  ///   - tracks: Video tracks to search.
  /// - Returns: `True` if artwork was found; `false` otherwise.
  private func searchTracksForArtwork(_ player: PlayerCore, _ url: URL, _ ticket: Int,
                                      _ tracks: [MPVTrack]) -> Bool {
    guard !tracks.isEmpty else { return false }
    log("Searching \(tracks.count) tracks for front cover artwork", url, level: .verbose)
    for track in tracks {
      // Only interested in tracks representing an image.
      guard track.isImage else { continue }
      if track.isAlbumart {
        guard let image = constructImage(url, track) else { continue }
        foundFrontCoverArtwork(player, url, ticket, image)
        return true
      }
      // The media item is an image.
      guard let image = NSImage(contentsOf: url) else {
        log("Unable to create an image from: \(url)", level: .error)
        continue
      }
      foundFrontCoverArtwork(player, url, ticket, image)
      return true
    }
    log("Did not find front cover artwork", url, level: .verbose)
    return false
  }

  /// Update the artwork supplied in [MPMediaItemPropertyArtwork](https://developer.apple.com/documentation/mediaplayer/mpmediaitempropertyartwork), if needed.
  ///
  /// There are 3 kinds of artwork. In order of most preferred to least preferred they are:
  /// - Front cover artwork
  /// - Quick Look thumbnail
  /// - On Screen Controller thumbnail
  ///
  /// What kind of artwork is available can change over time as the media item is being loaded:
  /// - Front cover artwork will not be available until mpv has populated the video track
  /// - Quick Look thumbnail is generated asynchronously and may not be available on the first request
  /// - On Screen Controller thumbnail will not be available until IINA has generated thumbnails
  ///
  /// The best artwork available at the time of this update will be used. A future call to this method may upgrade the artwork if a
  /// better kind of artwork becomes available.
  ///
  /// There may not be any artwork available for the media item:
  /// - Front cover artwork may not have been supplied
  /// - Quick Look thumbnail may be missing because by default Quick Look does not support all the types of media IINA does
  /// - On Screen Controller thumbnail may be missing because the user disabled the `Enable thumbnail preview` setting
  ///
  /// When `MPMediaItemPropertyArtwork` is not supplied the Now Playing module will use IINA's app icon.
  ///
  /// Longer operations are performed in the background using `artworkQueue` or by [QLThumbnailGenerator](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator)
  /// using its own threads. The main thread is used for coordination with the background work.
  /// - Parameters:
  ///   - player: The `PlayerCore` that is playing the media item.
  ///   - url: The URL of the media item.
  ///   - tracks: The current list of video tracks.
  private func updateArtwork(_ player: PlayerCore, _ url: URL, _ tracks: [MPVTrack]) {
    guard !artworkUpdateInProgress else {
      // An artwork update is currently in progress in the background. Something could have
      // changed, such as a video track being added, or OSC thumbnails becoming available that
      // could change the artwork selection. Do not allow concurrent processing. Remember an
      // updated is pending and process it once the current update has completed.
      if !artworkUpdatePending {
        log("Artwork update pending", level: .verbose)
      }
      artworkUpdatePending = true
      return
    }
    artworkUpdateInProgress = true
    // Copy state that can change for use by the background task.
    let isNetworkResource = player.info.isNetworkResource
    let ticket = artworkTicket
    let tracks = player.info.videoTracks
    artworkQueue.async { [self] in
      // Look for front cover artwork. If found, no need to do anything more.
      guard !searchTracksForArtwork(player, url, ticket, tracks) else { return }

      // When streaming artwork can be found in video tracks either because the stream contains
      // embedded artwork or an image to use for artwork was specified using --cover-art-files.
      // But the other sources of artwork, Quick Look and the OSC thumbnails are not available when
      // streaming.
      guard !isNetworkResource else {
        DispatchQueue.main.async { self.artworkUpdateComplete() }
        return
      }

      // If we already have a Quick Look thumbnail then nothing more to do. NOTE that we are
      // reading artworkKind from a background thread and it may not represent the media item
      // currently being processed in artworkQueue and could change at any point in time. This
      // is not a problem has actions are coordinated using the ticket once running on the main
      // thread.
      guard artworkKind.need(.qlThumbnail) else {
        DispatchQueue.main.async { [self] in
          defer { artworkUpdateComplete() }
          guard artworkTicket == ticket else { return }
          log("Already using a Quick Look thumbnail for artwork", url, level: .verbose)
        }
        return
      }

      // Quick Look thumbnail generation may initially fail due to thumbnail creation taking too
      // long. But because the generator caches thumbnails a following request for the same
      // thumbnail may succeed. Thus we want to retry generation requests, but limit the number
      // of retries as the generator may be failing due to it not supporting the kind of media.
      if artworkQLGenerationRetries == artworkQLGenerationMaxRetries {
        log("Maximum number of Quick Look thumbnail generation attempts reached", level: .verbose)
      }
      artworkQLGenerationRetries += 1
      guard artworkQLGenerationRetries <= artworkQLGenerationMaxRetries else {
        // Skip Quick Look generation and fall back to using an OSC thumbnail for the artwork.
        DispatchQueue.main.async { [self] in
          defer { artworkUpdateComplete() }
          guard artworkTicket == ticket else { return }
          useOSCThumbnail(player, url)
        }
        return
      }

      // Try and generate a Quick Look thumbnail. Because QLThumbnailGenerator generates thumbnails
      // in the background and then calls a completion handler, the fallback to an OSC thumbnail
      // is handled in generateQLThumbnail.
      generateQLThumbnail(player, url, ticket)
    }
  }

  /// Use an On Screen Controller thumbnail for the artwork (if available).
  /// - Parameters:
  ///   - player: The `PlayerCore` that is playing the media item.
  ///   - url: The URL of the media item.
  private func useOSCThumbnail(_ player: PlayerCore, _ url: URL) {
    guard artworkKind.need(.oscThumbnail) else {
      log("Already using an OSC thumbnail for artwork", url, level: .verbose)
       return
    }
    guard Preference.bool(for: .enableThumbnailPreview) else {
      log("OSC thumbnail previews are disabled", level: .verbose)
      return
    }
    guard player.info.thumbnailsReady else {
      log("OSC thumbnails are still being generated or read from the cache", url, level: .verbose)
      return
    }
    // If we don't know the duration of the video assume it is twice the position at which
    // we would like to obtain a thumbnail.
    let twice = 2 * oscThumbnailPosition
    let duration = player.info.videoDuration ?? VideoTime(twice)
    // If the video is short then obtain a thumbnail at the midpoint of the video. This somewhat
    // matches up with how QuickLook Video selects the position at which to create a thumbnail.
    let position = duration.second < twice ? duration.second / 2 : oscThumbnailPosition
    guard let thumbnail = player.info.getThumbnail(forSecond: position)?.image else {
      log("Did not find an OSC thumbnail at \(position)", url, level: .verbose)
      return
    }
    foundArtwork(player, url, thumbnail, .oscThumbnail)
  }

  // MARK: - Utils

  private func log(_ message: @autoclosure () -> String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: Logger.Sub.nowPlaying)
  }

  private func log(_ message: String, _ url: URL, level: Logger.Level = .debug) {
    log(message + " for: \(url.mpvStr)", level: level)
  }

  private func observe(_ name: Notification.Name, block: @escaping (Notification) -> Void) {
    observers.append(NotificationCenter.default.addObserver(forName: name, object: nil,
                                                            queue: .main, using: block))
  }

  // MARK: - Artwork Kinds

  /// The various kinds  of artwork for a media item.
  ///
  /// There are 3 kinds of artwork. In order of most preferred to least preferred they are:
  /// - Front cover artwork
  /// - Quick Look thumbnail
  /// - On Screen Controller thumbnail
  enum ArtworkKind: Int, CustomStringConvertible {
    case none
    case oscThumbnail
    case qlThumbnail
    case frontCover

    /// Description of the artwork kind for use in log messages.
    var description: String {
      switch self {
      case .none: return "none"
      case .oscThumbnail: return "OSC thumbnail"
      case .qlThumbnail: return "Quick Look thumbnail"
      case .frontCover: return "front cover artwork"
      }
    }

    /// Determine if the given kind of artwork is preferred over this kind.
    /// - Parameter kind: The kind of artwork to compare to this kind.
    /// - Returns: `True` if the given artwork kind is needed; `false` otherwise.
    @inlinable func need(_ kind: ArtworkKind) -> Bool { self.rawValue < kind.rawValue }
  }

  // MARK: - Initializer

  private init() {
    // Because showing artwork is a complex operation there is an internal setting that can be
    // changed to disable this feature should any problems with it be discovered. No need to listen
    // for changes to the track list if we are not searching tracks for artwork.
    guard Preference.bool(for: .enableNowPlayingArtwork) else { return }
    observe(.iinaTracklistChanged) { [unowned self] notification in
      // A track list change can not establish a Now Playing session. If one is not active ignore
      // this notification. If the best kind of artwork has already been found then there is no
      // need to search tracks for a better kind of artwork.
      guard isActive, artworkKind.need(.frontCover) else { return }
      guard let player = notification.object as? PlayerCore else {
        // This is an internal error. The notification object must be a PlayerCore.
        log("iinaTracklistChanged notification object is not a PlayerCore", level: .error)
        return
      }
      // Only the active player can own the Now Playing session, ignore track list changes for
      // background players. If the URL does not match then that means the player is in the process
      // of loading new media. Must wait for the player to call updateInfo when the media starts
      // playing.
      guard player == PlayerCore.lastActive, let currentURL = player.info.currentURL,
            currentURL == url else { return }
      // The track list can change a lot due to subtitle tracks being loaded. Avoid trying to update
      // the artwork if the number of video tracks has not changed since the last time they were
      // searched for artwork.
      let tracks = player.info.videoTracks
      guard tracks.count != artworkLastTrackCount else { return }
      artworkLastTrackCount = tracks.count
      log("Processing change in number of video tracks (\(tracks.count))", currentURL)
      updateInfo()
    }
  }

  deinit {
    observers.forEach {
      NotificationCenter.default.removeObserver($0)
    }
  }
}

// MARK: - Extensions

extension MPNowPlayingPlaybackState: @retroactive CustomStringConvertible {
  public var description: String {
    switch self {
    case .unknown: return "unknown"
    case .playing: return "playing"
    case .paused: return "paused"
    case .stopped: return "stopped"
    case .interrupted: return "interrupted"
    @unknown default: return String(self.rawValue)
    }
  }
}

extension Logger.Sub {
  static let nowPlaying = Logger.makeSubsystem("now-playing")
}
