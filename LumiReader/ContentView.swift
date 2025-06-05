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

    // 【新增】状态变量，用于跟踪进入 AI 对话 Tab 之前所在的 Tab
    @State private var previousTabType: TabType? = nil

    // 【新增】状态变量，用于存储 AI 对话浮窗的拖动偏移量
    // 【修改】设置浮窗的初始垂直偏移量，使其靠近屏幕右侧中间
    @State private var aiChatButtonOffset: CGSize = CGSize(width: 0, height: 0) // 将初始垂直偏移量设回 0，确保按钮可见

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
            
            // 【修改】将 previousTabType 和 aiChatButtonOffset 传递给 AIChatView
            // 【修正】新增 selectedTab 绑定参数
            AIChatView(article: $selectedArticleForChat, selectedTab: $selectedTab, previousTabType: previousTabType, dragOffset: $aiChatButtonOffset)
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
        // 【新增】监听 selectedTab 的变化，更新 previousTabType
        .onChange(of: selectedTab) { oldTab, newTab in
            // 当切换到 AI 对话 Tab 时，记录当前 Tab 作为 previousTabType
            if newTab == .aiChat {
                previousTabType = oldTab
                print("【Tab切换】切换到 AI 对话，previousTabType 设置为: \(oldTab)")
            } else if oldTab == .aiChat {
                // 当从 AI 对话 Tab 切换走时，清空 previousTabType
                previousTabType = nil
                print("【Tab切换】离开 AI 对话，previousTabType 已清空")
            }
        }
        // 【新增】确保在视图出现时初始化 previousTabType
        .onAppear {
            print("【ContentView】视图出现，当前 selectedTab: \(selectedTab)")
            if selectedTab == .aiChat {
                previousTabType = .articleList // 默认值
                print("【ContentView】初始化 previousTabType 为: \(previousTabType ?? .articleList)")
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
