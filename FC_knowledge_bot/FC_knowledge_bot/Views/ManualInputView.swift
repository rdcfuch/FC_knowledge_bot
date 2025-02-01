//
//  ManualInputView.swift
//  FC_knowledge_bot
//
//  Created by FC Fu on 1/31/25.
//

import SwiftUI

struct ManualInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var title = ""
    @State private var content = ""
    @State private var hasChanges = false
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil
    
    private let fileManager = ManualTextFileManager.shared
    private var editingId: UUID?
    
    init(editingId: UUID? = nil) {
        self.editingId = editingId
        if let id = editingId,
           let (metadata, content) = try? fileManager.loadText(id: id) {
            _title = State(initialValue: metadata.title)
            _content = State(initialValue: content)
        }
    }
    
    var body: some View {
        Form {
            Section(header: Text("Title")) {
                TextField("Enter title", text: $title)
                    .onChange(of: title) { _, _ in
                        updateHasChanges()
                    }
            }
            
            Section(header: Text("Content")) {
                TextEditor(text: $content)
                    .frame(minHeight: 200)
                    .onChange(of: content) { _, _ in
                        updateHasChanges()
                    }
            }
            
            if isProcessing {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Processing text...")
                        Spacer()
                    }
                }
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle(editingId == nil ? "New Text" : "Edit Text")
        .navigationBarItems(
            leading: Button("Cancel") { dismiss() },
            trailing: Button("Save") { saveText() }
                .disabled(!hasChanges || (title.isEmpty && content.isEmpty) || isProcessing)
        )
    }
    
    private func updateHasChanges() {
        if let id = editingId,
           let (metadata, initialContent) = try? fileManager.loadText(id: id) {
            // For editing mode, compare with values from file
            hasChanges = title != metadata.title || content != initialContent
        } else {
            // For new text, enable save if either field is not empty
            hasChanges = !title.isEmpty || !content.isEmpty
        }
    }
    
    private func saveText() {
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                // Save text to file system
                if let id = editingId {
                    _ = try fileManager.saveText(id: id, title: title, content: content)
                } else {
                    _ = try fileManager.saveText(title: title, content: content)
                }
                
                // Update vector database
                let processor = DocumentProcessor(apiKey: UserDefaults.standard.string(forKey: "openai_api_key") ?? "")
                
                // Split content into chunks and generate embeddings
                let chunks = processor.splitIntoChunks(content)
                print("\n[Vector DB Update] Splitting content into \(chunks.count) chunks")
                
                for (index, chunk) in chunks.enumerated() {
                    print("\n[Vector DB Update] Processing chunk #\(index + 1)")
                    print("Content: \(chunk)")
                    
                    let embedding = try await processor.getEmbedding(for: chunk)
                    print("Generated embedding with size: \(embedding.count)")
                    
                    // Create and save document chunk to SwiftData
                    let documentChunk = DocumentChunk(content: chunk)
                    documentChunk.embedding = embedding
                    modelContext.insert(documentChunk)
                    try modelContext.save()
                    print("Saved chunk to vector database with embedding size: \(embedding.count)")
                    print("Chunk content: \(chunk)")
                    print("Chunk ID: \(documentChunk.id)")
                    print("ModelContext save successful")
                }
                
                print("\n[Vector DB Update] All chunks processed and saved")
                
                await MainActor.run {
                    isProcessing = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = "Error saving text: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        ManualInputView()
    }
}