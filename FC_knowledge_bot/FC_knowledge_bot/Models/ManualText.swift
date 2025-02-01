//
//  ManualText.swift
//  FC_knowledge_bot
//
//  Created by FC Fu on 1/31/25.
//

import Foundation
import SwiftData

@Model
final class ManualText {
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var lastModifiedAt: Date
    
    init(title: String, content: String) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.createdAt = Date()
        self.lastModifiedAt = Date()
    }
}