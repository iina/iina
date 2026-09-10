import XCTest
@testable import IINALogic

final class PluginWebViewNavigationTests: XCTestCase {
  private let prefPrefix = "file:///plugins/demo/preferences.html"

  func testHelpTabNeverOpensExternally() {
    XCTAssertFalse(
      PluginWebViewNavigation.shouldOpenExternally(
        currentTabIsHelp: true,
        requestURL: URL(string: "https://example.com"),
        allowedPrefPrefix: prefPrefix
      )
    )
  }

  func testPrefPrefixAndAboutBlankStayInWebView() {
    XCTAssertFalse(
      PluginWebViewNavigation.shouldOpenExternally(
        currentTabIsHelp: false,
        requestURL: URL(string: prefPrefix),
        allowedPrefPrefix: prefPrefix
      )
    )
    XCTAssertFalse(
      PluginWebViewNavigation.shouldOpenExternally(
        currentTabIsHelp: false,
        requestURL: URL(string: "\(prefPrefix)#section"),
        allowedPrefPrefix: prefPrefix
      )
    )
    XCTAssertFalse(
      PluginWebViewNavigation.shouldOpenExternally(
        currentTabIsHelp: false,
        requestURL: URL(string: "about:blank"),
        allowedPrefPrefix: prefPrefix
      )
    )
  }

  func testHttpHttpsLinksOpenExternallyOnAboutOrSettings() {
    XCTAssertTrue(
      PluginWebViewNavigation.shouldOpenExternally(
        currentTabIsHelp: false,
        requestURL: URL(string: "https://github.com/iina/plugin"),
        allowedPrefPrefix: prefPrefix
      )
    )
    XCTAssertTrue(
      PluginWebViewNavigation.shouldOpenExternally(
        currentTabIsHelp: false,
        requestURL: URL(string: "http://example.com/docs"),
        allowedPrefPrefix: prefPrefix
      )
    )
  }

  func testNonHttpSchemesDoNotOpenExternally() {
    XCTAssertFalse(
      PluginWebViewNavigation.shouldOpenExternally(
        currentTabIsHelp: false,
        requestURL: URL(string: "file:///tmp/secret.html"),
        allowedPrefPrefix: prefPrefix
      )
    )
    XCTAssertFalse(
      PluginWebViewNavigation.shouldOpenExternally(
        currentTabIsHelp: false,
        requestURL: URL(string: "javascript:alert(1)"),
        allowedPrefPrefix: prefPrefix
      )
    )
    XCTAssertFalse(
      PluginWebViewNavigation.shouldOpenExternally(
        currentTabIsHelp: false,
        requestURL: nil,
        allowedPrefPrefix: prefPrefix
      )
    )
  }

  func testNilPrefPrefixStillOpensHttpExternally() {
    XCTAssertTrue(
      PluginWebViewNavigation.shouldOpenExternally(
        currentTabIsHelp: false,
        requestURL: URL(string: "https://example.com"),
        allowedPrefPrefix: nil
      )
    )
  }
}
