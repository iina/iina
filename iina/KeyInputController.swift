//
//  KeyInputController.swift
//  iina
//
//  Created by Matthew Svoboda on 2022.05.17.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/*
 A single KeyInputController instance should be associated with a single PlayerCore, and while the player window has focus, its
 PlayerWindowController is expected to direct key presses to this class's `resolveKeyEvent` method.
 to match the user's key stroke(s) into recognized commands.

 A [key mapping](x-source-tag://KeyMapping) is an association from user input to an IINA or MPV command.
 This can include mouse events (though not handled by this class), single keystroke (which may include modifiers), or a sequence of keystrokes.
 See [the MPV manual](https://mpv.io/manual/master/#key-names) for information on MPV's valid "key names".

 // MARK: - Note on key sequences

 From the MPV manual:

 > It's also possible to bind a command to a sequence of keys:
 >
 > a-b-c show-text "command run after a, b, c have been pressed"
 > (This is not shown in the general command syntax.)
 >
 > If a or a-b or b are already bound, this will run the first command that matches, and the multi-key command will never be called.
 > Intermediate keys can be remapped to ignore in order to avoid this issue.
 > The maximum number of (non-modifier) keys for combinations is currently 4.

 Although IINA's active key bindings (as set in IINA's Preferences window) take effect immediately and apply to all player windows, each player
 window maintains independent state, and in keeping with this, each player's KeyInputController maintains a separate buffer of pressed keystrokes
 (going back as many as 4 keystrokes).

 */
class KeyInputController {

  // MARK: - Shared state for all players

  static private let sharedSubsystem = Logger.Subsystem(rawValue: "keyinput")

  // Derived from IINA's currently active key bindings. We need to account for partial key sequences so that the user doesn't hear a beep
  // while they are typing the beginning of the sequence. For example, if there is currently a binding for "x-y-z", then "x" and "x-y".
  // This needs to be rebuilt each time the keybindings change.
  static private var partialValidSequences = Set<String>()

  // Reacts when there is a change to the global key bindings
  static private var keyBindingsChangedObserver: NSObjectProtocol? = nil

  static func initSharedState() {
    if let existingObserver = keyBindingsChangedObserver {
      NotificationCenter.default.removeObserver(existingObserver)
    }
    keyBindingsChangedObserver = NotificationCenter.default.addObserver(forName: .iinaKeyBindingChanged, object: nil, queue: .main) { _ in
      KeyInputController.rebuildPartialValidSequences()
    }

    // initial build
    KeyInputController.rebuildPartialValidSequences()
  }

  static private func onKeyBindingsChanged(_ sender: Notification) {
    Logger.log("Key bindings changed. Rebuilding partial valid key sequences", level: .verbose, subsystem: sharedSubsystem)
    KeyInputController.rebuildPartialValidSequences()
  }

  static private func rebuildPartialValidSequences() {
    var partialSet = Set<String>()
    for (keyCode, _) in PlayerCore.keyBindings {
      if keyCode.contains("-") && keyCode != "default-bindings" {
        let keySequence = keyCode.split(separator: "-")
        if keySequence.count >= 2 && keySequence.count <= 4 {
          var partial = ""
          for key in keySequence {
            if partial == "" {
              partial = String(key)
            } else {
              partial = "\(partial)-\(key)"
            }
            if partial != keyCode && !PlayerCore.keyBindings.keys.contains(partial) {
              partialSet.insert(partial)
            }
          }
        }
      }
    }
    Logger.log("Generated partialValidKeySequences: \(partialSet)", level: .verbose)
    partialValidSequences = partialSet
  }

  // MARK: - Single player instance

  private var lastKeysPressed = RingBuffer<String>(capacity: 4)

  private var playerCore: PlayerCore!
  private lazy var subsystem = Logger.Subsystem(rawValue: "\(playerCore.subsystem.rawValue)/\(KeyInputController.sharedSubsystem.rawValue)")

  init(playerCore: PlayerCore) {
    self.playerCore = playerCore
  }

  func log(_ msg: String, level: Logger.Level) {
    Logger.log(msg, level: level, subsystem: subsystem)
  }

  // Called when this window has keyboard focus but it was already handled by someone else (probably the main menu).
  // But it's still important to know that it happened
  func keyWasHandled(_ keyDownEvent: NSEvent) {
    log("Clearing list of pressed keys", level: .verbose)
    lastKeysPressed.clear()
  }

  /*
   Parses the user's most recent keystroke from the given keyDown event and determines if it (a) matches a key binding for a single keystroke,
   or (b) when combined with the user's previous keystrokes, matches a key binding for a key sequence.

   Returns:
   - nil if keystroke is invalid (e.g., it does not resolve to an actively bound keystroke or key sequence, and could not be interpreted as starting
     or continuing such a key sequence)
   - (a non-null) KeyMapping whose action is "ignore" if it should be ignored by MPV and IINA
   - (a non-null) KeyMapping whose action is not "ignore" if the keystroke matched an active (non-ignored) key binding or the final keystroke
     in a key sequence.
   */
  func resolveKeyEvent(_ keyDownEvent: NSEvent) -> KeyMapping? {
    assert (keyDownEvent.type == NSEvent.EventType.keyDown, "Expected a KeyDown event but got: \(keyDownEvent)")

    let keyStroke: String = KeyCodeHelper.mpvKeyCode(from: keyDownEvent)
    if keyStroke == "" {
      log("Event could not be translated; ignoring: \(keyDownEvent)", level: .debug)
      return nil
    }

    return resolveKeySequence(keyStroke)
  }

  // Try to match key sequences, up to 4 values. shortest match wins
  private func resolveKeySequence(_ lastKeyStroke: String) -> KeyMapping? {
    lastKeysPressed.insertHead(lastKeyStroke)

    var keySequence = ""
    var hasPartialValidSequence = false

    for prevKey in lastKeysPressed.reversed() {
      if keySequence.isEmpty {
        keySequence = prevKey
      } else {
        keySequence = "\(prevKey)-\(keySequence)"
      }

      log("Checking sequence: \"\(keySequence)\"", level: .verbose)

      if let keyBinding = PlayerCore.keyBindings[keySequence] {
        if keyBinding.isIgnored {
          log("Ignoring \"\(keyBinding.key)\"", level: .verbose)
          hasPartialValidSequence = true
        } else {
          log("Found active binding for \"\(keyBinding.key)\" -> \(keyBinding.action)", level: .debug)
          // Non-ignored action! Clear prev key buffer as per MPV spec
          lastKeysPressed.clear()
          return keyBinding
        }
      } else if !hasPartialValidSequence && KeyInputController.partialValidSequences.contains(keySequence) {
        // No exact match, but at least is part of a key sequence.
        hasPartialValidSequence = true
      }
    }

    if hasPartialValidSequence {
      // Send an explicit "ignore" for a partial sequence match, so player window doesn't beep
      log("Contains partial sequence, ignoring: \"\(keySequence)\"", level: .verbose)
      return KeyMapping(key: keySequence, rawAction: MPVCommand.ignore.rawValue, isIINACommand: false, comment: nil)
    } else {
      // Not even part of a valid sequence = invalid keystroke
      log("No active binding for keystroke \"\(lastKeyStroke)\"", level: .debug)
      return nil
    }
  }
}
