import SwiftUI
import SwiftData
import UniformTypeIdentifiers


struct DocumentListItemView: View {
    let document: Document
    let isProcessing: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(document.fileName)
                    .lineLimit(1)
                Text(document.localPath)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.7)
            } else if document.isProcessed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
    }
}

struct ManualTextListItemView: View {
    let metadata: TextMetadata
    let content: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(metadata.title)
                .lineLimit(1)
            Text(content.prefix(50))
                .font(.caption)
                .foregroundColor(.gray)
            Text(metadata.lastModifiedAt, style: .date)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

struct DocumentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var manualTexts: [(TextMetadata, String)] = []
    @Query private var documents: [Document]
    @State private var showManualInput = false
    @State private var showFilePicker = false
    @State private var processingDocuments: Set<String> = []
    
    private let fileManager = ManualTextFileManager.shared
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Documents")) {
                    Button(action: { showFilePicker.toggle() }) {
                        Label("Import Document", systemImage: "doc.badge.plus")
                    }
                    
                    ForEach(documents) { document in
                        DocumentListItemView(document: document, isProcessing: processingDocuments.contains(document.id.uuidString))
                    }
                    .onDelete(perform: deleteDocuments)
                }
                
                Section(header: Text("Manual Texts")) {
                    ForEach(manualTexts.indices, id: \.self) { index in
                        let (metadata, content) = manualTexts[index]
                        NavigationLink(destination: ManualInputView(editingId: metadata.id)) {
                            ManualTextListItemView(metadata: metadata, content: content)
                        }
                    }
                    .onDelete(perform: deleteManualTexts)
                }
                
                Section(header: Text("Manual Input")) {
                    Button(action: { showManualInput.toggle() }) {
                        Label("Add Knowledge", systemImage: "square.and.pencil")
                    }
                }
            }
            .navigationTitle("Knowledge Management")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Knowledge Management")
                        .font(.headline)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                manualTexts = fileManager.getAllTexts()
                print("\n[Manual Texts List]")
                print("Total manual texts: \(manualTexts.count)")
                
                for (index, (metadata, content)) in manualTexts.enumerated() {
                    print("\nText #\(index + 1)")
                    print("Title: \(metadata.title)")
                    print("Content: \(content.prefix(100))...")
                    print("Last modified: \(metadata.lastModifiedAt)")
                }
            }
            .sheet(isPresented: $showManualInput) {
                NavigationView {
                    ManualInputView()
                        .modelContainer(modelContext.container)
                }
            }
            .onChange(of: showManualInput) { _, isShowing in
                if !isShowing {
                    // Refresh manual texts when sheet is dismissed
                    manualTexts = fileManager.getAllTexts()
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.text, .plainText, .pdf],
                allowsMultipleSelection: true
            ) { result in
                Task {
                    do {
                        let urls = try result.get()
                        for url in urls {
                            guard url.startAccessingSecurityScopedResource() else { continue }
                            defer { url.stopAccessingSecurityScopedResource() }
                            
                            let filename = url.lastPathComponent
                            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            let destinationURL = documentsDirectory.appendingPathComponent(filename)
                            
                            try? FileManager.default.removeItem(at: destinationURL)
                            try FileManager.default.copyItem(at: url, to: destinationURL)
                            
                            let document = Document(fileName: filename, fileType: url.pathExtension, fileSize: (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0, localPath: destinationURL.path)
                            modelContext.insert(document)
                            try modelContext.save()
                            
                            processingDocuments.insert(document.id.uuidString)
                            
                            let processor = DocumentProcessor(apiKey: UserDefaults.standard.string(forKey: "openai_api_key") ?? "")
                            try await processor.processDocument(document) { progress in
                                print("Processing progress: \(progress)")
                            }
                            
                            // Save document chunks to SwiftData
                            if let chunks = document.chunks {
                                for chunk in chunks {
                                    modelContext.insert(chunk)
                                }
                            }
                            
                            document.isProcessed = true
                            try modelContext.save()
                            print("\n[Document Processing] Saved document chunks to SwiftData")
                            print("Document ID: \(document.id)")
                            print("Total chunks: \(document.chunks?.count ?? 0)")
                            processingDocuments.remove(document.id.uuidString)
                        }
                    } catch {
                        print("Error importing documents: \(error)")
                    }
                }
            }
        }
    }
    
    private func deleteManualTexts(at offsets: IndexSet) {
        for index in offsets {
            let (metadata, _) = manualTexts[index]
            try? fileManager.deleteText(id: metadata.id)
        }
        // Refresh the list
        manualTexts = fileManager.getAllTexts()
    }
    
    private func deleteDocuments(at offsets: IndexSet) {
        for index in offsets {
            let document = documents[index]
            
            // Delete the local file
            try? FileManager.default.removeItem(atPath: document.localPath)
            
            // Delete associated chunks from vector database
            let descriptor = FetchDescriptor<DocumentChunk>()
            if let chunks = try? modelContext.fetch(descriptor) {
                let documentChunks = chunks.filter { $0.document?.id == document.id }
                
                // Remove chunks from both SwiftData and vector store
                let vectorStore = VectorStore()
                for chunk in documentChunks {
                    // Delete from vector store
                    try? vectorStore.deleteChunk(id: chunk.id)
                    
                    // Delete from SwiftData
                    modelContext.delete(chunk)
                }
            }
            
            // Delete from SwiftData
            modelContext.delete(document)
            
            try? modelContext.save()
        }
    }
}

#Preview {
    let schema = Schema([
        Document.self,
        DocumentChunk.self,
        Chat.self,
        ChatMessage.self,
        ManualText.self
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    
    return DocumentPickerView()
        .modelContainer(container)
}