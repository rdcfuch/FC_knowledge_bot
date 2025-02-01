import SwiftUI
import UniformTypeIdentifiers
import SwiftData

struct DocumentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isImporting = false
    @State private var isProcessing = false
    @State private var processingProgress = 0.0
    @State private var showingManualInput = false
    @AppStorage("manual_input_text") private var storedManualInputText = ""
    @State private var manualInputText = ""
    @State private var isProcessingText = false
    
    var body: some View {
        NavigationView {
            VStack {
                if isProcessing {
                    ProgressView("Processing Document", value: processingProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .padding()
                    
                    Text(String(format: "%.0f%%", processingProgress * 100))
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                        
                        Text("Select documents to upload")
                            .font(.headline)
                        
                        Text("Supported formats: PDF, TXT, DOC, DOCX")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        VStack(spacing: 12) {
                            Button(action: { isImporting = true }) {
                                Text("Choose File")
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(8)
                            }
                            
                            Button(action: showManualInputSheet) {
                                Text("Manual Input")
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.green)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Upload Document")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.pdf, .plainText, .rtf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let files):
                    guard let file = files.first else { return }
                    processDocument(file)
                case .failure(let error):
                    print("Error importing file: \(error.localizedDescription)")
                }
            }
        }
        .sheet(isPresented: $showingManualInput) {
            NavigationView {
                VStack {
                    TextEditor(text: $manualInputText)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .onChange(of: manualInputText) { oldValue, newValue in
                            storedManualInputText = newValue
                        }
                }
                .padding()
                .navigationTitle("Manual Input")
                .navigationBarItems(
                    leading: Button("Cancel") {
                        showingManualInput = false
                        manualInputText = ""
                    },
                    trailing: Button("Save") {
                        isProcessingText = true
                        processManualInput()
                    }
                    .disabled(manualInputText.isEmpty)
                )
            }
        }
    }
    
    private func showManualInputSheet() {
        manualInputText = storedManualInputText
        showingManualInput = true
    }
    
    private func processManualInput() {
        guard !manualInputText.isEmpty else {
            isProcessingText = false
            return
        }
        showingManualInput = false  // Close the sheet immediately
        isProcessing = true
        processingProgress = 0.0
        
        // Create a temporary file to store the manual input
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "manual_input_\(Date().timeIntervalSince1970).txt"
        let fileURL = documentsURL.appendingPathComponent(fileName)
        
        do {
            try manualInputText.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Create document record
            let document = Document(
                fileName: fileName,
                fileType: "txt",
                fileSize: Int64(manualInputText.utf8.count),
                localPath: fileURL.path
            )
            
            modelContext.insert(document)
            
            // Process document using DocumentProcessor
            Task {
                do {
                    let apiKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
                    guard !apiKey.isEmpty else {
                        throw NSError(domain: "DocumentProcessing", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key not found"])
                    }
                    
                    let processor = DocumentProcessor(apiKey: apiKey)
                    processingProgress = 0.3
                    
                    try await processor.processDocument(document)
                    processingProgress = 0.7
                    
                    document.isProcessed = true
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay for smooth progress
                    processingProgress = 1.0
                    
                    await MainActor.run {
                        manualInputText = ""
                        isProcessingText = false
                        dismiss()
                    }
                } catch {
                    print("Error processing document: \(error.localizedDescription)")
                    await MainActor.run {
                        isProcessing = false
                        processingProgress = 0.0
                        isProcessingText = false
                    }
                }
            }
            
        } catch {
            print("Error saving manual input: \(error.localizedDescription)")
            isProcessing = false
            processingProgress = 0.0
            isProcessingText = false
        }
    }
    
    private func processDocument(_ file: URL) {
        isProcessing = true
        
        // Copy file to app's documents directory
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsURL.appendingPathComponent(file.lastPathComponent)
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: file, to: destinationURL)
            
            // Create document record
            let document = Document(
                fileName: file.lastPathComponent,
                fileType: file.pathExtension,
                fileSize: Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0),
                localPath: destinationURL.path
            )
            
            modelContext.insert(document)
            
            // Process document using DocumentProcessor
            Task {
                do {
                    let processor = DocumentProcessor(apiKey: UserDefaults.standard.string(forKey: "openai_api_key") ?? "")
                    try await processor.processDocument(document) { progress in
                        Task { @MainActor in
                            processingProgress = progress
                        }
                    }
                    document.isProcessed = true
                    await MainActor.run {
                        isProcessing = false
                        dismiss()
                    }
                } catch {
                    print("Error processing document: \(error)")
                    await MainActor.run {
                        isProcessing = false
                    }
                }
            }
            
        } catch {
            print("Error processing document: \(error)")
            isProcessing = false
        }
    }
}