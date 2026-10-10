// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import Foundation
import Security

struct SubtitleCredentials: Codable, Equatable {
    var apiKey = ""
    var username = ""
    var password = ""
    var userAgent = "IINAPad v0.3.0"
    var canSearch: Bool { !apiKey.isEmpty && !userAgent.isEmpty }
    var canDownload: Bool { canSearch && !username.isEmpty && !password.isEmpty }
}

enum SubtitleServiceError: LocalizedError {
    case setup, loginRequired, invalidResponse, invalidDownload, http(Int), keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .setup: return "Set up your OpenSubtitles.com API key and registered application name first."
        case .loginRequired: return "Enter your OpenSubtitles.com username and password in Account to download subtitles."
        case .invalidResponse: return "OpenSubtitles returned an incomplete response. Please try again."
        case .invalidDownload: return "The download was not a valid subtitle file, or exceeded 10 MB."
        case let .http(status):
            switch status {
            case 401: return "OpenSubtitles authentication failed. Check your API key and account details."
            case 403: return "OpenSubtitles denied this request. Check your account permissions or download allowance."
            case 406: return "Your OpenSubtitles download allowance is exhausted. Try again after it resets."
            case 429: return "OpenSubtitles is limiting requests. Please wait before trying again."
            default: return "OpenSubtitles request failed (HTTP \(status)). Please try again."
            }
        case let .keychain(status): return "Unable to access the subtitle account in Keychain (\(status))."
        }
    }
}

enum SubtitleAccountStore {
    private static let identity: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.local.iinapad.opensubtitles",
        kSecAttrAccount as String: "account"
    ]

    static func load() throws -> SubtitleCredentials {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return SubtitleCredentials() }
        guard status == errSecSuccess else { throw SubtitleServiceError.keychain(status) }
        guard let data = result as? Data else { throw SubtitleServiceError.invalidResponse }
        return try JSONDecoder().decode(SubtitleCredentials.self, from: data)
    }

    static func save(_ credentials: SubtitleCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let values: [String: Any] = [kSecValueData as String: data,
                                   kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(identity as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(identity.merging(values) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SubtitleServiceError.keychain(status) }
    }

    static func remove() throws {
        let status = SecItemDelete(identity as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SubtitleServiceError.keychain(status) }
    }
}

struct OnlineSubtitle: Identifiable, Equatable {
    let id: Int64
    let name: String
    let language: String
    let downloads: Int
    let hearingImpaired: Bool
}

struct SubtitleSearchPage {
    let results: [OnlineSubtitle]
    let page: Int
    let totalPages: Int
}

struct SubtitleDownload {
    let url: URL
    let remaining: Int?
    let resetTime: String?
}

/// Restrict redirects before URLSession can forward credential-bearing headers.
private final class SubtitleRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, OpenSubtitlesClient.isProviderURL(url),
              task.originalRequest?.value(forHTTPHeaderField: "Api-Key") == nil || OpenSubtitlesClient.isAPIURL(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

actor OpenSubtitlesClient {
    typealias Fetch = (URLRequest) async throws -> (Data, URLResponse)
    private let fetch: Fetch
    private let credentials: SubtitleCredentials
    private var token: String?
    private var tokenDate = Date.distantPast
    private var baseURL = URL(string: "https://api.opensubtitles.com/api/v1")!
    private let destination: URL

    init(credentials: SubtitleCredentials, destination: URL? = nil, fetch: Fetch? = nil) {
        self.credentials = credentials
        self.destination = destination ?? URL.documentsDirectory.appending(path: "Subtitles", directoryHint: .isDirectory)
        if let fetch { self.fetch = fetch }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 60
            let session = URLSession(configuration: config, delegate: SubtitleRedirectPolicy(), delegateQueue: nil)
            self.fetch = { request in try await session.data(for: request) }
        }
    }

    nonisolated static func isAPIURL(_ url: URL) -> Bool {
        url.scheme == "https" && ["api.opensubtitles.com", "vip-api.opensubtitles.com"].contains(url.host?.lowercased() ?? "")
        && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    nonisolated static func isProviderURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(), url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        return ["opensubtitles.com", "opensubtitles.org"].contains { host == $0 || host.hasSuffix("." + $0) }
    }

    func search(query: String, language: String, page: Int = 1) async throws -> SubtitleSearchPage {
        guard credentials.canSearch else { throw SubtitleServiceError.setup }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SubtitleServiceError.invalidResponse }
        var parameters = [URLQueryItem(name: "query", value: trimmed), URLQueryItem(name: "page", value: String(page)),
                          URLQueryItem(name: "order_by", value: "download_count"), URLQueryItem(name: "order_direction", value: "desc")]
        if !language.isEmpty { parameters.append(URLQueryItem(name: "languages", value: language)) }
        var components = URLComponents(url: baseURL.appending(path: "subtitles"), resolvingAgainstBaseURL: false)!
        components.queryItems = parameters.sorted { $0.name < $1.name }
        let response: SearchResponse = try await api(request(components.url!))
        let results = response.data.flatMap { item in
            item.attributes.files.map { file in
                OnlineSubtitle(id: file.file_id, name: item.attributes.release ?? file.file_name ?? "Subtitle",
                               language: item.attributes.language, downloads: item.attributes.download_count ?? 0,
                               hearingImpaired: item.attributes.hearing_impaired ?? false)
            }
        }
        return SubtitleSearchPage(results: results, page: response.page ?? page, totalPages: response.total_pages ?? page)
    }

    func download(_ subtitle: OnlineSubtitle) async throws -> SubtitleDownload {
        guard credentials.canDownload else { throw SubtitleServiceError.loginRequired }
        if token == nil || Date().timeIntervalSince(tokenDate) > 23 * 3600 { try await login() }
        var request = request(baseURL.appending(path: "download"), method: "POST")
        request.httpBody = try JSONEncoder().encode(DownloadRequest(file_id: subtitle.id, sub_format: "srt"))
        let response: DownloadResponse
        do { response = try await api(request) }
        catch SubtitleServiceError.http(401) {
            token = nil
            throw SubtitleServiceError.http(401)
        }
        guard let link = URL(string: response.link), Self.isProviderURL(link) else { throw SubtitleServiceError.invalidDownload }
        // No API key, username, password, or bearer token is sent to the file CDN.
        var fileRequest = URLRequest(url: link)
        fileRequest.setValue(credentials.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, rawResponse) = try await fetch(fileRequest)
        try Task.checkCancellation()
        guard let http = rawResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SubtitleServiceError.http((rawResponse as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard data.count <= 10 * 1024 * 1024, !data.isEmpty,
              let text = String(data: data, encoding: .utf8), text.contains("-->"),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("<!doctype html") else {
            throw SubtitleServiceError.invalidDownload
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let language = subtitle.language.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        let url = destination.appending(path: "\(language)-\(subtitle.id)-\(UUID().uuidString.prefix(8)).srt")
        try data.write(to: url, options: .atomic)
        return SubtitleDownload(url: url, remaining: response.remaining, resetTime: response.reset_time_utc)
    }

    private func login() async throws {
        var login = request(URL(string: "https://api.opensubtitles.com/api/v1/login")!, method: "POST")
        login.httpBody = try JSONEncoder().encode(LoginRequest(username: credentials.username, password: credentials.password))
        let response: LoginResponse = try await api(login)
        guard !response.token.isEmpty else { throw SubtitleServiceError.invalidResponse }
        if let host = response.base_url {
            let text = host.contains("://") ? host : "https://" + host
            guard let url = URL(string: text), Self.isAPIURL(url) else { throw SubtitleServiceError.invalidResponse }
            baseURL = URL(string: "https://\(url.host!)/api/v1")!
        }
        token = response.token
        tokenDate = Date()
    }

    private func request(_ url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue(credentials.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method == "POST" { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return request
    }

    private func api<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await fetch(request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw SubtitleServiceError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw SubtitleServiceError.http(response.statusCode) }
        guard data.count < 2 * 1024 * 1024 else { throw SubtitleServiceError.invalidResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct LoginRequest: Encodable { let username: String; let password: String }
    private struct LoginResponse: Decodable { let token: String; let base_url: String? }
    private struct DownloadRequest: Encodable { let file_id: Int64; let sub_format: String }
    private struct DownloadResponse: Decodable { let link: String; let remaining: Int?; let reset_time_utc: String? }
    private struct SearchResponse: Decodable { let data: [Item]; let page: Int?; let total_pages: Int? }
    private struct Item: Decodable { let attributes: Attributes }
    private struct Attributes: Decodable {
        let language: String
        let release: String?
        let download_count: Int?
        let hearing_impaired: Bool?
        let files: [File]
    }
    private struct File: Decodable { let file_id: Int64; let file_name: String? }
}
