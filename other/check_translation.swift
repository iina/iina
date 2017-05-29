import Cocoa

class Regex {

  var regex: NSRegularExpression?

  init (_ pattern: String) {
    if let exp = try? NSRegularExpression(pattern: pattern, options: []) {
      self.regex = exp
    } else {
      print("Cannot create regex \(pattern)")
    }
  }

  func matches(_ str: String) -> Bool {
    if let matches = regex?.numberOfMatches(in: str, options: [], range: NSMakeRange(0, str.characters.count)) {
      return matches > 0
    } else {
      return false
    }
  }

  func captures(in str: String) -> [String] {
    var result: [String] = []
    if let matches = regex?.matches(in: str, options: [], range: NSMakeRange(0, str.characters.count)) {
      matches.forEach { match in
        for i in 0..<match.numberOfRanges {
          let range = match.rangeAt(i)
          if range.length > 0 {
            result.append((str as NSString).substring(with: match.rangeAt(i)))
          } else {
            result.append("")
          }
        }
      }
    }
    return result
  }
}


let ignorePlaceHolderTitle = true
let checkRedundantKey = false

let languages = ["de", "fr", "it", "ja", "ko", "pl", "zh-Hans", "zh-Hant", "ru"]

var stat: [String: Int] = {
  var dic: [String: Int] = [:]
  for lang in languages {
    dic[lang] = 0
  }
  return dic
}()

let fmtRegexp = Regex("%[\\.\\d]*[fsd@]")

let fm = FileManager.default

extension String {
  var directory: String {
    return "./iina/\(self).lproj"
  }

  func file(_ filename: String) -> String {
    return self + "/" + filename
  }

  var exists: Bool {
    return fm.fileExists(atPath: self)
  }

  var stringsContent: [String: String]? {
    if let dic = NSDictionary(contentsOfFile: self) as? [String : String] {
      return dic
    } else {
      print("  [x] Cannot read file \"\(self)\"")
      return nil
    }
  }

  var splittedFilename: (String, String) {
    let nsstr = self as NSString
    return (nsstr.deletingPathExtension, nsstr.pathExtension)
  }
}

enum BaseLang {
  case base, zhHans
  var name: String {
    switch self {
    case .base:
      return "Base"
    case .zhHans:
      return "zh-Hans"
    }
  }
}

func sameArray(_ a: [String], _ b: [String]) -> Bool {
  guard a.count == b.count else { return false }
  for i in 0..<a.count {
    guard a[i] == b[i] else { return false }
  }
  return true
}

func makeSure(fileExists file: String, withExtension ext: String, basedOn base: BaseLang) {
  let fullname = "\(file).\(ext)"
  for lang in languages {
    if base == .zhHans && lang == "zh-Hans" { continue }
    guard lang.directory.file(fullname).exists else {
      print("  [x][\(lang)] File \"\(fullname)\" doesn't extst")
      stat[lang]! += 1
      continue
    }
  }
}

func makeSure(allKeysExistInFile file: String, basedOn base: BaseLang) {
  let baseLang = base.name
  let fullname = "\(file).strings"
  guard let baseDic = baseLang.directory.file(fullname).stringsContent else { return }

  for lang in languages {
    if base == .zhHans && lang == "zh-Hans" { continue }
    guard var langDic = lang.directory.file(fullname).stringsContent else { stat[lang]! += 1; return }
    // for all keys in base dic
    for (key, baseValue) in baseDic {
      // check whether key exist
      if ignorePlaceHolderTitle && (baseValue == "Label" || baseValue == "Text Cell") { continue }
      if let value = langDic[key] {
        // check whether has formatting problem
        if fmtRegexp.matches(baseValue) {
          guard sameArray(fmtRegexp.captures(in: baseValue), fmtRegexp.captures(in: value)) else {
            print("  [!][\(lang)] Wrong format string for key \(key) in \(file)")
            print("        Base:        \(baseValue)")
            print("        Translation: \(value)")
            stat[lang]! += 1
            continue
          }
        }
        langDic.removeValue(forKey: key)
      } else {
        print("  [!][\(lang)] Key \"\(key)\" doesn't exist in \(file) (\(baseValue))")
        stat[lang]! += 1
      }
    }
    // check redundant keys
    for (key, langValue) in langDic {
      guard checkRedundantKey else { continue }
      if ignorePlaceHolderTitle && (langValue == "Label" || langValue == "Text Cell") { continue }
      print("  [-][\(lang)] Redundant key \"\(key)\" (\(langValue))")
      stat[lang]! += 1
    }
  }
}

// start

guard let rawFileList = try? fm.contentsOfDirectory(atPath: "Base".directory) else {
  print("[ERROR] Cannot get file list")
  exit(1)
}

let fileList = rawFileList.filter { !$0.hasPrefix(".") }

for file in fileList {
  let (filename, ext) = file.splittedFilename

  print("---\n# \(file) #")
  switch ext {
  case "rtf":
    makeSure(fileExists: filename, withExtension: "rtf", basedOn: .base)
  case "xib":
    makeSure(fileExists: filename, withExtension: "strings", basedOn: .base)
    makeSure(allKeysExistInFile: filename, basedOn: .zhHans)
  case "strings":
    makeSure(fileExists: filename, withExtension: "strings", basedOn: .base)
    makeSure(allKeysExistInFile: filename, basedOn: .base)
  default:
    print("[INFO] Jumpped \(file)")
  }
}

print("\nFinished. Issues count:")
print(stat)
