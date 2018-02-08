//
//  SyncManager.swift
//  iina
//
//  Created by Andrey Sevrikov on 07/02/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Foundation

protocol SyncManagerDelegate: class {
  /** State of synchronization process has changed */
  func didChange(state: SyncManager.State, source: SyncManager.Source)
  
  /** Synchronization is finished with calculated *delay* */
  func didSync(source: SyncManager.Source, delay: Double)
}

class SyncManager {
  
  enum Source {
    case subs
    case audio
  }
  
  enum State {
    
    /** Synchronization isn't started yet */
    case idle
    
    /** Marking video */
    case presync
    
    /** Marking subs or audio */
    case sync
  }

  weak var delegate: SyncManagerDelegate?
  
  private var source: Source?
  private var state: State = .idle
  
  private var lastPosition: Double?
  
  /**
   Steps through synchronization process
   
   - Parameters:
     - source: What kind of media is being synchronized
     - position: Current playback position
   */
  func step(source: Source, position: Double) {
  
    if let lastSource = self.source, lastSource != source {
      self.source = source
      self.state = .presync
      
      delegate?.didChange(state: self.state, source: source)
      
      return
    }
    
    switch state {
      
    case .idle:
      self.source = source
      self.state = .presync
      
      delegate?.didChange(state: self.state, source: source)
      
    case .presync:
      lastPosition = position
      self.state = .sync
      
      delegate?.didChange(state: self.state, source: source)
      
    case .sync:
      guard let lastPosition = lastPosition else { return }
      
      self.source = nil
      self.state = .idle
      
      delegate?.didChange(state: self.state, source: source)
      delegate?.didSync(source: source, delay: lastPosition - position)
    }
  }
  
}
