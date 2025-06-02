//
//  SettingsView.swift
//  LumiReader
//
//  Created by jolin on 2025/5/31.
//

import SwiftUI
import CoreData // Import CoreData for NSManagedObjectContext
//import Models // Import shared Prompt structure and default prompts

struct SettingsView: View {
    // 示例数据
    @AppStorage("geminiApiKey") private var geminiApiKey: String = ""
    @AppStorage("batchSummaryPrompt") private var batchSummaryPrompt: String = ""
    @AppStorage("aiPromptsData") private var aiPromptsData: Data = Data()
    @State private var aiPrompts: [Prompt] = []
    @State private var editingPromptIndex: Int? = nil
    @State private var newPromptTitle: String = ""
    @State private var newPromptContent: String = ""
    
    var body: some View {
        ZStack {
            // 渐变背景
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.95, green: 0.91, blue: 1.0), Color(red: 0.91, green: 0.84, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 设置内容区
                ScrollView {
                    VStack(spacing: 20) {
                        // AI服务配置
                        SettingGroupBox(title: "AI 服务配置") {
                            VStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("API Key:")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.gray)
                                    HStack(spacing: 8) {
                                        TextField("请输入API Key", text: $geminiApiKey)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .padding(8)
                                            .background(Color.white.opacity(0.7))
                                            .cornerRadius(6)
                                            .font(.system(size: 15))
                                        Button(action: { /* 保存API Key */ }) {
                                            Text("保存")
                                                .font(.system(size: 13))
                                                .foregroundColor(.white)
                                                .padding(.vertical, 6)
                                                .padding(.horizontal, 16)
                                                .background(Color.blue)
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                                Divider().padding(.vertical, 8)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("批量总结提示词:")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.gray)
                                    TextEditor(text: $batchSummaryPrompt)
                                        .frame(minHeight: 80, maxHeight: 120)
                                        .padding(8)
                                        .background(Color.white.opacity(0.7))
                                        .cornerRadius(6)
                                        .font(.system(size: 15))
                                    HStack {
                                        Spacer()
                                        Button(action: {
                                            // 恢复默认批量总结提示词
                                            batchSummaryPrompt = ""
                                            
                                            // 恢复默认预设提示词并保存
                                            aiPrompts = []
                                            savePrompts()
                                            
                                        }) {
                                            Text("恢复默认")
                                                .font(.system(size: 13))
                                                .foregroundColor(.gray)
                                                .padding(.vertical, 6)
                                                .padding(.horizontal, 16)
                                                .background(Color(.systemGray5))
                                                .cornerRadius(8)
                                        }
                                        Button(action: { /* 保存提示词 */ }) {
                                            Text("保存")
                                                .font(.system(size: 13))
                                                .foregroundColor(.white)
                                                .padding(.vertical, 6)
                                                .padding(.horizontal, 16)
                                                .background(Color.blue)
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                            }
                        }
                        // AI对话预设提示词
                        SettingGroupBox(title: "AI对话预设提示词") {
                            VStack(spacing: 0) {
                                ForEach(aiPrompts.indices, id: \.self) { idx in
                                    SettingItem {
                                        if editingPromptIndex == idx {
                                            VStack(alignment: .leading, spacing: 8) {
                                                HStack {
                                                    TextField("提示词标题", text: Binding(
                                                        get: { aiPrompts[idx].title },
                                                        set: { aiPrompts[idx].title = $0 }
                                                    ))
                                                    .textFieldStyle(PlainTextFieldStyle())
                                                    .padding(6)
                                                    .background(Color.white.opacity(0.7))
                                                    .cornerRadius(6)
                                                    .font(.system(size: 15))
                                                    Button(action: {
                                                        editingPromptIndex = nil
                                                    }) {
                                                        Image(systemName: "checkmark")
                                                            .foregroundColor(.blue)
                                                    }
                                                }
                                                TextEditor(text: Binding(
                                                    get: { aiPrompts[idx].content },
                                                    set: { aiPrompts[idx].content = $0 }
                                                ))
                                                .frame(height: 80)
                                                .padding(6)
                                                .background(Color.white.opacity(0.7))
                                                .cornerRadius(6)
                                                .font(.system(size: 15))
                                            }
                                        } else {
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack {
                                                    Text(aiPrompts[idx].title)
                                                        .font(.system(size: 15, weight: .medium))
                                                    Spacer()
                                                    HStack(spacing: 2) {
                                                        Button(action: { editingPromptIndex = idx }) {
                                                            Image(systemName: "pencil")
                                                                .foregroundColor(.blue)
                                                        }
                                                        Button(action: { deletePrompt(at: idx) }) {
                                                            Image(systemName: "trash")
                                                                .foregroundColor(.red)
                                                        }
                                                    }
                                                }
                                                Text(aiPrompts[idx].content)
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.gray)
                                                    .lineLimit(2)
                                            }
                                        }
                                    }
                                    if idx != aiPrompts.count - 1 {
                                        Divider()
                                    }
                                }
                                SettingItem {
                                    Button(action: { addPrompt() }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "plus.circle")
                                                .font(.system(size: 16))
                                            Text("添加新提示词")
                                                .font(.system(size: 15))
                                        }
                                        .foregroundColor(.blue)
                                    }
                                }
                                HStack {
                                    Spacer()
                                    Button(action: { savePrompts() }) {
                                        Text("保存")
                                            .font(.system(size: 13))
                                            .foregroundColor(.white)
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 16)
                                            .background(Color.blue)
                                            .cornerRadius(8)
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Color.clear)
                .frame(maxHeight: .infinity)
            }
        }
        .onAppear(perform: loadPrompts)
    }
    
    // MARK: - Helper Functions
    private func savePrompts() {
        if let encoded = try? JSONEncoder().encode(aiPrompts) {
            aiPromptsData = encoded
        }
    }
    
    private func loadPrompts() {
        if let decoded = try? JSONDecoder().decode([Prompt].self, from: aiPromptsData) {
            aiPrompts = decoded
        } else {
            // Load default prompts if no data is saved
            aiPrompts = []
        }
    }
    
    private func addPrompt() {
        aiPrompts.append(Prompt(title: "", content: ""))
        editingPromptIndex = aiPrompts.count - 1
    }
    
    private func deletePrompt(at index: Int) {
        aiPrompts.remove(at: index)
    }
}

// MARK: - 分组卡片
struct SettingGroupBox<Content: View>: View {
    let title: String
    let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(Color.clear)
            content()
        }
        .background(Color.white.opacity(0.8))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.bottom, 4)
    }
}

// MARK: - 设置项
struct SettingItem<Content: View>: View {
    let content: () -> Content
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            content()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.clear)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
} 
