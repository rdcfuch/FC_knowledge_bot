//
//  Item.swift
//  FC_knowledge_bot
//
//  Created by FC Fu on 1/31/25.
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
