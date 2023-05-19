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
import Gzip

class OpenSub {
  final class Subtitle: OnlineSubtitle {
    var filename: String = ""
    var langID: String
    var addDate: String
    var rating: String
    var dlCount: String
    var subDlLink: String

    init(index: Int, filename: String, langID: String, addDate: String, rating: String, dlCount: String, subDlLink: String) {
      self.filename = filename
      self.langID = langID
      self.addDate = addDate
      self.rating = rating
      self.dlCount = dlCount
      self.subDlLink = subDlLink
      super.init(index: index)
    }

    override func download() -> Promise<[URL]> {
      return Promise { resolver in
        Just.get(subDlLink, asyncCompletionHandler: { response in
          guard response.ok, let data = response.content, let unzipped = try? data.gunzipped() else {
            resolver.reject(OnlineSubtitle.CommonError.networkError(response.error))
            return
          }
          let subFilename = "[\(self.index)]\(self.filename)"
          guard let url = unzipped.saveToFolder(Utility.tempDirURL, filename: subFilename) else {
            resolver.reject(OnlineSubtitle.CommonError.fsError)
            return
          }
          resolver.fulfill([url])
        })
      }
    }

    override func getDescription() -> (name: String, left: String, right: String) {
      (
        filename,
        "\(langID) \u{2b07}\(dlCount) \u{2605}\(rating)",
        addDate
      )
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
    // lower level error
    case wrongResponseFormat
    case xmlRpcError(JustXMLRPC.XMLRPCError)
  }


  class Fetcher: OnlineSubtitle.DefaultFetcher, OnlineSubtitleFetcher {
    typealias Subtitle = OpenSub.Subtitle

    struct FileInfo {
      var hashValue: String
      var fileSize: UInt64

      var dictionary: [String: String] {
        get {
          return [
            "moviehash": hashValue,
            "moviebytesize": "\(fileSize)"
          ]
        }
      }
    }

    typealias ResponseFilesData = [[String: Any]]

    /// Minimum file size imposed by [Open Subtitles](https://www.opensubtitles.org).
    ///
    /// Open Subtitles limits the size of movies that it supports. This is documented on the wiki page [HashSourceCodes](https://trac.opensubtitles.org/projects/opensubtitles/wiki/HashSourceCodes):
    ///
    /// On opensubtitles.org is movie file size limited to **9000000000 > $moviebytesize > 131072 bytes**
    ///
    /// - Todo: Enforce the maximum file size.
    private static let minimumFileSize = 131072

    private let chunkSize: Int = 65536
    private let apiPath = "https://api.opensubtitles.org:443/xml-rpc"
    private let xmlRpc: JustXMLRPC

    private let subChooseViewController = SubChooseViewController()

    var language: String

    let ua: String = {
      let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
      return "IINA v\(version)"
    }()
    var token: String!

    var heartBeatTimer: Timer?
    let heartbeatInterval = TimeInterval(800)

    static let shared = Fetcher()

    required init() {
      let userLang = Preference.string(for: .subLang) ?? ""
      if userLang.isEmpty {
        Utility.showAlert("sub_lang_not_set")
        self.language = "eng"
      } else {
        self.language = userLang
      }
      self.xmlRpc = JustXMLRPC(apiPath)
    }

    func fetch(from url: URL, withProviderID id: String, playerCore player: PlayerCore) -> Promise<[Subtitle]> {
      return login()
      .then { _ in
        self.hash(url, player.info.isNetworkResource)
      }.then { info in
        self.requestByHashAndSize(info)
      }.recover { error -> Promise<[Subtitle]> in
        if case OnlineSubtitle.CommonError.noResult = error {
          return self.requestByName(url, player.info.isNetworkResource, player.getMediaTitle())
        } else {
          throw error
        }
      }.then { subs in
        self.showSubSelectWindow(with: subs)
      }
    }

    private func findPath(_ path: [String], in data: Any) throws -> Any? {
      var current: Any? = data
      for arg in path {
        guard let next = current as? [String: Any] else { throw Error.wrongResponseFormat }
        current = next[arg]
      }
      return current
    }

    private func checkStatus(_ data: Any) -> Bool {
      if let parsed = try? findPath(["status"], in: data) {
        return (parsed as? String ?? "").hasPrefix("200")
      } else {
        return false
      }
    }

    func login(testUser username: String? = nil, password: String? = nil) -> Promise<Void> {
      return Promise { resolver in
        var finalUser = ""
        var finalPw = ""
        if let testUser = username, let testPw = password {
          // if test login
          finalUser = testUser
          finalPw = testPw
        } else {
          // check logged in
          if self.loggedIn {
            resolver.fulfill(())
            return
          }
          // read password
          if let udUsername = Preference.string(for: .openSubUsername), !udUsername.isEmpty {
            if let (_, readPassword) = try? KeychainAccess.read(username: udUsername, forService: .openSubAccount) {
              finalUser = udUsername
              finalPw = readPassword
            }
          }
        }
        // login
        xmlRpc.call("LogIn", [finalUser, finalPw, "eng", ua]) { status in
          switch status {
          case .ok(let response):
            // OK
            guard let parsed = (response as? [String: Any]) else {
              resolver.reject(Error.wrongResponseFormat)
              return
            }
            // check status
            let pStatus = parsed["status"] as! String
            if pStatus.hasPrefix("200") {
              self.token = parsed["token"] as? String
              log("OpenSub: logged in as user \(finalUser)")
              self.startHeartbeat()
              resolver.fulfill(())
            } else {
              resolver.reject(Error.loginFailed(pStatus))
            }
          case .failure:
            // Failure
            resolver.reject(Error.loginFailed("Failure"))
          case .error(let error):
            // Error
            if let cause = error.underlyingError {
              if OnlineSubtitle.isConnectFailure(cause) {
                resolver.reject(OnlineSubtitle.CommonError.cannotConnect(cause))
                return
              }
              if OnlineSubtitle.isTimedOutFailure(cause) {
                resolver.reject(OnlineSubtitle.CommonError.timedOut(cause))
                return
              }
            }
            resolver.reject(Error.xmlRpcError(error))
          }
        }
      }
    }

    func hash(_ url: URL, _ isNetworkResource: Bool) -> Promise<FileInfo> {
      return Promise { resolver in
        guard !isNetworkResource else {
          // Cannot create a hash when streaming. Force caller to use title instead.
          resolver.reject(OnlineSubtitle.CommonError.noResult)
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

        resolver.fulfill(FileInfo(hashValue: String(format: "%016qx", hash), fileSize: fileSize))
      }
    }

    func requestByHashAndSize(_ info: FileInfo) -> Promise<[Subtitle]> {
      log("Searching for subtitles of movies matching hash \(info.hashValue) and size \(info.fileSize)")
      return self.request(info.dictionary)
    }

    func requestByName(_ fileURL: URL, _ isNetworkResource: Bool, _ mediaTitle: String) -> Promise<[Subtitle]> {
       return requestIMDB(fileURL, isNetworkResource, mediaTitle).then { imdb -> Promise<[Subtitle]> in        let info = ["imdbid": imdb]
        return self.request(info)
      }
    }

    func requestIMDB(_ fileURL: URL, _ isNetworkResource: Bool, _ mediaTitle: String) -> Promise<String> {
      return Promise { resolver in
        // When streaming use the media title as frequently the URL does not reflect the title
        // of the video.
        let searchString = isNetworkResource ? mediaTitle : fileURL.lastPathComponent
        log("Searching for subtitles of movies matching '\(searchString)'")
        xmlRpc.call("GuessMovieFromString", [token as Any, [searchString]]) { status in
          switch status {
          case .ok(let response):

            func parseResponse() throws -> String {
              let responsePath = ["data", searchString, "BestGuess"]
              guard let bestGuess = try self.findPath(responsePath, in: response) as? [String: Any] else {
                return ""
              }

              guard let imdbEntry = bestGuess["IMDBEpisode"] ?? bestGuess["IDMovieIMDB"] else {
                return ""
              }
              if let imdbEntry = imdbEntry as? Int {
                return String(imdbEntry)
              }
              return imdbEntry as? String ?? ""
            }

            do {
              guard self.checkStatus(response) else { throw Error.wrongResponseFormat }
              try resolver.fulfill(parseResponse())
            } catch let (error) {
              resolver.reject(error)
              return
            }
          case .failure:
            resolver.reject(Error.searchFailed("Failure"))
          case .error(let error):
            resolver.reject(Error.xmlRpcError(error))
          }
        }
      }
    }

    func request(_ info: [String: String]) -> Promise<[Subtitle]> {
      return Promise { resolver in
        let limit = 100
        var requestInfo = info
        requestInfo["sublanguageid"] = self.language
        xmlRpc.call("SearchSubtitles", [token as Any, [requestInfo], ["limit": limit]]) { status in
          switch status {
          case .ok(let response):
            guard self.checkStatus(response) else { resolver.reject(Error.wrongResponseFormat); return }
            guard let pData = try? self.findPath(["data"], in: response) as? ResponseFilesData else {
              resolver.reject(Error.wrongResponseFormat)
              return
            }
            var result: [Subtitle] = []
            for (index, subData) in pData.enumerated() {
              let sub = Subtitle(index: index,
                                 filename: subData["SubFileName"] as! String,
                                 langID: subData["SubLanguageID"] as! String,
                                 addDate: subData["SubAddDate"] as! String,
                                 rating: subData["SubRating"] as! String,
                                 dlCount: subData["SubDownloadsCnt"] as! String,
                                 subDlLink: subData["SubDownloadLink"] as! String)
              result.append(sub)
            }
            if result.isEmpty {
              resolver.reject(OnlineSubtitle.CommonError.noResult)
            } else {
              resolver.fulfill(result)
            }
          case .failure:
            // Failure
            resolver.reject(Error.searchFailed("Failure"))
          case .error(let error):
            // Error
            resolver.reject(Error.xmlRpcError(error))
          }
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

    private func startHeartbeat() {
      heartBeatTimer = Timer(timeInterval: heartbeatInterval, target: self, selector: #selector(sendHeartbeat), userInfo: nil, repeats: true)
    }

    @objc private func sendHeartbeat() {
      xmlRpc.call("NoOperation", [token as Any]) { result in
        switch result {
        case .ok(let value):
          // 406 No session
          if let pValue = value as? [String: Any], (pValue["status"] as? String ?? "").hasPrefix("406") {
            log("heartbeat: no session", level: .warning)
            self.token = nil
            self.login().catch { err in
              switch err {
              case Error.loginFailed(let reason):
                log("(re-login) \(reason)", level: .error)
              case Error.xmlRpcError(let error):
                log("(re-login) \(error.readableDescription)", level: .error)
              default:
                log("(re-login) \(err.localizedDescription)", level: .error)
              }
            }
          } else {
            log("OpenSub: heartbeat ok")
          }
        default:
          log("OpenSub: heartbeat failed", level: .error)
          self.token = nil
        }
      }
    }

    var loggedIn: Bool {
      return token != nil
    }
  }

  private static func log(_ message: String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: Logger.Sub.opensub)
  }
}

extension Logger.Sub {
  static let opensub = Logger.makeSubsystem("opensub")
}
