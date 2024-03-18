//
//  OSSubtitle.swift
//  iina
//
//  Created by lhc on 11/3/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation
import Just
import PromiseKit

/// Downloader for [Open Subtitles](https://www.opensubtitles.com/).
/// - Important: This code **should not** be enhanced as the plan is to remove all built-in code for downloading subtitles and
///              replace it with plug-in implementations.
class OpenSub {
  final class Subtitle: OnlineSubtitle {

    private static let dateFormatter: DateFormatter = {
      let dateFormatter = DateFormatter()
      dateFormatter.dateStyle = .medium
      dateFormatter.timeStyle = .none
      return dateFormatter
    }()

    private let subtitle: OpenSubClient.Subtitle

    init(index: Int, subtitle: OpenSubClient.Subtitle) {
      self.subtitle = subtitle
      super.init(index: index)
    }

    /// Asynchronously download this subtitle.
    ///
    /// Downloading requires making two separate requests to [Open Subtitles](https://www.opensubtitles.com/).
    /// Despite its name, the
    /// [Download](https://opensubtitles.stoplight.io/docs/opensubtitles-api/6be7f6ae2d918-download)
    /// REST API method does not return the contents subtitle file. The response from this call contains details related to the quota
    /// imposed by `Open Subtitles` on downloads along with a link that can be used to download the subtitle file contents. Thus
    /// a second request is required to actually download the subtitle file contents.
    /// - Returns: A [URL](https://developer.apple.com/documentation/foundation/url) to the file containing
    ///            the downloaded subtitle.
    override func download() -> Promise<[URL]> {
      let fileId = subtitle.attributes.files[0].fileId
      return OpenSubClient.shared.download(fileId: fileId).then { downloadResponse in
        OpenSubClient.shared.downloadFileContents(downloadResponse.link).then { data in
          Promise { resolver in
            // This check was added after Open Subtitles returned a subtitle file of zero length.
            // Better to catch this error early to make it obvious what the problem is rather than
            // creating a zero length file that triggers a failure during loading.
            if data.isEmpty {
              resolver.reject(Error.emptyFile(
                "Subtitle file \"\(downloadResponse.fileName)\" with ID \(fileId) is empty, no contents"))
              return
            }
            let remaining = String(downloadResponse.remaining)
            let requests = String(downloadResponse.requests)
            log("Download #\(requests), remaining quota \(remaining), quota resets in \(downloadResponse.resetTime)")
            let subFilename = "[\(self.index)]\(downloadResponse.fileName)"
            guard let url = data.saveToFolder(Utility.tempDirURL, filename: subFilename) else {
              resolver.reject(OnlineSubtitle.CommonError.fsError)
              return
            }
            resolver.fulfill([url])
          }
        }
      }
    }

    /// Returns a description of this subtitle suitable for display to the user.
    /// - Returns: A tuple containing the name of this subtitle and the strings to display in the two other columns shown by the
    ///            view displayed to the user for choosing the subtitle files to download.
    override func getDescription() -> (name: String, left: String, right: String) {
      let attributes = subtitle.attributes
      var tokens: [String] = []

      tokens.append(attributes.language)

      if let releaseYear = attributes.featureDetails.year, releaseYear > 0 {
        tokens.append("(\(releaseYear))")
      }

      if let fps = attributes.fps, fps != 0 {
        tokens.append("\(fps.stringMaxFrac2) fps")
      }

      let downloadCount = "\u{2b07}\(attributes.downloadCount)"
      tokens.append(downloadCount)

      let fileName = attributes.files[0].fileName
      let description = tokens.joined(separator: "  ")
      let uploadDate = OpenSub.Subtitle.dateFormatter.string(from: attributes.uploadDate)
      return (fileName, description, uploadDate)
    }
  }

  enum Error: Swift.Error {
    // login failed (reason)
    case loginFailed(String)
    // file error
    case cannotReadFile(Swift.Error)
    case fileTooSmall(Int)
    // search failed (reason)
    case searchFailed(String)
    case emptyFile(String)
  }

  class Fetcher: OnlineSubtitle.DefaultFetcher, OnlineSubtitleFetcher {
    typealias Subtitle = OpenSub.Subtitle

    /// `True` if currently logged in to [Open Subtitles](https://www.opensubtitles.com), `false` otherwise.
    override var loggedIn: Bool { OpenSubClient.shared.loggedIn }

    /// Minimum file size imposed by [Open Subtitles](https://www.opensubtitles.org).
    ///
    /// Open Subtitles limits the size of movies that it supports. This is documented on the wiki page
    /// [HashSourceCodes](https://trac.opensubtitles.org/projects/opensubtitles/wiki/HashSourceCodes):
    ///
    /// On opensubtitles.org is movie file size limited to **9000000000 > $moviebytesize > 131072 bytes**
    ///
    /// - Todo: Enforce the maximum file size.
    private static let minimumFileSize = 131072

    private let chunkSize: Int = 65536

    private let subChooseViewController = SubChooseViewController()

    private var languages: [String] = {
      guard let preferredLanguages = Preference.string(for: .subLang) else {
        Utility.showAlert("sub_lang_not_set")
        return ["en"]
      }
      return preferredLanguages.components(separatedBy: ",")
    }()

    /// The new OpenSubtitle API only supports a fixed set of language codes.
    /// Here we cache the result so `obtainLanguageCodes()` only needs to be called once.
    private static var supportedLanguages: [String] = []

    static let shared = Fetcher()

    func fetch(from url: URL, withProviderID id: String, playerCore player: PlayerCore) -> Promise<[Subtitle]> {
      return login().then { _ in
        self.obtainLanguageCodes()
        }.then {
          self.filterLanguageCodes()
        }.then {
          self.hash(url)
        }.then { hash in
          self.searchForSubtitles(url, hash, player.getMediaTitle())
        }.then { subs in
          self.showSubSelectWindow(with: subs)
        }
    }

    /// Calculate an [Open Subtitles](https://www.opensubtitles.com/) hash code value.
    ///
    /// If a hash code is provided when searching for subtitles then `Open Subtitles` will return matching subtitles first in the
    /// response.
    ///
    /// Calculating the hash code is described in detail in the `Open Subtitles` wiki post
    /// [HashSourceCodes](https://trac.opensubtitles.org/projects/opensubtitles/wiki/HashSourceCodes).
    /// - Note: If the media is being streamed then it is not possible to calculate the hash code and `nil` will be returned.
    /// - Parameter url: Location of the media being played.
    /// - Returns: String containing the hash code or `nil`.
    func hash(_ url: URL) -> Promise<String?> {
      return Promise { resolver in
        guard url.isFileURL else {
          // Cannot create a hash when streaming.
          resolver.fulfill(nil)
          return
        }
        let file: FileHandle
        do {
          file = try FileHandle(forReadingFrom: url)
        } catch {
          resolver.reject(Error.cannotReadFile(error))
          return
        }
        defer { file.closeFile() }

        file.seekToEndOfFile()
        let fileSize = file.offsetInFile

        guard fileSize > OpenSub.Fetcher.minimumFileSize else {
          resolver.reject(Error.fileTooSmall(OpenSub.Fetcher.minimumFileSize))
          return
        }

        let offsets: [UInt64] = [0, fileSize - UInt64(chunkSize)]

        var hash = offsets.map { offset -> UInt64 in
          file.seek(toFileOffset: offset)
          return file.readData(ofLength: chunkSize).chksum64
          }.reduce(0, &+)

        hash += fileSize

        resolver.fulfill(String(format: "%016qx", hash))
      }
    }

    /// Log in to [Open Subtitles](https://www.opensubtitles.com/).
    ///
    /// The `username`/`password` parameters are used to test credentials when the user configuring the account on the
    /// `Subtitle` tab of IINA's settings. Normally the credentials will be retrieved from the macOS `Keychain`.
    ///
    /// This method detects if the user is already logged in and avoids needlessly creating a new user session.
    /// - Parameters:
    ///   - username: User name to test or `nil`.
    ///   - password: Password when testing credentials or `nil`.
    func login(testUser username: String? = nil, password: String? = nil) -> Promise<Void> {
      var finalUser: String? = username
      var finalPw: String? = password
      if finalUser == nil || finalPw == nil {
        // check logged in
        if OpenSubClient.shared.loggedIn {
          log("Already logged in to Open Subtitles")
          return .value
        }
        // read password
        if let udUsername = Preference.string(for: .openSubUsername), !udUsername.isEmpty {
          if let (_, readPassword) = try? KeychainAccess.read(username: udUsername, forService: .openSubAccount) {
            finalUser = udUsername
            finalPw = readPassword
          }
        }
      }
      guard let finalUser = finalUser, let finalPw = finalPw else {
        log("An Open Subtitles account has not been configured")
        return .value
      }
      return OpenSubClient.shared.login(username: finalUser, password: finalPw).then { response in
        Promise { resolver in
          let allowedDownloads = String(response.user.allowedDownloads)
          let vip = response.user.vip ? " as VIP" : ""
          log("Logged in to Open Subtitles\(vip), allowed downloads: \(allowedDownloads)")
          resolver.fulfill(())
        }
      }.recover { error in
        throw Error.loginFailed(error.localizedDescription)
      }
    }

    /// Obtain supported language codes.
    func obtainLanguageCodes() -> Promise<Void> {
      guard Fetcher.supportedLanguages.isEmpty else { return .value }
      return OpenSubClient.shared.languages().then { response in
        Promise { resolver in
          Fetcher.supportedLanguages = response.data.map { $0.languageCode }
          resolver.fulfill(())
        }
      }.recover { error in
        throw OnlineSubtitle.CommonError.networkError(error)
      }
    }

    /// Filter out unsupported language codes.
    ///
    /// IINA's `Preferred language` setting is used when automatically loading local subtitle files as well as when downloading
    /// from subtitle sites. As a result it may contian language codes not supported by Open Subtitles. When logging is enabled this
    /// method will log the language codes in the setting that are not supported by Open Subtitles and will be ignored. This is only
    /// done for ease of debugging.
    func filterLanguageCodes() -> Promise<Void> {
      let supportedCodes = Fetcher.supportedLanguages
      log("Preferred languages: \(languages.sorted().joined(separator: ","))")
      log("Supported languages: \(supportedCodes.sorted().joined(separator: ","))")

      var ignoredCodes: [String] = []
      var filteredCodes: [String] = []
      for language in languages {
        if supportedCodes.contains(language) {
          filteredCodes.append(language)
        } else {
          ignoredCodes.append(language)
        }
      }

      if filteredCodes.isEmpty {
        log("None of the preferred languages are supported: \(ignoredCodes); using en", level: .warning)
        filteredCodes = ["en"]
      } else if !ignoredCodes.isEmpty {
        log("The following preferred languages will be ignored: \(ignoredCodes)")
      } else {
        log("All preferred languages are supported")
      }
      languages = filteredCodes
      return .value
    }

    /// Logout of the user session.
    ///
    /// Open Subtitles requests that applications logout of of user sessions so that they can free resources. This is discussed in the
    /// [Best Practices](https://opensubtitles.stoplight.io/docs/opensubtitles-api/6ef2e232095c7-best-practices)
    /// section of the Open Subtitles REST API documentation.
    /// - Parameter timeout: The timeout to to use for the the request.
    override func logout(timeout: TimeInterval? = nil) -> Promise<Void> {
      guard OpenSubClient.shared.loggedIn else {
        Logger.log("Not logged in to Open Subtitles")
        return .value
      }
      log("Logging out of Open Subtitles")
      return OpenSubClient.shared.logout(timeout: timeout).asVoid().done {
        log("Logged out of Open Subtitles")
      }
    }

    /// Search [Open Subtitles](https://www.opensubtitles.com/) for subtitles for the given movie.
    ///
    /// If no subtitles are found this method will fail with the error `noResult`.
    /// - Parameters:
    ///   - url: A [URL](https://developer.apple.com/documentation/foundation/url) to the movie to search
    ///          for subtitles for.
    ///   - hash: An [Open Subtitles](https://www.opensubtitles.com/) hash code value or `nil`.
    ///   - mediaTitle: The title of the movie.
    /// - Returns: An array containing one or more `Subtitle` objects.
    func searchForSubtitles(_ url: URL, _ hash: String?, _ mediaTitle: String) -> Promise<[Subtitle]> {
      // When streaming prefer the movie's title.
      let searchString = url.isFileURL ? url.deletingPathExtension().lastPathComponent : mediaTitle
      if let hash = hash {
        log("Searching for subtitles of movies with hash \(hash) and matching '\(searchString)'")
      } else {
        log("Searching for subtitles of movies matching '\(searchString)'")
      }
      return OpenSubClient.shared.subtitles(languages: languages, hash: hash, query: searchString).then { response in
        Promise { resolver in
          guard response.totalCount != 0 else {
            resolver.reject(OnlineSubtitle.CommonError.noResult)
            return
          }
          var result: [Subtitle] = []
          for (index, subData) in response.data.enumerated() {
            guard subData.type == "subtitle" else {
              log("Ignoring result with unexpected type: \(subData.type), subtitle ID: \(subData.id)",
                  level: .warning)
              continue
            }
            guard !subData.attributes.files.isEmpty else {
              // Should not occur according to the Open Subtitles REST API documentation which
              // indicates this array must contain at least one entry. However results returned
              // have sometimes violated other documented behavior so it is critical to validate
              // the data returned.
              log("Ignoring result missing file information, subtitle ID: \(subData.id)",
                  level: .warning)
              continue
            }
            result.append(Subtitle(index: index, subtitle: subData))
          }
          guard !result.isEmpty else {
            // The normal case where no subtitles were found is caught above. The subtitles returned
            // must have been ignored.
            resolver.reject(OnlineSubtitle.CommonError.noResult)
            return
          }
          resolver.fulfill((result))
        }
      }.recover { error -> Promise<[Subtitle]> in
        switch error {
        case OnlineSubtitle.CommonError.noResult:
          throw error
        default:
          throw Error.searchFailed(error.localizedDescription)
        }
      }
    }

    func showSubSelectWindow(with subs: [Subtitle]) -> Promise<[Subtitle]> {
      return Promise { resolver in
        // return when found 0 or 1 sub
        if subs.count <= 1 {
          resolver.fulfill(subs)
          return
        }
        subChooseViewController.subtitles = subs
        subChooseViewController.context = self

        subChooseViewController.userDoneAction = { subs in
          resolver.fulfill(subs as! [Subtitle])
        }
        subChooseViewController.userCanceledAction = {
          resolver.reject(OnlineSubtitle.CommonError.canceled)
        }
        PlayerCore.active.sendOSD(.foundSub(subs.count), autoHide: false, accessoryView: subChooseViewController.view)
        subChooseViewController.tableView.reloadData()
      }
    }
  }

  private static func log(_ message: String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: Logger.Sub.opensub)
  }
}

extension Logger.Sub {
  static let opensub = Logger.makeSubsystem("opensub")
}
