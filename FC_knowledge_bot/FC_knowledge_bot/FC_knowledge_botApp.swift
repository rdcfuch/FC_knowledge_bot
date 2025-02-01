//
//  FC_knowledge_botApp.swift
//  FC_knowledge_bot
//
//  Created by FC Fu on 1/31/25.
//

import SwiftUI
import SwiftData

@main
struct FC_knowledge_botApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Document.self,
            DocumentChunk.self,
            Chat.self,
            ChatMessage.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
