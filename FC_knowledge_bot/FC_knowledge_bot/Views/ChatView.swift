//
//  ChatView.swift
//  FC_knowledge_bot
//
//  Created by FC Fu on 1/31/25.
//

import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext: ModelContext
    @Query private var chats: [Chat]
    @State private var messageText = ""
    @State private var selectedChat: Chat?
    @State private var showSettings = false
    @State private var showDocumentPicker = false
    @AppStorage("openai_api_key") private var apiKey = ""
    @AppStorage("deepseek_api_key") private var deepseekApiKey = ""
    @AppStorage("selected_model") private var selectedModel = "deepseek-chat"
    private let vectorStore = VectorStore()
    
    private var isUsingDeepseek: Bool {
        selectedModel.hasPrefix("deepseek")
    }
    
    private var currentApiKey: String {
        isUsingDeepseek ? deepseekApiKey : apiKey
    }
    
    private var apiEndpoint: String {
        isUsingDeepseek ? "https://api.deepseek.com/v1/chat/completions" : "https://api.openai.com/v1/chat/completions"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Navigation Bar
                HStack {
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Button(action: {
                        selectedModel = isUsingDeepseek ? "gpt-4-mini" : "deepseek-chat"
                        UserDefaults.standard.set(selectedModel, forKey: "selected_model")
                    }) {
                        Image(isUsingDeepseek ? "ds" : "openai")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .scaledToFit()
                    }
                    Text("Knowledge Agent")
                        .foregroundColor(.white)
                        .font(.headline)
                    Spacer()
                    Button(action: { showDocumentPicker.toggle() }) {
                        Image(systemName: "doc.badge.plus")
                            .foregroundColor(.white)
                    }
                }
                .padding()
                .background(Color.black)
                
                // Main Content Area
                if chats.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "camera.aperture")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 50, height: 50)
                            .foregroundColor(.gray)
                        Spacer()
                        
                        // Suggestion Buttons
                        VStack(spacing: 12) {
                            Button(action: {}) {
                                HStack {
                                    Text("Ask me a question")
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                            }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                           
                    }
                        .padding(.horizontal)
                        .padding(.bottom, 80)
                }
                } else {
                    ChatDetailView(chat: selectedChat ?? chats[0])
                }
                
                // Message Input Bar
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 12) {
                        Button(action: { showDocumentPicker.toggle() }) {
                            Image(systemName: "plus")
                                .foregroundColor(.primary)
                    }
                        TextField("Message", text: $messageText)
                            .textFieldStyle(.plain)
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(messageText.isEmpty ? .gray : .blue)
                                .font(.system(size: 24))
                    }
                        .disabled(messageText.isEmpty)
                }
                    .padding()
                    .background(Color(.systemBackground))
                    .sheet(isPresented: $showSettings) {
                        SettingsView(apiKey: $apiKey)
                    }
                    .sheet(isPresented: $showDocumentPicker) {
                        DocumentPickerView()
                            .modelContainer(modelContext.container)
                    }
                }
            }
            .background(Color(.systemBackground))
            .sheet(isPresented: $showSettings) {
                SettingsView(apiKey: $apiKey)
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPickerView()
            }
        }
    }
    
    private func createNewChat() {
        let newChat = Chat(title: "New Chat")
        modelContext.insert(newChat)
        selectedChat = newChat
    }
    
    private func listVectorDBContents() {
        let vectorStore = VectorStore()
        do {
            print("\n[VectorDB Contents]")
            let allChunks = try vectorStore.getAllChunks()
            print("Total chunks: \(allChunks.count)")
            
            for (index, chunk) in allChunks.enumerated() {
                print("\nChunk #\(index + 1)")
                print("ID: \(chunk.id)")
                print("Content: \(chunk.content)")
                if let embedding = chunk.embedding {
                    print("Embedding size: \(embedding.count)")
                } else {
                    print("No embedding found")
                }
            }
        } catch {
            print("Error listing vector DB contents: \(error)")
        }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        guard !currentApiKey.isEmpty else {
            let errorChat = selectedChat ?? Chat(title: "Error")
            if selectedChat == nil {
                modelContext.insert(errorChat)
                selectedChat = errorChat
            }
            let errorMessage = ChatMessage(content: "Error: API key is not set for \(isUsingDeepseek ? "DeepSeek" : "OpenAI"). Please set it in Settings.", isUserMessage: false)
            errorChat.messages?.append(errorMessage)
            return
        }
        
        let newChat = selectedChat ?? Chat(title: messageText)
        if selectedChat == nil {
            modelContext.insert(newChat)
            selectedChat = newChat
        }
        let newMessage = ChatMessage(content: messageText, isUserMessage: true)
        newChat.messages?.append(newMessage)
        
        let userMessage = messageText
        messageText = ""
        
        print("\n[User Message] \(userMessage)")
        
        let processor = DocumentProcessor(apiKey: apiKey)
        Task {
            do {
                let embedding = try await processor.getEmbedding(for: userMessage)
                print("\n[Vector Search Debug] User message: \(userMessage)")
                print("[Vector Search Debug] Query embedding size: \(embedding.count)")
                
                let descriptor = FetchDescriptor<DocumentChunk>()
                let chunks = try modelContext.fetch(descriptor)
                print("Total chunks in database: \(chunks.count)")
                
                let similarChunks = try vectorStore.searchSimilar(queryEmbedding: embedding, maxResults: 5)
                print("\n[Vector Search Results] Found \(similarChunks.count) similar chunks")
                
                let contextMessage = "Context from relevant documents:\n" + (similarChunks.map { "\n" + $0.content }.joined())
                print("\n[Context Message]\n\(contextMessage)")
                
                let url = URL(string: apiEndpoint)!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer " + currentApiKey, forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 30
                request.networkServiceType = .responsiveData
                
                let messages = newChat.messages?.map { [
                    "role": $0.isUserMessage ? "user" : "assistant",
                    "content": $0.content
                ] } ?? []
                
                var finalMessages = messages
                finalMessages.append(["role": "system", "content": contextMessage])
                
                let requestBody: [String: Any] = [
                    "model": selectedModel,
                    "messages": finalMessages,
                    "temperature": 0.7,
                    "max_tokens": isUsingDeepseek ? 4096 : 2000,
                    "stream": false
                ]
                
                request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "ChatView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
                }
                
                guard httpResponse.statusCode == 200 else {
                    let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let errorMessage = (errorJson?["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
                    if httpResponse.statusCode == 401 {
                        throw NSError(domain: "ChatView", code: httpResponse.statusCode, 
                                     userInfo: [NSLocalizedDescriptionKey: "Invalid API key for \(isUsingDeepseek ? "DeepSeek" : "OpenAI"). Please check your settings."])
                    } else {
                        throw NSError(domain: "ChatView", code: httpResponse.statusCode, 
                                     userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorMessage)"])
                    }
                }
                
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                print("\n[API Response]\n\(String(describing: json))")
                
                guard let choices = json?["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let message = firstChoice["message"] as? [String: Any],
                      let content = message["content"] as? String else {
                    throw NSError(domain: "ChatView", code: 1, 
                                 userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
                }
                
                await MainActor.run {
                    let botMessage = ChatMessage(content: content, isUserMessage: false)
                    newChat.messages?.append(botMessage)
                }
            } catch {
                await MainActor.run {
                    let errorMessage = ChatMessage(content: "Error: \(error.localizedDescription)", isUserMessage: false)
                    newChat.messages?.append(errorMessage)
                }
            }
        }
    }

struct ChatDetailView: View {
    let chat: Chat
    @State private var messageText = ""
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(chat.messages ?? [], id: \.id) { message in
                    MessageBubble(message: message)
                }
            }
            .padding()
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUserMessage {
                Spacer()
            }
            
            Text(message.content)
                .padding(12)
                .background(message.isUserMessage ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(message.isUserMessage ? .white : .primary)
                .cornerRadius(16)
            
            if !message.isUserMessage {
                Spacer()
            }
        }
    }
}
}
