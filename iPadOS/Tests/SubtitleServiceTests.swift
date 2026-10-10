// SPDX-License-Identifier: GPL-3.0-only
// Experimental iPadOS contribution added 2026-10-10.

import XCTest
@testable import IINAPad

private actor SubtitleFixtureAPI {
    var requests: [URLRequest] = []
    var downloadLink = "https://dl.opensubtitles.com/subtitle.srt"
    var searchStatus = 200
    let fileID: Int64 = 9_007_199_254_740_999

    func setDownloadLink(_ link: String) { downloadLink = link }
    func setSearchStatus(_ status: Int) { searchStatus = status }

    func fetch(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let path = request.url!.path
        var status = 200
        let body: String
        switch path {
        case "/api/v1/subtitles":
            status = searchStatus
            body = """
            {"page":1,"total_pages":2,"data":[{"attributes":{"language":"en","release":"Fixture release","download_count":4,"hearing_impaired":false,"files":[{"file_id":\(fileID),"file_name":"fixture.srt"}]}}]}
            """
        case "/api/v1/login": body = "{\"token\":\"test-token\",\"base_url\":\"vip-api.opensubtitles.com\"}"
        case "/api/v1/download": body = "{\"link\":\"\(downloadLink)\",\"remaining\":3,\"reset_time_utc\":\"tomorrow\"}"
        case "/subtitle.srt": body = "1\n00:00:00,000 --> 00:00:04,000\nFixture subtitle\n"
        default: throw SubtitleServiceError.invalidResponse
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}

final class SubtitleServiceTests: XCTestCase {
    private let credentials = SubtitleCredentials(apiKey: "test-key", username: "test-user", password: "test-password", userAgent: "Test v1")

    func testSearchAndAuthenticatedDownload() async throws {
        let api = SubtitleFixtureAPI()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { if FileManager.default.fileExists(atPath: folder.path) { try! FileManager.default.removeItem(at: folder) } }
        let client = OpenSubtitlesClient(credentials: credentials, destination: folder, fetch: { try await api.fetch($0) })
        let page = try await client.search(query: "A & B", language: "en")
        XCTAssertEqual(page.totalPages, 2)
        XCTAssertEqual(page.results.first?.id, 9_007_199_254_740_999)
        let download = try await client.download(page.results[0])
        XCTAssertEqual(download.remaining, 3)
        XCTAssertTrue(try String(contentsOf: download.url, encoding: .utf8).contains("Fixture subtitle"))
        let requests = await api.requests
        XCTAssertEqual(requests.count, 4)
        let query = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first(where: { $0.name == "query" })?.value, "A & B")
        XCTAssertEqual(query.map(\.name), query.map(\.name).sorted())
        XCTAssertEqual(requests[2].url?.host, "vip-api.opensubtitles.com")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        let body = try JSONSerialization.jsonObject(with: requests[2].httpBody!) as! [String: Any]
        XCTAssertEqual((body["file_id"] as? NSNumber)?.int64Value, 9_007_199_254_740_999)
        XCTAssertNil(requests[3].value(forHTTPHeaderField: "Api-Key"))
        XCTAssertNil(requests[3].value(forHTTPHeaderField: "Authorization"))
    }

    func testDownloadRejectsUntrustedHostBeforeFetching() async throws {
        let api = SubtitleFixtureAPI()
        await api.setDownloadLink("https://opensubtitles.com.attacker.example/secret.srt")
        let client = OpenSubtitlesClient(credentials: credentials, fetch: { try await api.fetch($0) })
        do {
            _ = try await client.download(OnlineSubtitle(id: 1, name: "Fixture", language: "en", downloads: 0, hearingImpaired: false))
            XCTFail("Untrusted download was accepted")
        } catch SubtitleServiceError.invalidDownload { }
        let requests = await api.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testQuotaAndHostValidation() async throws {
        let api = SubtitleFixtureAPI()
        await api.setSearchStatus(429)
        let client = OpenSubtitlesClient(credentials: credentials, fetch: { try await api.fetch($0) })
        do { _ = try await client.search(query: "Fixture", language: "en"); XCTFail("Quota error was hidden") }
        catch SubtitleServiceError.http(429) { }
        XCTAssertFalse(OpenSubtitlesClient.isAPIURL(URL(string: "http://api.opensubtitles.com")!))
        XCTAssertFalse(OpenSubtitlesClient.isAPIURL(URL(string: "https://user:password@api.opensubtitles.com")!))
        XCTAssertFalse(OpenSubtitlesClient.isProviderURL(URL(string: "https://dl.opensubtitles.com.attacker.example")!))
        XCTAssertTrue(OpenSubtitlesClient.isProviderURL(URL(string: "https://dl.opensubtitles.org")!))
    }
}
