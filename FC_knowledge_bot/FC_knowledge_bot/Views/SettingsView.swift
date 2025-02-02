import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss: DismissAction
    @Binding var apiKey: String
    @State private var tempApiKey: String = ""
    @State private var deepseekApiKey: String = ""
    @State private var selectedModel: String = "deepseek-chat"
    @State private var isValidating = false
    @State private var isValidatingDeepseek = false
    @State private var validationError: String? = nil
    @State private var deepseekValidationError: String? = nil
    @State private var isRefreshing = false
    @State private var refreshError: String? = nil
    
    private let availableModels = [
        "deepseek-chat",
        "deepseek-coder"
    ]
    
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
                
                Section(header: Text("DeepSeek Settings")) {
                    SecureField("Enter DeepSeek API Key", text: $deepseekApiKey)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    if let error = deepseekValidationError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Button(action: validateAndSaveDeepseekKey) {
                        HStack {
                            Text("Save DeepSeek Key")
                            if isValidatingDeepseek {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(deepseekApiKey.isEmpty || isValidatingDeepseek)
                    
                    Picker("Select Model", selection: $selectedModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .onChange(of: selectedModel) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "selected_model")
                    }
                }
                
                Section {
                    Text("Your API keys are stored securely in the system keychain and are only used for communicating with the respective APIs.")
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
                deepseekApiKey = UserDefaults.standard.string(forKey: "deepseek_api_key") ?? ""
                selectedModel = UserDefaults.standard.string(forKey: "selected_model") ?? "deepseek-chat"
            }
        }
    }
    
    private func validateAndSaveKey() {
        isValidating = true
        validationError = nil
        
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
    
    private func validateAndSaveDeepseekKey() {
        isValidatingDeepseek = true
        deepseekValidationError = nil
        
        let url = URL(string: "https://api.deepseek.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer " + deepseekApiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let testBody: [String: Any] = [
            "model": "deepseek-chat",
            "messages": [
                ["role": "user", "content": "test"]
            ],
            "max_tokens": 5
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: testBody)
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                isValidatingDeepseek = false
                
                if let error = error {
                    deepseekValidationError = "Network error: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case 200...299:
                        UserDefaults.standard.set(deepseekApiKey, forKey: "deepseek_api_key")
                        UserDefaults.standard.set("deepseek-chat", forKey: "selected_model")
                    case 401:
                        deepseekValidationError = "Invalid DeepSeek API key"
                    default:
                        deepseekValidationError = "Unexpected error (HTTP \(httpResponse.statusCode))"
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
                let schema = Schema([Document.self, DocumentChunk.self, ManualText.self])
                let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                let context = ModelContext(container)
                
                // Delete only the chunks (vector database contents)
                let chunkDescriptor = FetchDescriptor<DocumentChunk>()
                let chunks = try context.fetch(chunkDescriptor)
                chunks.forEach { context.delete($0) }
                
                // Process documents
                let documentDescriptor = FetchDescriptor<Document>()
                let documents = try context.fetch(documentDescriptor)
                
                // Process manual texts
                let manualTextDescriptor = FetchDescriptor<ManualText>()
                let manualTexts = try context.fetch(manualTextDescriptor)
                
                let processor = DocumentProcessor(apiKey: apiKey)
                
                // Process each document
                for document in documents {
                    // Check if the file exists
                    let fileManager = FileManager.default
                    if !fileManager.fileExists(atPath: document.localPath) {
                        continue // Skip if file doesn't exist, but don't delete the document
                    }
                    
                    // Reset document's processing state
                    document.chunks = []
                    document.isProcessed = false
                    
                    // Process the document
                    try await processor.processDocument(document)
                    document.isProcessed = true
                }
                
                // Process each manual text
                for text in manualTexts {
                    // Split content into chunks and generate embeddings
                    let chunks = processor.splitIntoChunks(text.content)
                    
                    for chunk in chunks {
                        let embedding = try await processor.getEmbedding(for: chunk)
                        let documentChunk = DocumentChunk(content: chunk)
                        documentChunk.embedding = embedding
                        context.insert(documentChunk)
                    }
                }
                
                // Save context to persist changes
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