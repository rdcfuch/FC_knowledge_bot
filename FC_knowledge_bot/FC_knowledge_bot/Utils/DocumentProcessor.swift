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
    
    typealias ProgressCallback = (Double) -> Void
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func processDocument(_ document: Document, progressCallback: @escaping ProgressCallback = { _ in }) async throws {
        await MainActor.run {
            document.chunks = []
        }
        progressCallback(0.1)
        let content = try await readDocument(document)
        progressCallback(0.2)
        let chunks = splitIntoChunks(content)
        try await generateEmbeddings(for: chunks, in: document, progressCallback: progressCallback)
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
    
    private func generateEmbeddings(for chunks: [String], in document: Document, progressCallback: @escaping ProgressCallback) async throws {
        // Start from 30% progress
        progressCallback(0.3)
        
        let startTime = Date()
        var successfulChunks = 0
        var failedChunks = 0
        
        print("\n[Embedding Generation Started]")
        print("Total chunks to process: \(chunks.count)")
        let totalChunks = Double(chunks.count)
        
        for (index, chunk) in chunks.enumerated() {
            print("\n[Processing Chunk \(index + 1)/\(chunks.count)]")
            print("Chunk size: \(chunk.count) characters")
            
            do {
                // Create and initialize the document chunk on the main thread
                let documentChunk = await MainActor.run {
                    let chunk = DocumentChunk(content: chunk)
                    chunk.document = document
                    document.chunks?.append(chunk)
                    return chunk
                }
                
                // Get embedding with retry mechanism
                var embedding: [Float]? = nil
                var retryCount = 0
                let maxRetries = 3
                
                let chunkStartTime = Date()
                
                while embedding == nil && retryCount < maxRetries {
                    do {
                        print("Attempt \(retryCount + 1) to get embedding")
                        embedding = try await getEmbedding(for: chunk)
                        
                        let processingTime = Date().timeIntervalSince(chunkStartTime)
                        print("Embedding generated successfully in \(String(format: "%.2f", processingTime))s")
                        successfulChunks += 1
                        
                        // Create a local copy of the embedding for thread-safe access
                        let finalEmbedding = embedding
                        // Update the embedding on the main thread
                        await MainActor.run {
                            documentChunk.embedding = finalEmbedding
                        }
                        
                        if let embeddingSize = embedding?.count {
                            print("Embedding vector size: \(embeddingSize)")
                        }
                        
                        break // Exit the retry loop on success
                    } catch {
                        retryCount += 1
                        print("Embedding attempt \(retryCount) failed: \(error.localizedDescription)")
                        
                        if retryCount >= maxRetries {
                            failedChunks += 1
                            throw error
                        }
                        print("Waiting 1 second before retry...")
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay between retries
                    }
                }
                
                // Calculate progress from 30% to 90%
                let progress = 0.3 + (0.6 * (Double(index + 1) / totalChunks))
                progressCallback(progress)
                
                print("Adding delay between API calls to avoid rate limiting...")
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            } catch {
                print("\n[ERROR] Failed to process chunk \(index)")
                print("Error details: \(error)")
                throw error
            }
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        print("\n[Embedding Generation Summary]")
        print("Total processing time: \(String(format: "%.2f", totalTime))s")
        print("Successfully processed chunks: \(successfulChunks)")
        print("Failed chunks: \(failedChunks)")
        print("Average time per chunk: \(String(format: "%.2f", totalTime/Double(chunks.count)))s")
        
        // Save the context to persist the changes
        await MainActor.run {
            let context = document.modelContext
            try? context?.save()
        }
        
        progressCallback(1.0) // Complete the progress
    }
    
    func getEmbedding(for text: String) async throws -> [Float] {
        print("\n[Embedding API Request]")
        print("Input text length: \(text.count) characters")
        
        let startTime = Date()
        let url = URL(string: "https://api.openai.com/v1/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": "text-embedding-ada-002",
            "input": text
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        print("Sending request to OpenAI API...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let requestTime = Date().timeIntervalSince(startTime)
        print("API request completed in \(String(format: "%.2f", requestTime))s")
        
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
        
        return firstEmbedding.map { Float($0) }
    }
    
    func searchSimilarChunks(query: String, limit: Int = 3) async throws -> [DocumentChunk] {
        let queryEmbedding = try await getEmbedding(for: query)
        
        // Get all chunks from the database on the main thread
        return try await MainActor.run {
            let schema = Schema([Document.self, DocumentChunk.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<DocumentChunk>()
            let chunks = try context.fetch(descriptor)
            
            // Debug: Print all chunks in the database
            print("\nVector Database Contents:")
            print("Total chunks found: \(chunks.count)")
            for (index, chunk) in chunks.enumerated() {
                print("\nChunk \(index + 1):")
                print("Content: \(chunk.content)")
                print("Has embedding: \(chunk.embedding != nil)")
                if let embedding = chunk.embedding {
                    print("Embedding size: \(embedding.count)")
                    print("First 5 values: \(embedding.prefix(5))")
                }
            }
            
            // Calculate cosine similarity and sort chunks
            let rankedChunks = chunks.compactMap { chunk -> (DocumentChunk, Float)? in
                guard let embedding = chunk.embedding else { return nil }
                let similarity = self.cosineSimilarity(queryEmbedding.map { Float($0) }, embedding)
                return (chunk, similarity)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
            
            return Array(rankedChunks)
        }
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        
        return dotProduct / (normA * normB)
    }
}