//
//  Document.swift
//  FC_knowledge_bot
//
//  Created by FC Fu on 1/31/25.
//

import Foundation
import SwiftData

@Model
final class Document {
    var id: UUID
    var fileName: String
    var fileType: String
    var fileSize: Int64
    var uploadDate: Date
    var localPath: String
    var isProcessed: Bool
    var chunks: [DocumentChunk]?
    
    init(fileName: String, fileType: String, fileSize: Int64, localPath: String) {
        self.id = UUID()
        self.fileName = fileName
        self.fileType = fileType
        self.fileSize = fileSize
        self.uploadDate = Date()
        self.localPath = localPath
        self.isProcessed = false
        self.chunks = []
    }
}

@Model
final class DocumentChunk {
    var id: UUID
    var content: String
    var embedding: [Float]?
    var document: Document?
    var similarity: Float?
    
    init(content: String) {
        self.id = UUID()
        self.content = content
        self.embedding = nil
        self.similarity = nil
    }
}