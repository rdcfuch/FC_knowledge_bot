//
//  Chat.swift
//  FC_knowledge_bot
//
//  Created by FC Fu on 1/31/25.
//

import Foundation
import SwiftData

@Model
final class Chat {
    var id: UUID
    var title: String
    var createdAt: Date
    var messages: [ChatMessage]?
    
    init(title: String) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.messages = []
    }
}

@Model
final class ChatMessage {
    var id: UUID
    var content: String
    var timestamp: Date
    var isUserMessage: Bool
    var chat: Chat?
    var relatedDocuments: [Document]?
    
    init(content: String, isUserMessage: Bool) {
        self.id = UUID()
        self.content = content
        self.timestamp = Date()
        self.isUserMessage = isUserMessage
        self.relatedDocuments = []
    }
}