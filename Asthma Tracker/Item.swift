//
//  Item.swift
//  Asthma Tracker
//
//  Created by Marc Thomas on 14/05/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
