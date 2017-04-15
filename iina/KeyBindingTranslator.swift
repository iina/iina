//
//  KeyBindingTranslator.swift
//  iina
//
//  Created by lhc on 6/2/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Foundation
import Mustache

class KeyBindingTranslator {

  static let l10nDic: [String: String] = {
    guard let filePath = Bundle.main.path(forResource: "KeyBinding", ofType: "strings"),
      let dic = NSDictionary(contentsOfFile: filePath) as? [String : String] else {
        return [:]
    }
    return dic
  }()

  static let mpvCmdFormat: [String: String] = {
    guard let filePath = Bundle.main.path(forResource: "MPVCommandFormat", ofType: "strings"),
      let dic = NSDictionary(contentsOfFile: filePath) as? [String : String] else {
        return [:]
    }
    return dic
  }()

  static private let UnsupportedCmdPrefix = [
    "no-osd", "osd-auto", "osd-bar", "osd-msg-bar", "raw", "repeatable", "expand-properties"
  ]

  static func readableCommand(fromAction action: [String], isIINACommand: Bool = false) -> String {
    var commands = action.filter { !KeyBindingTranslator.UnsupportedCmdPrefix.contains($0) }
    // Command
    let cmd = commands[0]

    // If is IINA command
    if isIINACommand {
      return l10nDic["iina." + cmd] ?? cmd
    }

    // If translated
    if let mpvFormat = KeyBindingTranslator.mpvCmdFormat[cmd],
      let cmdTranslation = l10nDic["read." + cmd],
      let tmpl = try? Template(string: cmdTranslation) {
      // parse command
      var data: [String: String] = [:]
      for (index, part) in mpvFormat.components(separatedBy: " ").enumerated() {
        if part.contains("#") {
          // check '#' syntax
          let ss = part.components(separatedBy: "#")
          data[ss[0]] = commands.at(index) ?? ss[1]
        } else if part.contains(":") {
          // check ':' syntax
          let ss = part.components(separatedBy: ":")
          let key = ss[0]
          let value = commands.at(index)
          let choices = ss[1].components(separatedBy: "|")
          let boolKey = key + "_" + (value ?? choices[0])
          data[boolKey] = "true"
          data[key] = commands.at(index)
        } else if part.hasSuffix("...") {
          var mPart = part
          mPart.characters.removeLast(3)
          data[mPart] = commands[index..<commands.count].joined(separator: " ")
        } else {
          data[part] = commands.at(index)
        }
      }
      // add translation for property
      if let opt = data["property"], let optTranslation = l10nDic["opt." + opt] {
        data["property"] = optTranslation
      }
      // add translation for values
      if let value = data["value"] {
        if value == "yes" || value == "no" {
          data["value"] = l10nDic[value]
        } else if cmd == "add", !value.hasPrefix("-"), !value.hasPrefix("+") {
          data["value"] = "+" + value
        }
        // tweak for "seek"
        if cmd == "seek" {
          let seekOpt = data["opt"] ?? "relative"
          let splittedOpt = seekOpt.components(separatedBy: "+")
          if splittedOpt.contains(where: { $0.hasPrefix("absolute") }) {
            data["abs"] = "true"
          } else if value.hasPrefix("-") {
            data["bwd"] = "true"
            data["value"]!.characters.removeFirst()
          } else {
            data["fwd"] = "true"
          }
          if splittedOpt.contains(where: { $0.hasSuffix("percent") }) {
            data["per"] = "true"
          } else {
            data["sec"] = "true"
          }
          if splittedOpt.contains("exact") {
            data["exact"] = "true"
          } else if splittedOpt.contains("keyframes") {
            data["kf"] = "true"
          }
        }
      }
      // render
      if let rendered = try? tmpl.render(data) {
        return rendered
      }
    }
    // If not translated, just translate the cmd name
    if let translationForCmd = l10nDic["cmd." + cmd] {
      commands[0] = translationForCmd
    }
    return commands.joined(separator: " ")
  }

  static func string(fromCriterions criterions: [Criterion]) -> String {
    var mapped = criterions.filter { !$0.isPlaceholder }.map { $0.mpvCommandValue }

    let firstCriterion = criterions[0] as! TextCriterion

    if firstCriterion.isIINACommand {
      mapped.insert("@iina", at: 0)
    }

    // special cases

    /// [add property add|minus value] (length: 4)s
    if firstCriterion.name == "add" {
      // - format the number
      if var doubleValue = Double(mapped.popLast()!) {
        let sign = mapped.popLast()
        if sign == "minus" {
          doubleValue = -doubleValue
        }
        mapped.append(doubleValue.prettyFormat())
      } else {
        mapped.removeLast()
      }
    }

    /// [seek forward|backward|seek-to value flag] (length: 4)
    else if firstCriterion.name == "seek" {
      // - relative is default value
      if mapped[3] == "relative" {
        mapped.removeLast()
      }
      // - format the number
      if var doubleValue = Double(mapped[2]) {
        if mapped[1] == "backward" {
          doubleValue = -doubleValue
        }
        mapped[2] = doubleValue.prettyFormat()
      }
      mapped.remove(at: 1)
    }

    /// iina properties
    else if firstCriterion.name == "cycle" {
      if let name = (criterions[1] as? TextCriterion)?.name,
        KeyBindingDataLoader.toggleableIINAProperties.contains(name) {
        return "@iina toggle-\(name)"
      }
    }


    return mapped.joined(separator: " ")
  }

}
