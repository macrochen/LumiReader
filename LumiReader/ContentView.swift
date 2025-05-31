//
//  ContentView.swift
//  LumiReader
//
//  Created by jolin on 2025/5/31.
//

import SwiftUI
import CoreData

struct ContentView: View {
    var body: some View {
        TabView {
            ArticleListView()
                .tabItem {
                    Label("文章列表", systemImage: "list.bullet")
                }
            
            ContentSummaryView()
                .tabItem {
                    Label("内容总结", systemImage: "doc.text")
                }
            
            AIChatView()
                .tabItem {
                    Label("AI对话", systemImage: "bubble.left.and.bubble.right")
                }
            
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
        }
    }
}

// 预览
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()
