//
//  ContentView.swift
//  LumiReader
//
//  Created by jolin on 2025/5/31.
//

import SwiftUI
import CoreData

enum TabType: Int {
    case source = 0
    case summary = 1
    case aiChat = 2
    case settings = 3
}

struct ContentView: View {
    // MARK: - 修改：使用 TabType 作为主要状态，它与 TabView 的 selection 绑定
    @State private var selectedTab: TabType = .source
    @State private var selectedArticleForChat: Article? = nil
    @State private var aiChatButtonOffset: CGSize = .zero
    let tabTitles = ["来源", "总结", "对话", "设置"]

    var body: some View {
        VStack(spacing: 0) {
            // 内容区：可左右滑动
            // MARK: - 修改：直接将 TabView 的 selection 绑定到 $selectedTab
            TabView(selection: $selectedTab) {
                SourceView(selectedTab: $selectedTab, selectedArticleForChat: $selectedArticleForChat)
                    .tag(TabType.source)
                SummaryView(selectedTab: $selectedTab, selectedArticleForChat: $selectedArticleForChat)
                    .tag(TabType.summary)
                AIChatView(article: $selectedArticleForChat, selectedTab: $selectedTab, previousTabType: nil, dragOffset: $aiChatButtonOffset)
                    .tag(TabType.aiChat)
                SettingsView()
                    .tag(TabType.settings)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

            Divider()

            // 底部自定义TabBar
            HStack {
                // MARK: - 修改：根据 TabType 来创建按钮和设置动作
                ForEach(Array(zip(tabTitles, [TabType.source, .summary, .aiChat, .settings])), id: \.0) { title, tab in
                    Button(action: { selectedTab = tab }) {
                        Text(title)
                            .fontWeight(selectedTab == tab ? .bold : .regular)
                            .foregroundColor(selectedTab == tab ? .blue : .primary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(selectedTab == tab ? Color(.systemGray5) : Color.clear)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
    }
}

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
