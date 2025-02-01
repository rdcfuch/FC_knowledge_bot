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
    let schema = Schema([
        Document.self,
        DocumentChunk.self,
        Chat.self,
        ChatMessage.self,
        ManualText.self
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    
    return ContentView()
        .modelContainer(container)
}
