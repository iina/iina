//
//  LyricsOverlayState.swift
//  iina
//
//  Created by Erik Molina on 12/21/25.
//

import Foundation

struct LyricsOverlayState: Equatable {
    let previous: LyricsLine?
    let current: LyricsLine?
    let next: LyricsLine?
}
