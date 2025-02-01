import Foundation
import SwiftData

class VectorStore {
    struct ChunkWithSimilarity {
        let chunk: DocumentChunk
        let similarity: Float
    }
    
    func searchSimilar(queryEmbedding: [Float], maxResults: Int = 3) throws -> [DocumentChunk] {
        let context = try ModelContext(.init(for: Document.self))
        let descriptor = FetchDescriptor<DocumentChunk>()
        
        let chunks = try context.fetch(descriptor)
        
        // Filter out chunks without embeddings
        let chunksWithEmbeddings = chunks.filter { $0.embedding != nil }
        
        // Calculate cosine similarity for each chunk
        let chunksWithSimilarity = chunksWithEmbeddings.map { chunk in
            ChunkWithSimilarity(
                chunk: chunk,
                similarity: cosineSimilarity(queryEmbedding, chunk.embedding!)
            )
        }
        
        // Sort by similarity (highest first) and take top results
        let sortedChunks = chunksWithSimilarity
            .sorted { $0.similarity > $1.similarity }
            .prefix(maxResults)
            .map { $0.chunk }
        
        return Array(sortedChunks)
    }
    
    func getAllChunks() throws -> [DocumentChunk] {
        let context = try ModelContext(.init(for: Document.self))
        let descriptor = FetchDescriptor<DocumentChunk>()
        return try context.fetch(descriptor)
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        let dotProduct = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let magnitudeA = sqrt(a.reduce(0) { $0 + $1 * $1 })
        let magnitudeB = sqrt(b.reduce(0) { $0 + $1 * $1 })
        
        guard magnitudeA > 0 && magnitudeB > 0 else { return 0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
}