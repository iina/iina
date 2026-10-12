//
//  ObjcUtilsTests.swift
//  iinaTests
//
//  Tests for the deprecated AppKit calls that ObjcUtils makes on behalf of Swift code.
//

import AppKit
import Testing
@testable import IINA

@Suite("Deprecated AppKit calls made through ObjcUtils")
@MainActor
struct ObjcUtilsTests {

  /// An `NSColor` (device RGB 1, 0.5, 0.25, alpha 1) archived with `NSArchiver`, the format earlier versions of IINA stored colors
  /// in, made with `NSArchiver.archivedData(withRootObject:)`.
  private static let legacyColor = Data(
    base64Encoded: "BAtzdHJlYW10eXBlZIHoA4QBQISEhAdOU0NvbG9yAISECE5TT2JqZWN0AIWEAWMChARmZmZmAYMAAAA/gwAAgD4Bhg==")

  @Test("A color archived by an earlier version of IINA is read back")
  func legacyColorRead() throws {
    let data = try #require(Self.legacyColor)
    let color = try #require(ObjcUtils.unarchiveLegacyObject(with: data) as? NSColor)
    let rgb = try #require(color.usingColorSpace(.deviceRGB))
    #expect(rgb.redComponent == 1)
    #expect(rgb.greenComponent == 0.5)
    #expect(rgb.blueComponent == 0.25)
    #expect(rgb.alphaComponent == 1)
  }

  @Test("A view is given a best resolution, extended dynamic range OpenGL surface")
  func openGLSurface() {
    let view = NSView()
    ObjcUtils.enableHighResolutionOpenGLSurface(for: view)
    // Read by key, since reading the deprecated properties from Swift would warn.
    #expect(view.value(forKey: "wantsBestResolutionOpenGLSurface") as? Bool == true)
    #expect(view.value(forKey: "wantsExtendedDynamicRangeOpenGLSurface") as? Bool == true)
  }
}
