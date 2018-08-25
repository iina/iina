//
//  KeychainAccess.swift
//  iina
//
//  Created by Collider LI on 25/8/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation

class KeychainAccess {

  enum KeychainError: Error {
    case noResult
    case unhandledError(message: String)
    case unexpectedData
  }

  struct ServiceName: RawRepresentable {
    typealias RawValue = String
    var rawValue: String

    init(rawValue: String) {
      self.rawValue = rawValue
    }

    init(_ rawValue: String) {
      self.init(rawValue: rawValue)
    }

    static let openSubAccount = ServiceName(rawValue: "IINA OpenSubtitles Account")
    static let httpAuth = ServiceName(rawValue: "IINA Saved HTTP Password")
  }

  static func write(username: String, password: String, forService serviceName: ServiceName, server: String? = nil, port: Int? = nil) throws {
    let status: OSStatus

    if let _ = try? read(username: username, forService: .openSubAccount, server: nil, port: nil) {

      // if password exists, try to update the password
      var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: serviceName.rawValue]
      if let server = server { query[kSecAttrServer as String] = server }
      if let port = port { query[kSecAttrPort as String] = port }

      // create attributes for updating
      let passwordData = password.data(using: String.Encoding.utf8)!
      let attributes: [String: Any] = [kSecAttrAccount as String: username,
                                       kSecValueData as String: passwordData]
      // update
      status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

    } else {

      // try to write the password
      var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: serviceName.rawValue,
                                  kSecAttrAccount as String: username,
                                  kSecValueData as String: password]
      if let server = server { query[kSecAttrServer as String] = server }
      if let port = port { query[kSecAttrPort as String] = port }
      status = SecItemAdd(query as CFDictionary, nil)
    }

    // check result
    guard status != errSecItemNotFound else { throw KeychainError.noResult }
    guard status == errSecSuccess else {
      let message = (SecCopyErrorMessageString(status, nil) as String?) ?? ""
      throw KeychainError.unhandledError(message: message)
    }
  }

  static func read(username: String?, forService serviceName: ServiceName, server: String? = nil, port: Int? = nil) throws -> (username: String, password: String) {
    var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: serviceName.rawValue,
                                kSecMatchLimit as String: kSecMatchLimitOne,
                                kSecReturnAttributes as String: true,
                                kSecReturnData as String: true]
    if let username = username {
      query[kSecAttrAccount as String] = username
    }
    if let server = server {
      query[kSecAttrServer as String] = server
    }

    // initiate the search
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status != errSecItemNotFound else { throw KeychainError.noResult }
    guard status == errSecSuccess else {
      let message = (SecCopyErrorMessageString(status, nil) as String?) ?? ""
      throw KeychainError.unhandledError(message: message)
    }

    // get data
    guard let existingItem = item as? [String : Any],
      let passwordData = existingItem[kSecValueData as String] as? Data,
      let password = String(data: passwordData, encoding: String.Encoding.utf8),
      let account = existingItem[kSecAttrAccount as String] as? String
      else {
        throw KeychainError.unexpectedData
    }
    return (account, password)
  }
}
