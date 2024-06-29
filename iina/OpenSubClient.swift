//
//  OpenSubClient.swift
//  iina
//
//  Created by low-batt on 8/30/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation
import Just
import PromiseKit

/// [Open Subtitles](https://www.opensubtitles.com/)
/// [REST API](https://opensubtitles.stoplight.io/docs/opensubtitles-api/e3750fd63a100-getting-started/)
/// client.
///
/// The [opensubtitles.org](https://www.opensubtitles.org/)
/// [XMLRPC](https://trac.opensubtitles.org/projects/opensubtitles/wiki/XMLRPC) API is shutting down at the
/// end of 2023 and being replaced by the [opensubtitles.com](https://www.opensubtitles.com/)
/// [REST API](https://opensubtitles.stoplight.io/docs/opensubtitles-api/e3750fd63a100-getting-started/).
/// Thus this is more than a switch from a XMLRPC API to a REST API, it also involves a migration from `opensubtitles.org` to
/// `opensubtitles.com`.  This is not transparent to users with an `opensubtitles.org` account.  The Open Subtitles FAQ
/// [How do I import my opensubtitles.org account?](https://www.opensubtitles.com/en/faq)
/// instructs users to:
///
/// Go to the [user import] (https://www.opensubtitles.com/users/import) page and fill in the email registered on
/// opensubtitles.org. You will receive an email inviting you set yourself a new password. Your previous uploads will be referenced, user
/// right such as VIP will be imported.
///
/// Open Subtitles was unable to automate migrating a user's account password, so they implemented a manual account import
/// process that requires a user to change their password. IINA needs to communicate the need to manually migrate accounts to users
/// in order to avoid reports that login is broken.
///
/// This class provides a _somewhat_ generic client for the Open Subtitles REST API. The intent is to have a clear separation between
/// the code required merely to call the REST API and code that guides how IINA uses the API. Therefore **developers must not**
/// add code that specifically deals with IINA concerns. This class should remain a "dumb client". IINA concerns should be handled at a
/// higher level. To avoid the work and additional complexity of a true generic client, this class is tied to IINA in a number of ways such
/// as:
/// - The HTTP [User-Agent](https://en.wikipedia.org/wiki/User-Agent_header) request header is hardcoded to IINA
/// - The HTTP [Api-Key](https://opensubtitles.stoplight.io/docs/opensubtitles-api/e3750fd63a100-getting-started#api-key)
/// request header is hardcoded to IINA's key
/// - Only the REST API methods used by IINA are supported
/// - Only the method features used by IINA are supported
/// - IINA's logger is used for debug logging
/// Intentionally not present is any support for higher level IINA operations, many of which involve multiple API calls. The purpose of this
/// client is to make it easier for the higher level code to call individual API methods.
class OpenSubClient {
  
  enum Error: Swift.Error {

    /// An error that indicates the REST API call failed.
    /// - Parameters:
    ///   - statuscode:
    ///     [HTTP status code](https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml).
    ///   - message: Description of the failure.
    case callFailed(statusCode: Int?, message: String? = nil)
    
    /// An error that indicates the client expected the  HTTP response to contain content, but none was found.
    /// - Parameter statuscode:
    ///   [HTTP status code](https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml).
    case contentMissing(statusCode: Int?)
    
    /// An error that indicates the REST API call failed, returning a JSON struct containing information about the faillure.
    /// - Parameter response: An `ErrorResponse` object containing information about the failure.
    case errorResponse(response: OpenSubClient.ErrorResponse)
  }

  /// The `OpenSubClient` singleton object.
  static let shared = OpenSubClient()

  /// `True` if currently logged in, `false` otherwise.
  ///
  /// This property reflects whether the client currently possesses a valid
  /// [JSON Web Token](https://en.wikipedia.org/wiki/JSON_Web_Token) returned by the
  /// [login](https://opensubtitles.stoplight.io/docs/opensubtitles-api/73acf79accc0a-login) method.
  ///
  /// - NOTE: In [Authorization JWT](https://opensubtitles.stoplight.io/docs/opensubtitles-api/e3750fd63a100-getting-started#authorization-jwt)
  /// Open Subtitles indicates a token is valid for 24 hours. The client keeps track of when the token was obtained and will consider the
  /// token expired before 24 hours is reached in order to reduce the chance of a request failing with a 406 `invalid token` error.
  var loggedIn: Bool {
    guard token != nil, let tokenExpiration = tokenExpiration else { return false }
    guard Date() < tokenExpiration else {
      log("User session has expired")
      abandonUserSession()
      return false
    }
    return true
  }

  // MARK: - Private Properties

  /// URL to prepend to a REST API method name to form the full URL of the API endpoint.
  ///
  /// - Important: As discussed in the documentation for the
  ///     [login](https://opensubtitles.stoplight.io/docs/opensubtitles-api/73acf79accc0a-login)
  ///     method Open Subtitles may direct the client to use a different host for further API requests.
  private var apiBaseURL: URL
  
  /// Hostname to initially use to access the REST API.
  private let apiDefaultHostname = "api.opensubtitles.com"

  /// Official IINA [Open Subtitles](https://www.opensubtitles.com/)
  /// [API key](https://opensubtitles.stoplight.io/docs/opensubtitles-api/e3750fd63a100-getting-started#api-key).
  ///
  /// The API key identifies the _application_ using the
  /// [REST API](https://opensubtitles.stoplight.io/docs/opensubtitles-api/e3750fd63a100-getting-started),
  /// not the  [Open Subtitles](https://www.opensubtitles.com/) user.
  private let apiKey = "SPX87dlUuuHpxeh5u3rd7dHekOT6oYpx"

  /// [JSON decoder](https://developer.apple.com/documentation/foundation/jsondecoder) properly configured
  /// to decode responses from API methods.
  ///
  /// - Note: Decoding dates requires a custom decoder because the
  /// [ISO8601DateFormatter](https://developer.apple.com/documentation/foundation/iso8601dateformatter)
  /// can only be configured to expect one specific format, but dates in the JSON responses from Open Subtitles sometimes contain
  /// fractional seconds, `2023-09-01T23:59:59.000Z` and sometimes not, `2023-05-15T21:54:32Z`.
  private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard #available(macOS 10.12, *) else {
      let iso8601 = DateFormatter()
      iso8601.calendar = Calendar(identifier: .iso8601)
      iso8601.locale = Locale(identifier: "en_US_POSIX")
      iso8601.timeZone = TimeZone(secondsFromGMT: 0)
      iso8601.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
      let iso8601WithFractionalSeconds = DateFormatter()
      iso8601WithFractionalSeconds.calendar = Calendar(identifier: .iso8601)
      iso8601WithFractionalSeconds.locale = Locale(identifier: "en_US_POSIX")
      iso8601WithFractionalSeconds.timeZone = TimeZone(secondsFromGMT: 0)
      iso8601WithFractionalSeconds.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSZ"
      decoder.dateDecodingStrategy = .custom({ (decoder) -> Date in
        let container = try decoder.singleValueContainer()
        let dateStr = try container.decode(String.self)
        if let date = iso8601.date(from: dateStr) {
          return date
        }
        if let date = iso8601WithFractionalSeconds.date(from: dateStr) {
          return date
        }
        throw DecodingError.dataCorruptedError(in: container,
                                               debugDescription: "Expected ISO 8601 date: \(dateStr)")
      })
      return decoder
    }
    let iso8601 = ISO8601DateFormatter()
    let iso8601WithFractionalSeconds = ISO8601DateFormatter()
    iso8601WithFractionalSeconds.formatOptions = [.withFractionalSeconds]
    decoder.dateDecodingStrategy = .custom({ (decoder) -> Date in
      let container = try decoder.singleValueContainer()
      let dateStr = try container.decode(String.self)
      if let date = iso8601.date(from: dateStr) {
        return date
      }
      if let date = iso8601WithFractionalSeconds.date(from: dateStr) {
        return date
      }
      throw DecodingError.dataCorruptedError(in: container,
                                             debugDescription: "Expected ISO 8601 date: \(dateStr)")
    })
    return decoder
  }()

  /// Management of API request
  /// [rate limits](https://opensubtitles.stoplight.io/docs/opensubtitles-api/6ef2e232095c7-best-practices#limits)
  /// imposed on clients by Open Subtitles.
  private var rateLimiter = RateLimiter()

  /// Authorization [JSON Web Token](https://en.wikipedia.org/wiki/JSON_Web_Token) returned by the
  /// [login](https://opensubtitles.stoplight.io/docs/opensubtitles-api/73acf79accc0a-login) method.
  ///
  /// Authentication is discussed in [Getting Started](https://opensubtitles.stoplight.io/docs/opensubtitles-api/e3750fd63a100-getting-started#authorization-jwt)
  private var token: String?

  /// Time when the JWT will be considered expired by the client.
  private var tokenExpiration: Date?

  /// Length of time a JWT is considered valid.
  ///
  /// As documented in
  /// [Authorization JWT](https://opensubtitles.stoplight.io/docs/opensubtitles-api/e3750fd63a100-getting-started#authorization-jwt)
  /// `Open Subtitles` expires logged in user sessions after 24 hours. To reduce the chance of a request failing due to an expired
  /// token the client considers the token expired after 23 hours.
  private let tokenLifetime: TimeInterval = 23 * 60 * 60

  /// Value to send in the HTTP [User-Agent](https://en.wikipedia.org/wiki/User-Agent_header) request header.
  ///
  /// The value is formatted as specified in
  /// [Important-HTTP Request Headers](https://opensubtitles.stoplight.io/docs/opensubtitles-api/e3750fd63a100-getting-started#important-http-request-headers).
  private let userAgent: String = {
    let (version, build) = InfoDictionary.shared.version
    return "IINA v\(version)"
  }()

  // MARK: - REST API Methods
  
  /// [Download](https://opensubtitles.stoplight.io/docs/opensubtitles-api/6be7f6ae2d918-download) method.
  ///
  /// This method _does not_ download the subtitle file. It requests that a temporary URL be generated from which the subtitle file
  /// contents can be downloaded. As discussed in
  /// [Getting started](https://opensubtitles.stoplight.io/docs/opensubtitles-api/e3750fd63a100-getting-started)
  /// this is the method that Open Subtitles uses to enforce limits on use of their service. The download quota imposed depends up
  /// whether a user is authenticated or not and their rank. If the quota is exceeded this method will fail with a 406 (not acceptable)
  /// status code as explained in
  /// [Error codes](https://opensubtitles.stoplight.io/docs/opensubtitles-api/12f131ce12132-error-codes).
  /// - Parameter fileId: File ID of the subtitle file to download (obtained from search results).
  /// - Returns: A `DownloadResponse` containing a temporary link to the subtitle file and information such as requests
  ///            remaining before download quota is reached.
  func download(fileId: Int) -> Promise<DownloadResponse> {
    return after(seconds: rateLimiter.delayBeforeCall()).then { [self] in
      Promise { resolver in
        let data = ["file_id": String(fileId)]
        let url = apiURL("download")
        Just.post(url, data: data, headers: formHeaders(), asyncCompletionHandler: { [self] result in
          logHTTPResult(result)
          do {
            let response = try decodeResponse(DownloadResponse.self, from: result)
            resolver.fulfill(response)
          } catch {
            resolver.reject(error)
          }
        })
      }
    }
  }

  /// Download the contents of a subtitle file.
  ///
  /// This is an accompanying endpoint for the
  /// [Download](https://opensubtitles.stoplight.io/docs/opensubtitles-api/6be7f6ae2d918-download)
  /// method. That method does not return the subtitle file contents. Instead it returns a link that can then be used with this endpoint to
  /// download the file contents.
  /// - Parameter url: Link to subtitle file contents returned by the `Download` method.
  /// - Returns: A [Data](https://developer.apple.com/documentation/foundation/data) object containing the
  ///            file contents
  func downloadFileContents(_ url: URL) -> Promise<Data> {
    return after(seconds: rateLimiter.delayBeforeCall()).then { [self] in
      Promise { resolver in
        Just.get(url, headers: formHeaders(), asyncCompletionHandler: { [self] result in
          logHTTPResult(result)
          if let error = result.error {
            resolver.reject(error)
            return
          }
          guard result.ok else {
            // When downloading fails, Open Subtitles normally returns an error message as the
            // response content. As this is not a part of the REST API, the contents is not JSON.
            guard let text = result.text else {
              // No error message, generate a message based on HTTP status code.
              resolver.reject(Error.callFailed(statusCode: result.statusCode))
              return
            }
            // Sometimes the response content is a HTML error page instead of a simple text message.
            if let error = formErrorIfHtmlResponse(result) {
              resolver.reject(error)
              return
            }
            resolver.reject(Error.callFailed(statusCode: result.statusCode, message: text))
            return
          }
          guard let content = result.content else {
            resolver.reject(Error.contentMissing(statusCode: result.statusCode))
            return
          }
          resolver.fulfill(content)
        })
      }
    }
  }

  /// [Languages](https://opensubtitles.stoplight.io/docs/opensubtitles-api/1de776d20e873-languages)
  /// method.
  /// - Returns: A `LanguagesResponse` containing a list of the supported lanuage codes.
  func languages() -> Promise<LanguagesResponse> {
    return after(seconds: rateLimiter.delayBeforeCall()).then { [self] in
      Promise { resolver in
        let url = apiURL("infos/languages")
        Just.get(url, headers: formHeaders(), asyncCompletionHandler: { [self] result in
          logHTTPResult(result)
          do {
            let response = try self.decodeResponse(LanguagesResponse.self, from: result)
            resolver.fulfill(response)
          } catch {
            resolver.reject(error)
          }
        })
      }
    }
  }

  /// [Login](https://opensubtitles.stoplight.io/docs/opensubtitles-api/73acf79accc0a-login) method.
  ///
  /// This method is used to log into [Open Subtitles](https://www.opensubtitles.com/en). A successful login returns a
  /// [JSON Web Token](https://en.wikipedia.org/wiki/JSON_Web_Token) that is then passed in an `Authorization`
  /// header in further requests. Based on account privileges Open Subtitles may redirect the client to use a different hostname for the
  /// REST API endpoints in further requests.
  /// - Important: The given username and password _must_ be for an `opensubtitles.com` account., not an
  ///     `opensubtitles.org` account. Users with an `opensubtitles.org` account must
  ///     [import] (https://www.opensubtitles.com/users/import) it  into `opensubtitles.com` before the
  ///     account can be used.
  /// - Note: Open Subtitles documents that for the login method there is set limit 1 request per 1 second to avoid flooding with
  ///     wrong credentials. This means the rate limit response headers returned instruct the client to wait before sending another
  ///     request. However this only applies if the client is making another request to the login method. This is referred to as the
  ///     "throttling scope" in the
  ///     [RateLimit header fields for HTTP](https://www.ietf.org/archive/id/draft-ietf-httpapi-ratelimit-headers-07.html)
  ///     Internet Draft. Unfortunately at this time the draft does not define a standard header for specifying scope. This means the
  ///     `RateLimiter`class has no understanding of scope. As a workaround the rate limiter is recreated if login is successful to
  ///     avoid delaying the next API call.
  /// - Parameters:
  ///   - username: Account username.
  ///   - password: Account password.
  /// - Returns: account details.
  func login(username: String, password: String) -> Promise<LoginResponse> {
    return after(seconds: rateLimiter.delayBeforeCall()).then { [self] in
      Promise { resolver in
        let data = ["username": username, "password": password]
        let url = apiURL("login")
        Just.post(url, data: data, headers: formHeaders(), asyncCompletionHandler: { [self] result in
          logHTTPResult(result)
          do {
            let response = try self.decodeResponse(LoginResponse.self, from: result)
            resolver.fulfill(response)
            // Use a fresh rate limiter to avoid delaying the next request.
            rateLimiter = RateLimiter()
            token = response.token
            tokenExpiration = Date() + tokenLifetime
            // Open Subtitles may direct the client to use a different host for further requests.
            guard let hostname = response.baseUrl else {
              return
            }
            guard let baseURL = OpenSubClient.formBaseURL(hostname: hostname) else {
              // Should not occur. Malformed data returned by Open Subtitles? As login was
              // apparently successful we will treat this as a warning.
              log("Unable to form URL from: \(hostname)", level: .warning)
              return
            }
            apiBaseURL = baseURL
          } catch {
            resolver.reject(error)
          }
        })
      }
    }
  }

  /// [Logout](https://opensubtitles.stoplight.io/docs/opensubtitles-api/9fe4d6d078e50-logout) method.
  /// - Parameter timeout: The timeout to to use for the the request.
  /// - Returns: A `LogoutResponse`
  func logout(timeout: TimeInterval? = nil) -> Promise<LogoutResponse> {
    return after(seconds: rateLimiter.delayBeforeCall()).then { [self] in
      Promise { resolver in
        let headers = formHeaders()
        let url = apiURL("logout")
        Just.delete(url, headers: headers, timeout: timeout, asyncCompletionHandler: { [self] result in
          logHTTPResult(result)
          // Whether or not the logout request was successful consider the user as having logged out.
          abandonUserSession()
          do {
            let response = try self.decodeResponse(LogoutResponse.self, from: result)
            resolver.fulfill(response)
          } catch {
            resolver.reject(error)
          }
        })
      }
    }
  }

  /// [Subtitles](https://opensubtitles.stoplight.io/docs/opensubtitles-api/a172317bd5ccc-search-for-subtitles)
  /// method.
  ///
  /// Find available subtitles matching the query and
  /// [hash code](https://trac.opensubtitles.org/projects/opensubtitles/wiki/HashSourceCodes)
  /// (if available) in the given languages.
  /// - Note: This method does not adhere to the recommended REST API
  ///         [Best Practice](https://opensubtitles.stoplight.io/docs/opensubtitles-api/6ef2e232095c7-best-practices#performance)
  ///         of sending parameters in alphabetical order because the `Just` parameter is an unordered Swift dictionary.
  /// - Note: This method does not adhere to the recommended REST API
  ///         [Best Practice](https://opensubtitles.stoplight.io/docs/opensubtitles-api/6ef2e232095c7-best-practices#performance)
  ///         of using "+" instead "%20" for space in the URL encoding because `Just` does not provide a way to control the
  ///         percent encoding.
  /// - Parameters:
  ///   - languages: Language code(s).
  ///   - hash: Moviehash of the movie file.
  ///   - query:File name or text search.
  /// - Returns: A `SubtitlesResponse` object.
  func subtitles(languages: [String], hash: String?, query: String?) -> Promise<SubtitlesResponse> {
    return after(seconds: rateLimiter.delayBeforeCall()).then { [self] in
      Promise { resolver in
        // As per REST API best practices, attempt to send GET parameters in alphabetical order.
        // Unfortunately, Just.get takes a Swift dictionary therefore order is not guaranteed.
        var params = ["languages": languages.sorted().joined(separator: ",")]
        if let hash = hash {
          params["moviehash"] = hash
        }
        if let query = query {
          params["query"] = query
        }
        let url = apiURL("subtitles")
        Just.get(url, params: params, headers: formHeaders(), asyncCompletionHandler: { [self] result in
          logHTTPResult(result)
          do {
            let response = try self.decodeResponse(SubtitlesResponse.self, from: result)
            resolver.fulfill(response)
          } catch {
            resolver.reject(error)
          }
        })
      }
    }
  }

  // MARK: - Supporting Methods

  /// Abandons the current the user session.
  ///
  /// The [JSON Web Token](https://en.wikipedia.org/wiki/JSON_Web_Token) is discarded. The host to use for API
  /// requests is reset to the default Open Subtitles REST API server.
  private func abandonUserSession() {
    apiBaseURL = OpenSubClient.formBaseURL(hostname: apiDefaultHostname)!
    token = nil
    tokenExpiration = nil
  }

  /// Returns the REST API endpoint for the given method.
  /// - Parameter method: Name of the REST API method.
  /// - Returns: `URL` to send the request to.
  private func apiURL(_ method: String) -> URL { URL(string: method, relativeTo: apiBaseURL)! }

  /// Decode the result of a REST API call into a `Response` object.
  /// - Parameters:
  ///   - type: Type of `Response` to decode the response into.
  ///   - result: `HTTPResult` returned by [Just](https://github.com/dduan/Just).
  /// - Returns: Response JSON decoded into a `Response` object.
  private func decodeResponse<T>(_ type: T.Type, from result: HTTPResult) throws -> T where T : Response {
    if !result.headers.isEmpty {
      rateLimiter.processRateLimitHeaders(result.headers)
    }
    if let error = result.error {
      throw error
    }
    guard result.ok else {
      guard let content = result.content else {
        throw Error.callFailed(statusCode: result.statusCode, message: result.reason)
      }
      // Sometimes the response content is a HTML error page instead of JSON.
      if let error = formErrorIfHtmlResponse(result) {
        throw error
      }
      do {
        let response = try self.decoder.decode(ErrorResponse.self, from: content)
        guard let statusCode = result.statusCode, statusCode == 406,
              response.message == "invalid token" else {
          throw Error.errorResponse(response: response)
        }
        // The REST API returns a 406 (Not Acceptable) HTTP status code with an "invalid token"
        // error message if the server determined the JSON web token representing the user session
        // has expired. The client keeps track of when the token was acquired and attempts to reduce
        // the chance of this error occurring, however the client must still be prepared to handle
        // the case where the server rejects the token.
        log("User session is no longer valid")
        abandonUserSession()
        throw Error.errorResponse(response: response)
      } catch {
        guard let text = result.text else {
          throw error
        }
        log("Decoding JSON as \(String(describing: ErrorResponse.self)) failed: \(text) error thrown: \(error)", level: .error)
        throw error
      }
    }
    guard let content = result.content else {
      throw Error.contentMissing(statusCode: result.statusCode)
    }
    do {
      return try self.decoder.decode(type, from: content)
    } catch {
      guard let text = result.text else {
        throw error
      }
      log("Decoding JSON as \(String(describing: type)) failed: \(text) error thrown: \(error)", level: .error)
      throw error
    }
  }

  /// Form the base URL to append a REST API method to.
  ///
  /// The server to send REST API requests to is not a constant. The response to a login request may instruct the client to send further
  /// API requests to a different host.
  /// - Parameter hostname: Host to send REST API requests to.
  /// - Returns: Base `URL` to append a method name to.
  private static func formBaseURL(hostname: String) -> URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = hostname
    components.path = "/api/v1/"
    return components.url
  }

  /// Form an error if the given API response content is HTML.
  ///
  /// Normally when an API request fails the content of the response returned by Open Subtitles is a JSON `ErrorResponse`
  /// structure. However for certain types of failures the response content returned is a HTML error page. If the content is HTML the
  /// title is extracted and a `callFailed` error is constructed using the title as the error message.
  /// - Parameter result: `HTTPResult` returned by [Just](https://github.com/dduan/Just).
  /// - Returns: A `callFailed` error or `nil`
  private func formErrorIfHtmlResponse(_ result: HTTPResult) -> Error? {
    guard let contentHeader = result.headers["Content-Type"], contentHeader.contains("text/html"),
          let text = result.text else {
      return nil
    }
    log("Found HTML instead of JSON:\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))")
    guard let start = text.range(of: "<title>"), let end = text.range(of: "</title>"),
          start.upperBound < end.lowerBound else {
      // Not expected to occur. All error pages seen in testing included a title.
      return Error.callFailed(statusCode: result.statusCode, message: "HTML returned instead of JSON")
    }
    var message = String(text[start.upperBound..<end.lowerBound])
    if let statusCode = result.statusCode {
      let prefix = "\(statusCode) "
      if message.hasPrefix(prefix) {
        message = String(message.dropFirst(prefix.count))
      }
    }
    return Error.callFailed(statusCode: result.statusCode, message: message)
  }

  /// Form a dictionary containing the common headers sent in every request.
  ///
  /// These are the headers shown in the [Getting Started](https://opensubtitles.stoplight.io/docs/opensubtitles-api/e3750fd63a100-getting-started)
  /// section of the REST API documentation.
  /// - Returns: Dictionary containing the headers.
  private func formHeaders() -> [String: String] {
    var headers = ["Accept": "*/*", "Api-Key": String(apiKey.reversed()),
                   "Content-Type": "application/json", "User-Agent": userAgent]
    guard let token = token else { return headers }
    headers["Authorization"] = "Bearer \(token)"
    return headers
  }

  private func log(_ message: String, level: Logger.Level = .debug) {
    Logger.log(message, level: level, subsystem: Logger.Sub.opensubapi)
  }

  /// Log details about the result of calling a REST API.
  ///
  /// Both the request and the response are logged in detail. For debugging it is important to log the details of the response as the
  /// result returned by Open Subtitles is sometimes not matching up with the REST API documentation.
  /// - Important: This method redacts sensitive authentication and authorization data replacing it with `<private>`.
  /// - Parameter result: `HTTPResult` returned by [Just](https://github.com/dduan/Just).
  private func logHTTPResult(_ result: HTTPResult) {
    let options: JSONSerialization.WritingOptions = [.prettyPrinted]
    let privateValue = "<private>"
    if let request = result.request {
      var requestJson: [String: Any] = [:]
      if let httpMethod = request.httpMethod {
        requestJson["httpMethod"] = httpMethod
      }
      if let url = request.url {
        requestJson["url"] = url.absoluteString
      }
      if var headers = request.allHTTPHeaderFields, !headers.isEmpty {
        if headers["Api-Key"] != nil {
          headers["Api-Key"] = privateValue
        }
        if headers["Authorization"] != nil {
          headers["Authorization"] = privateValue
        }
        requestJson["headers"] = headers
      }
      if let data = request.httpBody, var body = try? JSONSerialization.jsonObject(with: data) as? [String:Any] {
        if body["username"] != nil {
          body["username"] = privateValue
        }
        if body["password"] != nil {
          body["password"] = privateValue
        }
        requestJson["body"] = body
      }
      if let data = try? JSONSerialization.data(withJSONObject: requestJson, options: options),
         let pretty = String(data: data, encoding: .utf8) {
        log("Request: \(pretty)")
      }
    }
    if let status = result.statusCode {
      log("HTTP response status code: \(status) \(result.reason)")
    }
    if let error = result.error {
      log("Error: \(error)")
    }
    guard var resultJson = result.json as? [String: Any] else {
      if !result.headers.isEmpty {
        var message = ""
        for (header, value) in result.headers {
          if !message.isEmpty {
            message += "\n"
          }
          message += "\(header): \(value)"
        }
        log("HTTP response headers:\n" + message)
      }
      return
    }
    if !result.headers.isEmpty {
      var dict: [String: String] = [:]
      for (key, value) in result.headers {
        dict[key] = value
      }
      resultJson["headers"] = dict
    }
    if resultJson["token"] != nil {
      resultJson["token"] = privateValue
    }
    if let data = try? JSONSerialization.data(withJSONObject: resultJson, options: options),
       let pretty = String(data: data, encoding: .utf8) {
      log("Response: \(pretty)")
    }
  }
  
  private init() {
    apiBaseURL = OpenSubClient.formBaseURL(hostname: apiDefaultHostname)!
  }

  // MARK: - Rate Limiter

  /// REST API call rate limiter.
  ///
  /// This class is used to detect when the client _must_ wait before sending a REST API request in order to adhere to the request rate
  /// limits imposed by Open Subtitles on clients. The limits currently imposed by Open Subtitles normally do not require IINA to wait
  /// before sending a request. Possibly selecting many subtitles to download could run fast enough to require a delay, but only if the
  /// subtitle files are tiny and the Open Subtitles servers are responding quickly. _However_  in response to overloaded servers Open
  /// Subtitles could lower the rate limits, thus clients _must_ obey the limits returned in responses from the server.
  ///
  /// Rate limits are discussed in the Open Subtitles REST API documentation in the
  /// [Best Practices](https://opensubtitles.stoplight.io/docs/opensubtitles-api/6ef2e232095c7-best-practices)
  /// section which says:
  ///
  /// API requests are rate limited **5 requests per 1 second** per IP address. It means your client should follow the limits,
  /// otherwise it will receive HTTP error:
  ///
  /// _429 Too Many Requests_
  ///
  /// The documentation goes on to say:
  ///
  /// On `/login` there is set limit 1 request per 1 second to avoid flooding with wrong credentials. Stop sending requests with same
  /// credentials if user fail to authenticate.
  ///
  /// The [Important HTTP response headers](https://opensubtitles.stoplight.io/docs/opensubtitles-api/e3750fd63a100-getting-started#important-http-response-headers)
  /// section contains a link to [Rate Limiting | Kong Docs](https://docs.konghq.com/hub/kong-inc/rate-limiting/).
  /// The Kong documentation contains this example of response headers:
  /// ```text
  /// RateLimit-Limit: 6
  /// RateLimit-Remaining: 4
  /// RateLimit-Reset: 47
  /// ```
  /// And indicates these headers are based on the Internet-Draft [RateLimit header fields for HTTP](https://datatracker.ietf.org/doc/draft-ietf-httpapi-ratelimit-headers/).
  class RateLimiter {

    /// Number of requests remaining in the quota for the current window.
    private var remaining = Int.max

    /// Time at which the current window ends and the quota resets .
    private var resets: TimeInterval = 0

    /// Returns the time to wait before sending a request.
    ///
    /// If the current time is outside of the window for which the quota in `remaining` is applicable then zero is returned. Otherwise
    /// the remaining quota is decremented and if the quota has not been exceeded then zero is returned. When the quota would be
    /// exceeded the time remaining until the current window ends and the quota resets is calculated and returned.
    /// - Returns: Time to wait in seconds.
    func delayBeforeCall() -> TimeInterval {
      // No delay needed if the current time is outside of the window for which the quota given in
      // remaining is applicable.
      let now = Date().timeIntervalSince1970
      guard resets > now else { return 0 }
      remaining -= 1
      // No delay needed if quota has not been exceeded.
      guard remaining < 0 else { return 0 }
      // Must wait until outside the current window and the quota resets.
      let delay = (resets - now).rounded(.up)
      let delayAsString = String(format: "%.f", delay)
      shared.log("Rate limit quota reached, waiting \(delayAsString)s before sending request")
      return delay
    }

    /// Process rate limit headers if present in the response headers.
    /// - Parameter headers: Response headers returned by the server.
    func processRateLimitHeaders(_ headers: CaseInsensitiveDictionary<String, String>) {
      // Up to the server as to whether it sends rate limit headers in the response.
      guard let remainingString = headers["ratelimit-remaining"],
            let resetString = headers["ratelimit-reset"] else {
        return
      }
      // Have headers, parse and validate their values.
      guard let remaining = Int(remainingString), remaining >= 0, let reset = Int(resetString),
            reset >= 0 else {
        // The draft RFC specifies that the values of these header fields are non-negative Integers
        // and that "Malformed RateLimit header fields MUST be ignored". Log a warning as this
        // should not occur and pretend no headers were received.
        shared.log("Malformed rate limits: \(remainingString), \(resetString)", level: .warning)
        return
      }
      // Save the time at which current window ends and the quota resets.
      resets = Date().timeIntervalSince1970 + Double(reset)
      self.remaining = remaining
    }
  }

  // MARK: - Response Models

  /// Response returned by the
  /// [Download](https://opensubtitles.stoplight.io/docs/opensubtitles-api/6be7f6ae2d918-download) method.
  struct DownloadResponse: Response {
    var fileName: String
    var link: URL
    var message: String
    var remaining: Int
    var requests: Int
    var resetTime: String
    var resetTimeUtc: Date
  }

  struct ErrorResponse: Response {
    var message: String
    var remaining: Int?
    var requests: Int?
    var resetTime: String?
    var resetTimeUtc: Date?
  }

  /// Part of the response returned by the
  /// [Languages](https://opensubtitles.stoplight.io/docs/opensubtitles-api/1de776d20e873-languages)
  /// method.
  struct LanguageCode: Decodable {
    var languageCode: String
    var languageName: String
  }

  /// Response returned by the
  /// [Languages](https://opensubtitles.stoplight.io/docs/opensubtitles-api/1de776d20e873-languages)
  /// method.
  struct LanguagesResponse: Response {
    var data: [LanguageCode]
  }

  /// Response returned by the
  /// [Login](https://opensubtitles.stoplight.io/docs/opensubtitles-api/73acf79accc0a-login) method.
  struct LoginResponse: Response {
    var baseUrl: String?
    var status: Int
    var token: String
    var user: User
  }

  /// Response returned by the
  /// [Logout](https://opensubtitles.stoplight.io/docs/opensubtitles-api/9fe4d6d078e50-logout) method.
  struct LogoutResponse: Response {
    var message: String
    var status: Int
  }

  /// Response returned by the
  /// [Subtitles](https://opensubtitles.stoplight.io/docs/opensubtitles-api/a172317bd5ccc-search-for-subtitles
  /// method.
  struct SubtitlesResponse: Response {
    var data: [Subtitle]
    var page: Int
    var perPage: Int
    var totalCount: Int
    var totalPages: Int
  }

  /// Part of the response returned by the
  /// [Login](https://opensubtitles.stoplight.io/docs/opensubtitles-api/73acf79accc0a-login) method.
  struct User: Decodable {
    var allowedDownloads: Int
    var allowedTranslations: Int
    var extInstalled: Bool
    var level: String
    var userId: Int
    var vip: Bool
  }

  // MARK: - Subtitle Models

  /// [Subtitle](https://opensubtitles.stoplight.io/docs/opensubtitles-api/573f76acc1493-subtitle) model.
  ///
  /// Structure modeling the JSON returned by the
  /// [Subtitles](https://opensubtitles.stoplight.io/docs/opensubtitles-api/a172317bd5ccc-search-for-subtitles)
  /// method representing a subtitle file.
  /// - Important: The above referenced documentation has proven to be unreliable. Testing has encountered properties that are
  /// documented as `required` but are being returned with `null` values in responses from Open Subtitles. This is unfortunate
  /// because returning `null` will trigger a [DecodingError](https://developer.apple.com/documentation/swift/decodingerror)
  /// unless an optional type is used for the property.  Many properties use optional types because we are unsure which ones can be
  /// depended upon to always be present.
  /// - Note: Properties not used by IINA at this time are not included in the release build to avoid the need to decode their values.
  struct Subtitle: Decodable {

    var attributes: SubtitleAttributes
    var id: String
    var type: String

    struct SubtitleAttributes: Decodable {
#if DEBUG
      var aiTranslated: Bool?
      var comments: String?
#endif
      var downloadCount: Int
      var featureDetails: SubtitleFeatureDetails
      var files: [SubtitleFile]
#if DEBUG
      var foreignPartsOnly: Bool?
#endif
      var fps: Double?
#if DEBUG
      var fromTrusted: Bool?
      var hd: Bool?
      var hearingImpaired: Bool?
#endif
      var language: String
#if DEBUG
      var legacySubtitleId: Int?
      var machineTranslated: Bool?
      var newDownloadCount: Int?
      var points: Int?
#endif
      var ratings: Double
#if DEBUG
      var relatedLinks: [SubtitleRelatedLinks]?
      var release: String?
      var subtitleId: String?
#endif
      var uploadDate: Date
#if DEBUG
      var uploader: SubtitleUploader
      var url: URL?
      var votes: Int?
#endif

      /// Model containing details about the media the subtitles are for.
      ///
      /// This JSON structure is dynamically typed. The value of the `featureType` property determines which of the following
      /// structures the object represents:
      /// - [Feature-Episode](https://opensubtitles.stoplight.io/docs/opensubtitles-api/06192f1ad8378-feature-episode)
      /// - [Feature-Movie](https://opensubtitles.stoplight.io/docs/opensubtitles-api/eb1e524fb59d6-feature-movie)
      /// - [Feature-Tvshow](https://opensubtitles.stoplight.io/docs/opensubtitles-api/b771c5ae51786-feature-tvshow)
      ///
      /// To properly decode dynamically typed JSON requires using something like the
      /// [DynamicCodableKit](https://swiftylab.github.io/DynamicCodableKit/documentation/dynamiccodablekit/)
      /// framework. As IINA is not making use of the information in these structures, only the common properties are modeled.
      struct SubtitleFeatureDetails: Decodable {
        var featureId: Int
        var featureType: String?
        var imdbId: Int?
        var title: String
        var tmdbId: Int?
        var year: Int?
      }

      struct SubtitleFile: Decodable {
#if DEBUG
        var cdNumber: Int?
#endif
        var fileId: Int
        var fileName: String
      }

      struct SubtitleRelatedLinks: Decodable {
        var imgUrl: URL?
        var label: String?
        var url: URL?
      }
      
      struct SubtitleUploader: Decodable {
        var name: String
        var rank: String?
        var uploaderId: Int?
      }
    }
  }
}

protocol Response: Decodable {}

extension OpenSubClient.Error: CustomStringConvertible, LocalizedError {
  var description: String {
    switch self {
    case .callFailed(let statusCode, let message):
      guard let message = message else {
        guard let statusCode = statusCode else {
          return String(describing: type(of: self))
        }
        return statusCodeAsString(statusCode)
      }
      guard let statusCode = statusCode else { return message }
      return message + " (\(statusCodeAsString(statusCode)))"
    case.contentMissing(let statusCode):
      let message = "Response content is missing"
      guard let statusCode = statusCode else { return message }
      return message + " (\(statusCodeAsString(statusCode)))"
    case .errorResponse(let response):
      return response.message
    }
  }
  
  var errorDescription: String? { description }

  private func statusCodeAsString(_ statusCode: Int) -> String {
    "\(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode))"
  }
}

extension Logger.Sub {
  static let opensubapi = Logger.makeSubsystem("opensubapi")
}
