//
//  PluginWebViewNavigation.swift
//  iina
//
//  Pure navigation policy for plugin settings/about WebViews (issue #6329).
//  Mirrored in other/LogicTests for unit tests.
//

import Foundation

enum PluginWebViewNavigation {
  /// When a non-help tab would cancel in-WebView navigation, open http(s) in the browser instead.
  static func shouldOpenExternally(
    currentTabIsHelp: Bool,
    requestURL: URL?,
    allowedPrefPrefix: String?
  ) -> Bool {
    guard !currentTabIsHelp, let url = requestURL else { return false }
    let absolute = url.absoluteString
    if absolute == "about:blank" { return false }
    if let allowedPrefPrefix, absolute.starts(with: allowedPrefPrefix) { return false }
    guard let scheme = url.scheme?.lowercased() else { return false }
    return scheme == "http" || scheme == "https"
  }
}
