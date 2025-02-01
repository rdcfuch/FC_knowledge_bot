//
//  ManualInputView.swift
//  FC_knowledge_bot
//
//  Created by FC Fu on 1/31/25.
//

import SwiftUI
import SwiftData

struct ManualInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var title = ""
    @State private var content = ""
    @State private var hasChanges = false
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil
    
    var editingText: ManualText?
    
    init(editingText: ManualText? = nil) {
        self.editingText = editingText
        if let text = editingText {
            _title = State(initialValue: text.title)
            _content = State(initialValue: text.content)
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
        .navigationTitle(editingText == nil ? "New Text" : "Edit Text")
        .navigationBarItems(
            leading: Button("Cancel") { dismiss() },
            trailing: Button("Save") { saveText() }
                .disabled(!hasChanges || (title.isEmpty && content.isEmpty) || isProcessing)
        )
    }
    
    private func updateHasChanges() {
        if let existingText = editingText {
            hasChanges = title != existingText.title || content != existingText.content
        } else {
            hasChanges = !title.isEmpty || !content.isEmpty
        }
    }
    
    private func saveText() {
        isProcessing = true
        errorMessage = nil
        
        if let existingText = editingText {
            // Update existing text
            existingText.title = title
            existingText.content = content
            existingText.lastModifiedAt = Date()
        } else {
            // Create new text
            let newText = ManualText(title: title, content: content)
            modelContext.insert(newText)
        }
        
        try? modelContext.save()
        
        // Update vector database
        Task {
            do {
                let processor = DocumentProcessor(apiKey: UserDefaults.standard.string(forKey: "openai_api_key") ?? "")
                
                // Split content into chunks and generate embeddings
                let chunks = processor.splitIntoChunks(content)
                print("\n[Vector DB Update] Splitting content into \(chunks.count) chunks")
                
                for (index, chunk) in chunks.enumerated() {
                    print("\n[Vector DB Update] Processing chunk #\(index + 1)")
                    print("Content: \(chunk)")
                    
                    let embedding = try await processor.getEmbedding(for: chunk)
                    print("Generated embedding with size: \(embedding.count)")
                    
                    // Create and save document chunk directly using SwiftData
                    let documentChunk = DocumentChunk(content: chunk)
                    documentChunk.embedding = embedding
                    modelContext.insert(documentChunk)
                    print("Saved chunk to vector database")
                }
                
                try? modelContext.save()
                print("\n[Vector DB Update] All chunks processed and saved")
                
                // List all contents in vector database
                let descriptor = FetchDescriptor<DocumentChunk>()
                if let chunks = try? modelContext.fetch(descriptor) {
                    print("\n[Vector DB Contents]")
                    print("Total chunks in database: \(chunks.count)")
                    
                    for (index, chunk) in chunks.enumerated() {
                        print("\nChunk #\(index + 1)")
                        print("ID: \(chunk.id)")
                        print("Content: \(chunk.content)")
                        if let embedding = chunk.embedding {
                            print("Embedding size: \(embedding.count)")
                        } else {
                            print("No embedding found")
                        }
                    }
                }
                
                await MainActor.run {
                    isProcessing = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = "Error updating vector database: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        ManualInputView()
            .modelContainer(for: ManualText.self, inMemory: true)
    }
}