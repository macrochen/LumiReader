//
//  LumiReaderApp.swift
//  LumiReader
//
//  Created by jolin on 2025/5/31.
//

import SwiftUI

@main
struct LumiReaderApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
