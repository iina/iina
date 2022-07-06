//
//  FuzzySearch.swift
//  iina
//
//  Created by Anas Saeed on 5/22/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/**
 An implementation of [Junegunn's FuzzyMatchV1 algorithm](https://github.com/junegunn/fzf/blob/master/src/algo/algo.go) in swift.
 Junegunn's code is licensed under an [MIT License](https://github.com/junegunn/fzf/blob/master/LICENSE). All credit for the algorithm goes to the original author.
 */


/*
 Junegunn's FuzzyMatchV1 consists of two steps:
 1. Finding the shortest fuzzy occurence of the pattern within the given string
 2. Scoring the found match
 
 Matching
 --------
 
 FuzzyMatchV1 finds the first fuzzy occurence of the pattern within the text through a forward scan, and once the position of the last character is located, it traverses backwards to find a shorter match.
 
 i__i___iina__  Pattern: "iina"
 *--*-----**>   1. Forward Scan
 <****    2. Backward Scan
 
 Scoring
 -------
 
 Once the pattern has been located, the algorithm will score the substring that contains the match; in the example above, it will score the substring "iina", not "i__i___iina"
 
 Read more about the scoring criteria [here](https://github.com/junegunn/fzf/blob/master/src/algo/algo.go)
 
 */

fileprivate let ScoreMatch = 16
fileprivate let ScoreGapStart = -3
fileprivate let ScoreGapExtension = -1

fileprivate let LeadingLetterPenalty = ScoreGapExtension
fileprivate let MaxLeadingLetterPenalty = LeadingLetterPenalty * 4

fileprivate let BonusBoundary = ScoreMatch / 2
fileprivate let BonusNonWord = ScoreMatch / 2
fileprivate let BonusCamel123 = BonusBoundary + ScoreGapExtension
fileprivate let BonusConsecutive = -(ScoreGapStart + ScoreGapExtension)
fileprivate let BonusFirstCharMultiplier = 2


/**
 Holds result of the fuzzy match on a string
 `start`: The starting index of the matched substring
 `end`: The ending index of the matched substring
 `score`: the score of the matched substring
 `pos`: the position of all matched letters in the string (used for rendering the matched letters as bolded)
 */
struct Result {
  let start: Int
  let end: Int
  let score: Int
  let pos: [Int]
  
  init(_ start: Int,_ end: Int,_ score: Int,_ pos: [Int]) {
    self.start = start
    self.end = end
    self.score = score
    self.pos = pos
  }
}

/**
 Enum used for scoring each character
 case `lower`: lowercase letters, i.e. 'a', 'b', 'c'
 case `upper`: uppercase letters, i.e. 'A', 'B', 'C'
 case `letter`: unicode characters, i.e. ’あ’
 case `number`: numbers, i.e. '1', '2', '3'
 case `nonWord`: characters that aren't letters or numbers, i.e. '-', '#'
 */
enum CharType {
  case lower
  case upper
  case letter
  case number
  case nonWord
}

/// Utility functions ot convert `Character` to `CharType`
func charTypeOf(_ char: Character) -> CharType {
  if char.isASCII {
    return charTypeOfAscii(char)
  }
  
  return charTypeOfNonAscii(char)
}

func charTypeOfAscii(_ char: Character) -> CharType {
  if char.isLowercase {
    return .lower
  } else if char.isUppercase {
    return .upper
  } else if char.isNumber {
    return .number
  }
  
  return .nonWord
}

func charTypeOfNonAscii(_ char: Character) -> CharType {
  if char.isLowercase {
    return .lower
  } else if char.isUppercase {
    return .upper
  } else if char.isLetter {
    return .letter
  }
  
  return .nonWord
}

/// Calculates the bonus score for two consecutive characters based on the FuzzyMatchV1 scoring criteria.
func bonusFor(_ prevType: CharType, _ currentType: CharType) -> Int {
  // Bonus if the previous letter is a separator like '-' or ' ', and the current letter is anything else.
  // i.e. ' P', '_I'
  if prevType == .nonWord && currentType != .nonWord {
    return BonusBoundary
  }
  
  // Bonus for matches in camelCase words or a number following a word (i.e. hello123)
  else if prevType == .lower && currentType == .upper || prevType != .number && currentType == .number {
    return BonusCamel123
  }
  
  else if currentType == .nonWord {
    return BonusNonWord
  }
  
  return 0
}

/// Calculates the score of the matched substring of `pattern` in `text`
func calculateScore(_ text: String,_ pattern: String,_ startIdx: Int,_ endIdx: Int) -> Result {
  // score: total score
  // inGap: if the previous character is unmatched
  // consecutive: number of previous characters that also matched
  var patternIdx = 0, score = 0, inGap = false, consecutive = 0, firstBonus = 0
  
  // Indexes of all matched characters in text
  var pos: [Int] = []
  
  var prevType = CharType.nonWord
  
  if startIdx > 0 {
    prevType = charTypeOf(text[startIdx - 1])
  }
  
  for textIdx in stride(from: startIdx, to: endIdx, by: 1) {
    let textChar = text[textIdx]
    let textType = charTypeOf(textChar)
    
    let patternChar = pattern[patternIdx]
    
    // If matched
    if textChar.lowercased() == patternChar.lowercased() {
      pos.append(textIdx)
      
      // Bonus for matching characters
      score += ScoreMatch
      
      var bonus = bonusFor(prevType, textType)
      
      if consecutive == 0 {
        firstBonus = bonus
      } else {
        if bonus == BonusBoundary {
          firstBonus = bonus
        }
        bonus = max(max(bonus, firstBonus), BonusConsecutive)
      }
      
      if patternIdx == 0 {
        score += bonus * BonusFirstCharMultiplier
        
        // Deduct score for every letter that comes before the first match
        score += max(LeadingLetterPenalty * textIdx, MaxLeadingLetterPenalty)
      } else {
        score += bonus
      }
      
      inGap = false
      consecutive += 1
      patternIdx += 1
      
    }
    // If not matched
    else {
      if inGap {
        score += ScoreGapExtension
      } else {
        score += ScoreGapStart
      }
      
      inGap = true
      consecutive = 0
      firstBonus = 0
    }
    
    prevType = textType
  }
  
  return Result(startIdx, endIdx, score, pos)
}

/// Finds the shortest occurence of `pattern` in `text`, and returns a score calculated from `calculateScore`
func fuzzyMatch(text: String, pattern: String) -> Result {
  if pattern.count == 0 {
    return Result( 0, 0, 0, [])
  }
  
  var patternIdx = 0, startIdx = -1, endIdx = -1
  
  let textLen = text.count
  let patternLen = pattern.count
  
  // We use case insensitive matching
  let textNorm = text.lowercased()
  let patternNorm = pattern.lowercased()
  
  // Forward Scan
  for textIdx in stride(from: 0, to: textLen, by: 1) {
    let textChar = textNorm[textIdx]
    let patternChar = patternNorm[patternIdx]
    
    if textChar == patternChar {
      if startIdx < 0 {
        startIdx = textIdx
      }
      
      patternIdx += 1
      
      if patternIdx == patternLen {
        endIdx = textIdx + 1
        break
      }
    }
  }
  
  if startIdx >= 0 {
    
    // Backwards Scan
    if endIdx >= 0 {
      patternIdx -= 1
      
      for textIdx in stride(from: endIdx - 1, through: startIdx, by: -1) {
        let textChar = textNorm[textIdx]
        let patternChar = patternNorm[patternIdx]
        
        if textChar == patternChar {
          patternIdx -= 1
          if patternIdx < 0 {
            startIdx = textIdx
            break
          }
        }
      }
      
    }
    // If we didn't find a full match of the pattern in the text, but some characters did match, we still want to score those matches
    else {
      endIdx = textLen
    }
    
    return calculateScore(text, pattern, startIdx, endIdx)
  }
  
  return Result(-1, -1, 0, [])
}

/// Get the character of a string at a specificed index
/// Ex.
/// ```
/// let text = "iina"
/// text[0] -> 'i'
/// text[2] -> 'n'
/// ```
extension String {
  subscript (i: Int) -> Character {
    return self[index(startIndex, offsetBy: i)]
  }
}
