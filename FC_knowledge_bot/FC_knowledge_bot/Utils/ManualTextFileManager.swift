//
//  ManualTextFileManager.swift
//  FC_knowledge_bot
//
//  Created by FC Fu on 1/31/25.
//

import Foundation

struct TextMetadata: Codable {
    let id: UUID
    let title: String
    let createdAt: Date
    let lastModifiedAt: Date
}

class ManualTextFileManager {
    static let shared = ManualTextFileManager()
    
    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    private let textsDirectory: URL
    
    private init() {
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        textsDirectory = documentsDirectory.appendingPathComponent("manual_texts")
        
        try? fileManager.createDirectory(at: textsDirectory, withIntermediateDirectories: true)
    }
    
    private func getMetadataPath(for id: UUID) -> URL {
        textsDirectory.appendingPathComponent(id.uuidString + ".metadata.json")
    }
    
    private func getContentPath(for id: UUID) -> URL {
        textsDirectory.appendingPathComponent(id.uuidString + ".txt")
    }
    
    func saveText(title: String, content: String) throws -> UUID {
        let id = UUID()
        return try saveText(id: id, title: title, content: content)
    }
    
    func saveText(id: UUID, title: String, content: String) throws -> UUID {
        let metadata = TextMetadata(
            id: id,
            title: title,
            createdAt: Date(),
            lastModifiedAt: Date()
        )
        
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: getMetadataPath(for: id))
        
        try content.write(to: getContentPath(for: id), atomically: true, encoding: .utf8)
        
        return id
    }
    
    func loadText(id: UUID) throws -> (TextMetadata, String) {
        let metadataData = try Data(contentsOf: getMetadataPath(for: id))
        let metadata = try JSONDecoder().decode(TextMetadata.self, from: metadataData)
        
        let content = try String(contentsOf: getContentPath(for: id), encoding: .utf8)
        
        return (metadata, content)
    }
    
    func deleteText(id: UUID) throws {
        try fileManager.removeItem(at: getMetadataPath(for: id))
        try fileManager.removeItem(at: getContentPath(for: id))
    }
    
    func getAllTexts() -> [(TextMetadata, String)] {
        let metadataURLs = try? fileManager.contentsOfDirectory(
            at: textsDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasSuffix(".metadata.json") }
        
        return (metadataURLs ?? []).compactMap { url in
            guard let id = UUID(uuidString: url.lastPathComponent.replacingOccurrences(of: ".metadata.json", with: "")) else { return nil }
            return try? loadText(id: id)
        }
    }
}