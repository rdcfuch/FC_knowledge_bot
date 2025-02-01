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
                    Text("ChatGPT 4o")
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
                                    Text("Create an image")
                                        .foregroundColor(.primary)
                                    Text("for my presentation")
                                        .foregroundColor(.gray)
                                    Spacer()
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                            
                            Button(action: {}) {
                                HStack {
                                    Text("Help me understand")
                                        .foregroundColor(.primary)
                                    Text("a technical document")
                                        .foregroundColor(.gray)
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
                        Button(action: {}) {
                            Image(systemName: "plus")
                                .foregroundColor(.primary)
                        }
                        Button(action: {}) {
                            Image(systemName: "globe")
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
                let manualInputText = UserDefaults.standard.string(forKey: "manual_input_text") ?? ""
                let contextMessage = userMessage + "\n\nRelevant context:\n---\n" + manualInputText
                
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
                
                print("\n[OpenAI Messages]\n\(messages)")
                
                let requestBody: [String: Any] = [
                    "model": "gpt-3.5-turbo",
                    "messages": messages + [["role": "user", "content": contextMessage]],
                    "temperature": 0.7
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
                }
            } catch {
                await MainActor.run {
                    let errorMessage = ChatMessage(content: "Error: \(error.localizedDescription)", isUserMessage: false)
                    newChat.messages?.append(errorMessage)
                }
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
