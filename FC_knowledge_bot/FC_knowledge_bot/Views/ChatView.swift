//
//  ChatView.swift
//  FC_knowledge_bot
//
//  Created by FC Fu on 1/31/25.
//

import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var chats: [Chat]
    @State private var messageText = ""
    @State private var selectedChat: Chat?
    @State private var showSettings = false
    @State private var showDocumentPicker = false
    @AppStorage("openai_api_key") private var apiKey = ""
    private let vectorStore = VectorStore()
    
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
        guard !apiKey.isEmpty else {
            let errorChat = selectedChat ?? Chat(title: "Error")
            if selectedChat == nil {
                modelContext.insert(errorChat)
                selectedChat = errorChat
            }
            let errorMessage = ChatMessage(content: "Error: OpenAI API key is not set. Please set it in Settings.", isUserMessage: false)
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
        
        // Store the message text and clear the input
        let userMessage = messageText
        messageText = ""
        
        print("\n[User Message] \(userMessage)")
        
        // Search for relevant document chunks
        let processor = DocumentProcessor(apiKey: apiKey)
        Task {
            do {
                // Get embeddings for the user message
                let embedding = try await processor.getEmbedding(for: userMessage)
                print("\n[Vector Search Debug] User message: \(userMessage)")
                print("[Vector Search Debug] Query embedding size: \(embedding.count)")
                
                // Debug: List all contents in vector DB before search
                print("\n[VectorDB Contents Before Search]")
                let descriptor = FetchDescriptor<DocumentChunk>()
                let chunks = try modelContext.fetch(descriptor)
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
                
                // Search for similar chunks using VectorStore
                print("\n[Vector Search Debug] Starting similarity search...")
                let similarChunks = try vectorStore.searchSimilar(queryEmbedding: embedding, maxResults: 5)
                print("\n[Vector Search Results] Found \(similarChunks.count) similar chunks")
                
                for (index, chunk) in similarChunks.enumerated() {
                    print("\nChunk #\(index + 1)")
                    print("Content: \(chunk.content)")
                    if let similarity = chunk.similarity {
                        print("Similarity score: \(similarity)")
                    }
                    if let embedding = chunk.embedding {
                        print("Embedding size: \(embedding.count)")
                    }
                }
                
                // Construct context message from similar chunks
                let contextMessage = "Context from relevant documents:\n" + (similarChunks.map { "\n" + $0.content }.joined())
                
                // // List all contents in vector DB
                // listVectorDBContents()
                
                print("\n[Context Message]\n\(contextMessage)")
                
                // Send message to OpenAI API
                let url = URL(string: "https://api.openai.com/v1/chat/completions")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 30
                request.networkServiceType = .responsiveData
                
                let messages = newChat.messages?.map { [
                    "role": $0.isUserMessage ? "user" : "assistant",
                    "content": $0.content
                ] } ?? []
                
                // Create a mutable copy and add context message
                var finalMessages = messages
                finalMessages.append(["role": "system", "content": contextMessage])
                
                print("\n[OpenAI Messages]")
                print("Chat History: \(messages)")
                print("Context Message: \(contextMessage)")
                print("Final Messages: \(finalMessages)")
                
                let requestBody: [String: Any] = [
                    "model": "gpt-4o-mini",
                    "messages": finalMessages,
                    "temperature": 0.7,
                    "max_tokens": 2000
                ]
                
                request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "ChatView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
                }
                
                guard httpResponse.statusCode == 200 else {
                    let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let errorMessage = (errorJson?["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
                    throw NSError(domain: "ChatView", code: httpResponse.statusCode, 
                                 userInfo: [NSLocalizedDescriptionKey: "OpenAI API Error: \(errorMessage)"])
                }
                
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                print("\n[OpenAI Response]\n\(String(describing: json))")
                
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
                    
                    // Print manual texts information after chat completion
                    print("\n[Manual Texts List after Chat]")
                    let fileManager = ManualTextFileManager.shared
                    let manualTexts = fileManager.getAllTexts()
                    print("Total manual texts: \(manualTexts.count)")
                    
                    for (index, (metadata, content)) in manualTexts.enumerated() {
                        print("\nText #\(index + 1)")
                        print("Title: \(metadata.title)")
                        print("Content: \(content.prefix(100))...")
                        print("Last modified: \(metadata.lastModifiedAt)")
                    }
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
