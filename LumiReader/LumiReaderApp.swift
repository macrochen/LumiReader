//
//  LumiReaderApp.swift
//  LumiReader
//
//  Created by jolin on 2025/5/31.
//

import SwiftUI
import GoogleSignIn

@main
struct LumiReaderApp: App {
    init() {
        // 配置Google Sign-In
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String else {
            fatalError("No Google Client ID found in Info.plist")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
