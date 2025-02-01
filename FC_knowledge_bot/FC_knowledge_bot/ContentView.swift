//
//  ContentView.swift
//  FC_knowledge_bot
//
//  Created by FC Fu on 1/31/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        ChatView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Document.self, Chat.self, ChatMessage.self, DocumentChunk.self], inMemory: true)
}
