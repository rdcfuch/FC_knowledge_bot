//
//  DocumentProcessor.swift
//  FC_knowledge_bot
//
//  Created by FC Fu on 1/31/25.
//

import Foundation
import SwiftData

class DocumentProcessor {
    private let apiKey: String
    private let chunkSize = 1000
    private let chunkOverlap = 200
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func processDocument(_ document: Document) async throws {
        let content = try await readDocument(document)
        let chunks = splitIntoChunks(content)
        try await generateEmbeddings(for: chunks, in: document)
    }
    
    private func readDocument(_ document: Document) async throws -> String {
        let fileURL = URL(fileURLWithPath: document.localPath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
    
    private func splitIntoChunks(_ text: String) -> [String] {
        var chunks: [String] = []
        let words = text.split(separator: " ")
        var currentChunk: [String] = []
        var currentLength = 0
        
        for word in words {
            let wordLength = word.count
            if currentLength + wordLength > chunkSize {
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk.joined(separator: " "))
                    
                    // Keep last few words for overlap
                    let overlapWords = Array(currentChunk.suffix(chunkOverlap))
                    currentChunk = overlapWords
                    currentLength = overlapWords.joined(separator: " ").count
                }
            }
            currentChunk.append(String(word))
            currentLength += wordLength + 1 // +1 for space
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: " "))
        }
        
        return chunks
    }
    
    private func generateEmbeddings(for chunks: [String], in document: Document) async throws {
        let url = URL(string: "https://api.openai.com/v1/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        document.chunks = []
        
        for chunk in chunks {
            let requestBody: [String: Any] = [
                "model": "text-embedding-ada-002",
                "input": chunk
            ]
            
            request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "DocumentProcessor", code: 1,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let errorMessage = (errorJson?["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
                throw NSError(domain: "DocumentProcessor", code: httpResponse.statusCode,
                             userInfo: [NSLocalizedDescriptionKey: "OpenAI API Error: \(errorMessage)"])
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let data = json?["data"] as? [[String: Any]],
                  let firstEmbedding = data.first?["embedding"] as? [Double] else {
                throw NSError(domain: "DocumentProcessor", code: 1,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid embedding format"])
            }
            
            let documentChunk = DocumentChunk(content: chunk)
            documentChunk.embedding = firstEmbedding.map { Float($0) }
            documentChunk.document = document
            document.chunks?.append(documentChunk)
            
            // Add a small delay to avoid rate limiting
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        }
    }
    
    func searchSimilarChunks(query: String, limit: Int = 3) async throws -> [DocumentChunk] {
        let url = URL(string: "https://api.openai.com/v1/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": "text-embedding-ada-002",
            "input": query
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embeddingData = json["data"] as? [[String: Any]],
              let queryEmbedding = embeddingData.first?["embedding"] as? [Double] else {
            throw NSError(domain: "DocumentProcessor", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to generate query embedding"])
        }
        
        // Convert query embedding to Float for comparison
        let queryVector = queryEmbedding.map { Float($0) }
        
        // Get all chunks from the database
        let context = try ModelContext(.init(for: Document.self))
        let descriptor = FetchDescriptor<DocumentChunk>()
        let chunks = try context.fetch(descriptor)
        
        // Calculate cosine similarity and sort chunks
        let rankedChunks = chunks.compactMap { chunk -> (DocumentChunk, Float)? in
            guard let embedding = chunk.embedding else { return nil }
            let similarity = cosineSimilarity(queryVector, embedding)
            return (chunk, similarity)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map { $0.0 }
        
        return Array(rankedChunks)
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        
        return dotProduct / (normA * normB)
    }
}