//
//  KeychainAccess.swift
//  iina
//
//  Created by Collider LI on 25/8/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation

class KeychainAccess {

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
  }

  static func write(username: String, password: String, forService serviceName: ServiceName) -> (succeeded: Bool, errorMessage: String?) {
    let service = serviceName.rawValue as NSString
    let accountName = username as NSString
    let pw = password as NSString
    let pwData = pw.data(using: String.Encoding.utf8.rawValue)! as NSData

    let status: OSStatus
    // try to read the password
    let (_, succeeded, _, readItemRef) = read(username: username, forService: serviceName)
    if succeeded {
      // else, try to modify the password
      status = SecKeychainItemModifyContent(readItemRef!,
                                            nil,
                                            UInt32(pw.length),
                                            pwData.bytes)
    } else {
      // if can't read, try to add password
      status = SecKeychainAddGenericPassword(nil,
                                             UInt32(service.length),
                                             service.utf8String,
                                             UInt32(accountName.length),
                                             accountName.utf8String,
                                             UInt32(pw.length),
                                             pwData.bytes,
                                             nil)
    }
    return (status == errSecSuccess, SecCopyErrorMessageString(status, nil) as String?)
  }

  static func read(username: String, forService serviceName: ServiceName) -> (password: String?, succeeded: Bool, errorMessage: String?, item: SecKeychainItem?) {
    let service = serviceName.rawValue as NSString
    let accountName = username as NSString
    var pwLength = UInt32()
    var pwData: UnsafeMutableRawPointer? = nil
    var itemRef: SecKeychainItem? = nil
    let status = SecKeychainFindGenericPassword(nil,
                                                UInt32(service.length),
                                                service.utf8String,
                                                UInt32(accountName.length),
                                                accountName.utf8String,
                                                &pwLength,
                                                &pwData,
                                                &itemRef)
    var password: String? = ""
    let succeeded = status == errSecSuccess
    if succeeded {
      let data = Data(bytes: pwData!, count: Int(pwLength))
      password = String(data: data, encoding: .utf8)
    }
    if pwData != nil {
      SecKeychainItemFreeContent(nil, pwData)
    }
    return (password, succeeded, SecCopyErrorMessageString(status, nil) as String?, itemRef)
  }
}
