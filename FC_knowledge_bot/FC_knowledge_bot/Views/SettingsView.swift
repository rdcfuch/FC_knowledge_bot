import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var apiKey: String
    @State private var tempApiKey: String = ""
    @State private var isValidating = false
    @State private var validationError: String? = nil
    @State private var isRefreshing = false
    @State private var refreshError: String? = nil
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("OpenAI API Key")) {
                    SecureField("Enter API Key", text: $tempApiKey)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    if let error = validationError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Button(action: validateAndSaveKey) {
                        HStack {
                            Text("Save Key")
                            if isValidating {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(tempApiKey.isEmpty || isValidating)
                }
                
                Section {
                    Text("Your API key is stored securely in the system keychain and is only used for communicating with OpenAI's API.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Section(header: Text("Knowledge Base")) {
                    Button(action: refreshKnowledgeBase) {
                        HStack {
                            Text("Refresh Knowledge Base")
                            if isRefreshing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRefreshing)
                    
                    if let refreshError {
                        Text(refreshError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Text("This will rebuild the knowledge base by reprocessing all documents and manual texts.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .onAppear {
                tempApiKey = apiKey
            }
        }
    }
    
    private func validateAndSaveKey() {
        isValidating = true
        validationError = nil
        
        // Create a test request to validate the API key
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer " + tempApiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let testBody: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "user", "content": "test"]
            ],
            "max_tokens": 5
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: testBody)
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                isValidating = false
                
                if let error = error {
                    validationError = "Network error: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case 200...299:
                        apiKey = tempApiKey
                        dismiss()
                    case 401:
                        validationError = "Invalid API key"
                    default:
                        validationError = "Unexpected error (HTTP \(httpResponse.statusCode))"
                    }
                }
            }
        }.resume()
    }
    
    private func refreshKnowledgeBase() {
        isRefreshing = true
        refreshError = nil
        
        Task {
            do {
                // Get all documents from the database
                let schema = Schema([Document.self, DocumentChunk.self])
                let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                let context = ModelContext(container)
                
                // Fetch all documents
                let descriptor = FetchDescriptor<Document>()
                let documents = try context.fetch(descriptor)
                
                // Delete all chunks
                let chunkDescriptor = FetchDescriptor<DocumentChunk>()
                let chunks = try context.fetch(chunkDescriptor)
                chunks.forEach { context.delete($0) }
                
                // Process each document
                for document in documents {
                    // Check if the file exists
                    let fileManager = FileManager.default
                    if !fileManager.fileExists(atPath: document.localPath) {
                        // If file doesn't exist, delete the document from database
                        context.delete(document)
                        continue
                    }
                    
                    document.chunks = []
                    document.isProcessed = false
                    
                    let processor = DocumentProcessor(apiKey: apiKey)
                    try await processor.processDocument(document)
                    document.isProcessed = true
                }
                
                // Save context to persist document deletions
                try context.save()
                
                await MainActor.run {
                    isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    isRefreshing = false
                    refreshError = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}