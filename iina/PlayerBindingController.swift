//
//  PlayerBindingController.swift
//  iina
//
//  Created by Matt Svoboda on 2022.05.17.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

let MP_MAX_KEY_DOWN = 4

/*
 A single PlayerBindingController instance should be associated with a single PlayerCore, and while the player window has focus ("is active"), its
 PlayerBindingController is expected to direct key presses to this class's `matchActiveKeyBinding` method.
 to match the user's key stroke(s) into recognized commands.

 This class stores up to the last 4 key combinations which the user pressed in this window in `keyPressHistory `.
 Switching between windows, or entering keys in a different window, does not affect the state of this player's window.
 Only input which occurs while this is the active window will change the contents of this structure. See "Key sequences" below.S

 This class also keeps track of any binidngs set by Lua scripts. It expects to be notified of new mpv "input sections" and updates to their
 states, via `defineSection()`, `enableSection()`, and `disableSection()`. In order to emulate mpv's algorithm for prioritizing input bindings
 which are set by Lua plugins via libmpv, each PlayerBindingController contains an `InputSectionStack` which approximates the stack-like structure
 used by an mpv core. In it, input bindings are grouped into  "input sections", which in turn must be "defined" and then "enabled" in order to
 be made active, and their order of enablement as well as any flags (signifying that each section is "strong" or "weak" or "exclusive")
 determines the rules for setting each binding's priority relative to others which possess an identical key combination trigger.

 * Some definitions *

 ** Key mappings **

 A `KeyMapping` is an association from user input to an IINA or mpv command.
 This can include mouse events (though not handled by this class), single keystroke (which may include modifiers), or a sequence of keystrokes.
 See [the mpv manual](https://mpv.io/manual/master/#key-names) for information on mpv's valid "key names".

 ** Input sections **

 Internally, mpv organizes key bindings into blocks called "input sections", or just "sections", which are identified by name. Because IINA
 doesn't currently support profiles, most IINA users (unless they are using Lua scripts) will only ever care about the implicit "default" section
 whose contents are dictated via input.conf.

 Confusingly, the input file can contain a label, "default-bindings start", which will put the bindings under it into a lower-priority group
 which is referred to by different names at different places in the code: it is either "builtin", "weak", or implied by a "default" flag (or missing
 the "force" flag) when defined. While the user-facing elements (mpv manual, config options) refers to these as "default bindings", it's not
 particularly wise to think of them as defaults, because they can be added and removed just as easily as other bindings; they simply have lower
 priority than their "force" counterparts. And in fact that is encouraged by mpv for authors who are writing Lua scripts.

 Inside this class we'll refer to "strong" (or non-defaults) bindings as having force==true, and "weak" bindings as having force==false.
 While mpv technically allows a mix of force and non-force bindings inside each section, for Lua scripts it is restricted to one type per section.
 We'll just use that para

 ** Key sequences **

 From the mpv manual:

 > It's also possible to bind a command to a sequence of keys:
 >
 > a-b-c show-text "command run after a, b, c have been pressed"
 > (This is not shown in the general command syntax.)
 >
 > If a or a-b or b are already bound, this will run the first command that matches, and the multi-key command will never be called.
 > Intermediate keys can be remapped to ignore in order to avoid this issue.
 > The maximum number of (non-modifier) keys for combinations is currently 4.

 Although IINA's active key bindings (as set in IINA's Preferences window) take effect immediately and apply to all player windows, each player
 window maintains independent state, and in keeping with this, each player's PlayerBindingController maintains a separate buffer of pressed keystrokes
 (going back as many as 4 keystrokes).

 */
class PlayerBindingController {

  // MARK: - Single player instance

  private let subsystem: Logger.Subsystem

  // Data structure which keeps track of a player's input sections
  private var sectionStack: InputSectionStack

  /*
   Stores up to the last 4 key presses, separately for each player.
   mpv equivalent: `int key_history[MP_MAX_KEY_DOWN];`
   Here, the the newest keypress is at the "head", with the "tail" being the oldest.
   */
  private var keyPressHistory = RingBuffer<String>(capacity: MP_MAX_KEY_DOWN)

  init(playerCore: PlayerCore) {
    self.subsystem = Logger.Subsystem(rawValue: "\(playerCore.subsystem.rawValue)/\(AppInputConfig.subsystem.rawValue)")

    // Default to adding the static shared sections
    sectionStack = InputSectionStack(subsystem, initialEnabledSections: AppInputConfig.sharedSections)
  }

  deinit {
    self.keyPressHistory.clear()
  }

  private func log(_ msg: String, level: Logger.Level = .debug) {
    Logger.log(msg, level: level, subsystem: subsystem)
  }

  func makeAppInputConfigBuilder() -> AppInputConfigBuilder {
    // this class is the only other class which can access this player's InputSectionStack.
    AppInputConfigBuilder(sectionStack)
  }

  // MARK: MPV Input section API

  func defineSection(_ inputSection: MPVInputSection) {
    sectionStack.defineSection(inputSection)
    AppInputConfig.rebuildCurrent()
  }

  func enableSection(_ sectionName: String, _ flags: [String]) {
    sectionStack.enableSection(sectionName, flags)
    AppInputConfig.rebuildCurrent()
  }

  func disableSection(_ sectionName: String) {
    sectionStack.disableSection(sectionName)
    AppInputConfig.rebuildCurrent()
  }

  // MARK: Key resolution

  /*
   Similar to `matchActiveKeyBinding()`, but takes a raw string directly (does not examine past key presses). Must be normalized.
   */
  func resolveMpvKey(_ keySequence: String) -> KeyMapping? {
    AppInputConfig.current.resolverDict[keySequence]?.keyMapping
  }

  /*
   Parses the user's most recent keystroke from the given keyDown event and determines if it (a) matches a key binding for a single keystroke,
   or (b) when combined with the user's previous keystrokes, matches a key binding for a key sequence.

   Returns:
   - nil if keystroke is invalid (e.g., it does not resolve to an actively bound keystroke or key sequence, and could not be interpreted as starting
     or continuing such a key sequence)
   - (a non-null) KeyMapping whose action is "ignore" if it should be ignored by mpv and IINA
   - (a non-null) KeyMapping whose action is not "ignore" if the keystroke matched an active (non-ignored) key binding or the final keystroke
     in a key sequence.
   */
  func matchActiveKeyBinding(endingWith keyDownEvent: NSEvent) -> KeyMapping? {
    assert (keyDownEvent.type == NSEvent.EventType.keyDown, "Expected a KeyDown event but got: \(keyDownEvent)")

    let keySequence: String = KeyCodeHelper.mpvKeyCode(from: keyDownEvent)
    if keySequence == "" {
      log("Event could not be translated; ignoring: \(keyDownEvent)")
      return nil
    }
    let normalizedKeySequence = KeyCodeHelper.normalizeMpv(keySequence)
    return matchShortestKeySequence(endingWith: normalizedKeySequence)
  }

  // Try to match key sequences, up to 4 keystrokes. shortest match wins
  private func matchShortestKeySequence(endingWith lastKeyStroke: String) -> KeyMapping? {
    let appBindings: AppInputConfig = AppInputConfig.current
    var keySequence = ""
    var hasPartialValidSequence = false

    keyPressHistory.insertHead(lastKeyStroke)

    for prevKey in keyPressHistory.reversed() {
      if keySequence.isEmpty {
        keySequence = prevKey
      } else {
        keySequence = "\(prevKey)-\(keySequence)"
      }

      log("Checking keySeq: \(keySequence.quoted)", level: .verbose)

      if let binding = appBindings.resolverDict[keySequence] {
        if binding.origin == .iinaPlugin {
          // Make extra sure we don't resolve plugin bindings here
          log("Sequence \(keySequence.quoted) resolved to an IINA plugin (and will be ignored)! This indicates a bug which should be fixed", level: .error)
          appBindings.logEnabledBindings()
          return nil
        }
        let keyMapping = binding.keyMapping
        if keyMapping.isIgnored {
          log("Ignoring \(keyMapping.normalizedMpvKey.quoted) (from: \(binding.srcSectionName.quoted))", level: .verbose)
          hasPartialValidSequence = true
        } else {
          log("Found matching binding: \(keyMapping.normalizedMpvKey.quoted) → \(keyMapping.readableAction.quoted) (from: \(binding.srcSectionName.quoted))")
          // Non-ignored action! Clear prev key buffer as per mpv spec
          keyPressHistory.clear()
          return keyMapping
        }
      }
    }

    if hasPartialValidSequence {
      // Send an explicit "ignore" for a partial sequence match, so player window doesn't beep
      log("Contains partial sequence, ignoring: \(keySequence.quoted)", level: .verbose)
      return KeyMapping(rawKey: keySequence, rawAction: MPVCommand.ignore.rawValue, comment: nil)
    } else {
      // Not even part of a valid sequence = invalid keystroke
      log("No active binding for keystroke \(lastKeyStroke.quoted)")
      appBindings.logEnabledBindings()
      return nil
    }
  }

}
