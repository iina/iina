//
//  MpvScriptMessageCenter.swift
//  iina
//
//  Bridges mpv's `script-message` command (delivered via the C API as
//  `MPV_EVENT_CLIENT_MESSAGE`) to IINA-internal subscribers using
//  `NotificationCenter`. This allows bundled Lua scripts and future
//  uosc-style integrations to call back into IINA by sending a
//  `script-message` from inside mpv.
//
//  See SPEC requirement 9 and PLAN Phase 4.
//

import Foundation

/// Singleton bridge that re-broadcasts mpv `script-message` events to
/// IINA-internal subscribers via `NotificationCenter`.
///
/// When a Lua script (or any mpv client) invokes the `script-message`
/// command, libmpv delivers it as an `MPV_EVENT_CLIENT_MESSAGE` whose
/// `args[0]` is the message name and `args[1...]` are the payload
/// arguments. `MPVController.handleEvent` parses the C struct and
/// forwards the extracted name/args to this center.
///
/// Subscribers register for `MpvScriptMessageCenter.notificationName`
/// and read `userInfo` keys `"name"` (String) and `"args"` ([String]).
final class MpvScriptMessageCenter {

  /// The `Notification.Name` used to broadcast script-message events.
  static let notificationName = Notification.Name("iina.mpv.scriptMessage")

  /// Process-wide singleton. There is exactly one mpv script-message
  /// channel per IINA process, regardless of the number of open
  /// windows / `PlayerCore` instances.
  static let shared = MpvScriptMessageCenter()

  private init() {}

  /// Re-broadcast a script-message event to all registered observers.
  ///
  /// - Parameters:
  ///   - name: The message name (the first argument of mpv's
  ///     `script-message` command).
  ///   - args: The payload arguments (everything after the name).
  func handle(name: String, args: [String]) {
    NotificationCenter.default.post(
      name: Self.notificationName,
      object: nil,
      userInfo: ["name": name, "args": args]
    )
  }
}
