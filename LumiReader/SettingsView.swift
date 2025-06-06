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
    @AppStorage("presetPromptsData") private var presetPromptsData: Data = Data()
    @State private var presetPrompts: [Prompt] = []
    @State private var editingPromptIndex: Int? = nil
    @State private var showingNewPromptInput = false
    @State private var tempNewPromptTitle: String = ""
    @State private var tempNewPromptContent: String = ""
    @AppStorage("chatSummaryFontSize") private var chatSummaryFontSize: Double = 15.0 // 默认文字大小
    
    // MARK: - Computed Properties for Sections

    private var apiKeySettingView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API Key:")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.gray)
            HStack(spacing: 8) {
                SecureField("请输入API Key", text: $geminiApiKey)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(8)
                    .background(Color.white.opacity(0.7))
                    .cornerRadius(6)
                    .font(.system(size: 15))
            }
        }
    }

    private var batchSummaryPromptSettingView: some View {
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
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5), lineWidth: 1))
            HStack {
                Spacer()
                Button(action: {
                    // 恢复默认批量总结提示词
                    batchSummaryPrompt = Prompt.DEFAULT_BATCH_SUMMARY_PROMPT // Only reset batch summary prompt
                    
                }) {
                    Text("恢复默认")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
        }
    }

    private func displayPresetPromptRowView(prompt: Prompt, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(prompt.title)
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                HStack(spacing: 2) {
                    Button(action: { editingPromptIndex = index }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.blue)
                    }
                    Button(action: { deletePrompt(at: index) }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            Text(prompt.content)
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .lineLimit(2)
        }
    }

    private func editingPresetPromptRowView(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("提示词标题", text: Binding(
                    get: { presetPrompts[index].title },
                    set: { presetPrompts[index].title = $0 }
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
                get: { presetPrompts[index].content },
                set: { presetPrompts[index].content = $0 }
            ))
            .frame(height: 80)
            .padding(6)
            .background(Color.white.opacity(0.7))
            .cornerRadius(6)
            .font(.system(size: 15))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5), lineWidth: 1))
        }
    }

    private var aiServiceConfigSection: some View {
        VStack(spacing: 0) {
            apiKeySettingView
            Divider().padding(.vertical, 8)
            batchSummaryPromptSettingView
        }
    }

    private var displaySettingsSection: some View {
        SettingGroupBox(title: "显示设置") {
            VStack(spacing: 0) {
                SettingItem {
                    HStack {
                        Text("文字大小")
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                        Slider(value: $chatSummaryFontSize, in: 12...30, step: 1) {
                            Text("文字大小调整") // Accessibility label
                        } minimumValueLabel: {
                            Text("小")
                        } maximumValueLabel: {
                            Text("大")
                        }
                        .frame(maxWidth: 500) // 控制滑块的最大宽度
                        Text("\(Int(chatSummaryFontSize))") // 显示当前文字大小数值
                            .font(.system(size: 15))
                            .frame(width: 30, alignment: .trailing) // 固定宽度对齐数值
                    }
                }
            }
        }
    }

    private func presetPromptRowView(index: Int) -> some View {
        SettingItem {
            if editingPromptIndex == index {
                editingPresetPromptRowView(index: index)
            } else {
                displayPresetPromptRowView(prompt: presetPrompts[index], index: index)
            }
        }
    }

    private var addPresetPromptButton: some View {
        SettingItem {
            Button(action: { showingNewPromptInput = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                    Text("添加新提示词")
                        .font(.system(size: 15))
                }
                .foregroundColor(.blue)
            }
        }
    }

    private var restorePresetPromptsButton: some View {
        Button(action: {
            // Restore default preset prompts and save
            presetPrompts = Prompt.DEFAULT_PRESET_PROMPTS
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
    }

    private var savePresetPromptsButton: some View {
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

    private var newPromptInputView: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingItem {
                TextField("提示词标题", text: $tempNewPromptTitle)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(6)
                    .background(Color.white.opacity(0.7))
                    .cornerRadius(6)
                    .font(.system(size: 15))
            }
            
            SettingItem {
                TextEditor(text: $tempNewPromptContent)
                    .frame(height: 80)
                    .padding(6)
                    .background(Color.white.opacity(0.7))
                    .cornerRadius(6)
                    .font(.system(size: 15))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5), lineWidth: 1))
            }
            
            HStack(spacing: 12) {
                Spacer()
                Button(action: cancelAddNewPrompt) {
                    Text("取消")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
                Button(action: saveNewPrompt) {
                    Text("添加")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .disabled(tempNewPromptTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tempNewPromptContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(.top, 10)
    }

    private var presetPromptsSection: some View {
        SettingGroupBox(title: "AI对话预设提示词") {
            VStack(spacing: 0) {
                ForEach(presetPrompts.indices, id: \.self) { idx in
                    presetPromptRowView(index: idx)
                }
                if showingNewPromptInput {
                    newPromptInputView
                } else {
                    addPresetPromptButton
                }
                // 【新增】底部按钮容器，用于恢复默认和保存
                HStack(spacing: 20) {
                    Spacer() // 左对齐
                    restorePresetPromptsButton
                    savePresetPromptsButton // 直接调用保存按钮视图
                    Spacer() // 右对齐
                }
                .frame(maxWidth: .infinity, alignment: .center) // 确保 Hstack 占据全宽并内容居中
                .padding(.top, 15) // 与上面内容的间距
                .padding(.bottom, 5) // 底部间距
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    var body: some View {
        ZStack {
            // 渐变背景
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(red: 0.85, green: 0.91, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 设置内容区
                ScrollView {
                    VStack(spacing: 20) {
                        displaySettingsSection
                        aiServiceConfigSection
                        presetPromptsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Color.clear)
                .frame(maxHeight: .infinity)
            }.padding(.top)
        }
        .onAppear {
            loadPrompts()
            // Set default batch summary prompt if it's empty
            if batchSummaryPrompt.isEmpty {
                batchSummaryPrompt = Prompt.DEFAULT_BATCH_SUMMARY_PROMPT
            }
        }
    }
    
    // MARK: - Helper Functions
    private func savePrompts() {
        if let encoded = try? JSONEncoder().encode(presetPrompts) {
            presetPromptsData = encoded
        }
    }
    
    private func loadPrompts() {
        if let decoded = try? JSONDecoder().decode([Prompt].self, from: presetPromptsData) {
            presetPrompts = decoded
        } else {
            // Load default prompts if no data is saved
            presetPrompts = Prompt.DEFAULT_PRESET_PROMPTS
        }
    }
    
    private func addPrompt() {
        showingNewPromptInput = true
        tempNewPromptTitle = ""
        tempNewPromptContent = ""
    }
    
    private func deletePrompt(at index: Int) {
        presetPrompts.remove(at: index)
    }
    
    private func cancelAddNewPrompt() {
        showingNewPromptInput = false
    }
    
    private func saveNewPrompt() {
        let newPrompt = Prompt(title: tempNewPromptTitle, content: tempNewPromptContent)
        presetPrompts.append(newPrompt)
        showingNewPromptInput = false
        tempNewPromptTitle = ""
        tempNewPromptContent = ""
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
