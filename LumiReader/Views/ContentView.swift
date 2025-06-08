//
//  ContentView.swift
//  LumiReader
//
//  Created by jolin on 2025/5/31.
//

import SwiftUI
import CoreData

enum TabType {
    case source, summary, aiChat, settings
}

struct ContentView: View {
    @State private var selectedTabIndex: Int = 0
    @State private var selectedTab: TabType = .source
    @State private var selectedArticleForChat: Article? = nil
    @State private var aiChatButtonOffset: CGSize = .zero
    let tabTitles = ["来源", "总结", "对话", "设置"]

    var body: some View {
        VStack(spacing: 0) {
            // 内容区：可左右滑动
            TabView(selection: $selectedTabIndex) {
                SourceView(selectedTab: $selectedTab, selectedArticleForChat: $selectedArticleForChat).tag(0)
                SummaryView(selectedTab: $selectedTab, selectedArticleForChat: $selectedArticleForChat).tag(1)
                AIChatView(article: $selectedArticleForChat, selectedTab: $selectedTab, previousTabType: nil, dragOffset: $aiChatButtonOffset).tag(2)
                SettingsView().tag(3)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

            Divider()

            // 底部自定义TabBar
            HStack {
                ForEach(tabTitles.indices, id: \.self) { idx in
                    Button(action: { selectedTabIndex = idx }) {
                        Text(tabTitles[idx])
                            .fontWeight(selectedTabIndex == idx ? .bold : .regular)
                            .foregroundColor(selectedTabIndex == idx ? .blue : .primary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(selectedTabIndex == idx ? Color(.systemGray5) : Color.clear)
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
