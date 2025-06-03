//
//  ContentView.swift
//  LumiReader
//
//  Created by jolin on 2025/5/31.
//

import SwiftUI
import CoreData

enum TabType {
    case articleList, summary, aiChat, settings
}

struct ContentView: View {
    @State private var selectedTab: TabType = .articleList
    @State private var selectedArticleForChat: Article? = nil

    var body: some View {
        TabView(selection: $selectedTab) {
            ArticleListView(selectedTab: $selectedTab, selectedArticleForChat: $selectedArticleForChat)
                .tabItem {
                    Label("文章列表", systemImage: "list.bullet.rectangle")
                }
                .tag(TabType.articleList)
            
            SummaryView(selectedTab: $selectedTab, selectedArticleForChat: $selectedArticleForChat)
                .tabItem {
                    Label("内容总结", systemImage: "doc.text.magnifyingglass")
                }
                .tag(TabType.summary)
            
            AIChatView(article: $selectedArticleForChat)
                .tabItem {
                    Label("AI对话", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(TabType.aiChat)
            
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
                .tag(TabType.settings)
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
