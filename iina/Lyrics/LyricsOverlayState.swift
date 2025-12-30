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
    
    // Expanded state for scrollable view
    let allLines: [LyricsLine]
    let currentIndex: Int
    
    init(previous: LyricsLine? = nil, current: LyricsLine? = nil, next: LyricsLine? = nil, 
         allLines: [LyricsLine] = [], currentIndex: Int = -1) {
        self.previous = previous
        self.current = current
        self.next = next
        self.allLines = allLines
        self.currentIndex = currentIndex
    }
}
