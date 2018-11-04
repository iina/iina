//
//  Translators.swift
//  iina
//
//  Created by Collider LI on 1/11/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation

struct LangObj: Decodable {
  let lang: String
  let translators: [TranslatorObj]
  struct TranslatorObj: Decodable {
    let name: String
    let link: LinkObj
    struct LinkObj: Decodable {
      let title: String?
      let url: String?
      let email: String?
    }
  }
}

struct Translator {
  static let all: [String: [Translator]]? = {
    guard
      let resource = Bundle.main.path(forResource: "Translators", ofType: "json"),
      let data = try? Data(contentsOf: URL(fileURLWithPath: resource)),
      let languages = try? JSONDecoder().decode([LangObj].self, from: data)
      else { return nil }
    let pairs = languages.map {(
        $0.lang,
        $0.translators.map { Translator(name: $0.name, url: $0.link.url, title: $0.link.title, email: $0.link.email) }
      )}
    return [String: [Translator]](uniqueKeysWithValues: pairs)
  }()

  let name: String
  let url: String?
  let title: String?
  let email: String?
}
