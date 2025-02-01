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
        }
        .navigationTitle(editingText == nil ? "New Text" : "Edit Text")
        .navigationBarItems(
            leading: Button("Cancel") { dismiss() },
            trailing: Button("Save") { saveText() }
                .disabled(!hasChanges || (title.isEmpty && content.isEmpty))
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
                let embedding = try await processor.getEmbedding(for: content)
                
                // Create and save document chunk directly using SwiftData
                let chunk = DocumentChunk(content: content)
                chunk.embedding = embedding
                modelContext.insert(chunk)
                try? modelContext.save()
            } catch {
                print("Error updating vector database: \(error)")
            }
        }
        
        dismiss()
    }
}

#Preview {
    NavigationView {
        ManualInputView()
            .modelContainer(for: ManualText.self, inMemory: true)
    }
}