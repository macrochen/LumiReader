//
//  LumiReaderApp.swift
//  LumiReader
//
//  Created by jolin on 2025/5/31.
//

import SwiftUI

@main
struct LumiReaderApp: App {
    // Initialize PersistenceController and get the viewContext
    let persistenceController = PersistenceController.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Inject the managedObjectContext into the environment
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
