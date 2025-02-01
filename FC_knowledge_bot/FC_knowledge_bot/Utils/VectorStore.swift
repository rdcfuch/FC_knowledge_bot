//
//  VectorStore.swift
//  FC_knowledge_bot
//
//  Created by FC Fu on 1/31/25.
//

import Foundation
import faiss

class VectorStore {
    private var index: faiss.Index?
    private var documentChunks: [DocumentChunk] = []
    private let dimension: Int = 1536  // Dimension of text-embedding-ada-002 model
    
    init() {
        // Initialize FAISS index with cosine similarity (inner product of normalized vectors)
        index = faiss.IndexFlatIP(dimension)
    }
    
    func addEmbedding(_ embedding: [Float], chunk: DocumentChunk) {
        guard let index = index else { return }
        
        // Normalize the embedding vector
        let normalizedEmbedding = normalize(embedding)
        
        // Add the normalized embedding to the FAISS index
        index.add(vectors: [normalizedEmbedding])
        
        // Store the document chunk
        documentChunks.append(chunk)
    }
    
    func searchSimilar(queryEmbedding: [Float], limit: Int = 3) -> [DocumentChunk] {
        guard let index = index else { return [] }
        
        // Normalize the query embedding
        let normalizedQuery = normalize(queryEmbedding)
        
        // Search for similar vectors
        let (distances, indices) = index.search(vectors: [normalizedQuery], k: limit)
        
        // Map the results to document chunks
        return indices[0].enumerated().compactMap { (i, idx) -> DocumentChunk? in
            guard idx >= 0 && idx < documentChunks.count else { return nil }
            return documentChunks[Int(idx)]
        }
    }
    
    private func normalize(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.map { $0 * $0 }.reduce(0, +))
        return vector.map { $0 / norm }
    }
}