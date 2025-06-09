//
//  SettingsView.swift
//  LumiReader
//
//  Created by jolin on 2025/5/31.
//

import SwiftUI
import CoreData

struct SettingsView: View {
    // MARK: - State Properties
    
    // 批量总结提示词的状态
    @State private var batchSummaryPrompt: String = ""
    @AppStorage("selectedBatchScheme") private var selectedBatchScheme: BatchPromptScheme = .normal
    
    // 预设提示词恢复为简单的 AppStorage
    @AppStorage("presetPromptsData") private var presetPromptsData: Data = Data()
    @State private var presetPrompts: [Prompt] = []
    
    // 通用设置
    @AppStorage("geminiApiKey") private var geminiApiKey: String = ""
    @AppStorage("chatSummaryFontSize") private var chatSummaryFontSize: Double = 15.0
    
    // 列表编辑和删除状态
    @State private var editingPromptId: UUID? = nil
    @State private var showingNewPromptInput = false
    @State private var tempNewPromptTitle: String = ""
    @State private var tempNewPromptContent: String = ""
    @State private var promptToDelete: (index: Int, title: String)? = nil
    @State private var showingDeleteAlert = false
    
    // MARK: - Body
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(red: 0.85, green: 0.91, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        displaySettingsSection
                        apiKeySection
                        batchSummarySection
                        presetPromptsSection // 现在是独立的部分
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .padding(.top)
        }
        .onAppear {
            loadBatchPrompt()
            loadPresetPrompts()
        }
        .onChange(of: selectedBatchScheme) { _ in
            loadBatchPrompt()
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { promptToDelete = nil }
            Button("删除", role: .destructive) {
                if let index = promptToDelete?.index {
                    deletePrompt(at: index)
                    savePresetPrompts() // 删除后直接保存
                }
                promptToDelete = nil
            }
        } message: {
            if let title = promptToDelete?.title {
                Text("确定要删除提示词「\(title)」吗？此操作无法撤销。")
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - View Sections
    
    private var displaySettingsSection: some View {
        SettingGroupBox(title: "显示设置") {
            SettingItem {
                HStack {
                    Text("文字大小")
                    Slider(value: $chatSummaryFontSize, in: 12...30, step: 1)
                    Text("\(Int(chatSummaryFontSize))")
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
    }
    
    private var apiKeySection: some View {
        SettingGroupBox(title: "通用 AI 设置") {
            SettingItem {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key:")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                    SecureField("请输入API Key", text: $geminiApiKey)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(8)
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(6)
                }
            }
        }
    }

    private var batchSummarySection: some View {
        SettingGroupBox(title: "批量总结提示词") {
            VStack(alignment: .leading, spacing: 16) {
                Picker("批量总结方案", selection: $selectedBatchScheme) {
                    ForEach(BatchPromptScheme.allCases) { scheme in
                        Text(scheme.rawValue).tag(scheme)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                TextEditor(text: $batchSummaryPrompt)
                    .frame(minHeight: 100, maxHeight: 150)
                    .padding(8)
                    .background(Color.white.opacity(0.7))
                    .cornerRadius(6)
                    .font(.system(size: 15))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5), lineWidth: 1))
                
                HStack {
                    Button("恢复默认") {
                        batchSummaryPrompt = Prompt.defaultBatchSummary(for: selectedBatchScheme)
                    }
                    .font(.system(size: 13)).foregroundColor(.blue)
                    
                    Spacer()
                    
                    Button("保存") {
                        saveBatchPrompt()
                    }
                    .font(.system(size: 13)).foregroundColor(.white)
                    .padding(.vertical, 6).padding(.horizontal, 16)
                    .background(Color.blue).cornerRadius(8)
                }
            }
            .padding()
        }
    }
    
    private var presetPromptsSection: some View {
        SettingGroupBox(title: "AI对话预设提示词") {
            VStack(alignment: .leading, spacing: 16) {
                List {
                    ForEach(Array(presetPrompts.enumerated()), id: \.element.id) { idx, prompt in
                        if editingPromptId == prompt.id {
                            editingPresetPromptRowView(index: idx)
                        } else {
                            displayPresetPromptRowView(prompt: prompt, index: idx)
                        }
                    }
                    .onMove(perform: movePresetPrompt)
                }
                .environment(\.editMode, .constant(.active))
                .listStyle(PlainListStyle())
                .frame(minHeight: 200, maxHeight: 400)
                .background(Color.clear)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5), lineWidth: 1))
                
                if showingNewPromptInput {
                    newPromptInputView.padding(.top, 8)
                }
                
                HStack(spacing: 12) {
                    if !showingNewPromptInput {
                        addPresetPromptButton
                    }
                    Spacer()
                    restorePresetPromptsButton
                }
            }
            .padding()
        }
    }

    // MARK: - View Components (Rows & Buttons)
    private var addPresetPromptButton: some View {
        Button(action: { showingNewPromptInput = true }) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                Text("添加新提示词")
            }
        }.font(.system(size: 14)).foregroundColor(.blue)
    }

    private var restorePresetPromptsButton: some View {
        Button("恢复默认列表") {
            presetPrompts = Prompt.DEFAULT_PRESET_PROMPTS
            savePresetPrompts()
        }
        .font(.system(size: 13)).foregroundColor(.gray)
        .padding(.vertical, 6).padding(.horizontal, 16)
        .background(Color(.systemGray5)).cornerRadius(8)
    }

    private func displayPresetPromptRowView(prompt: Prompt, index: Int) -> some View {
        ZStack(alignment: .trailing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.title).font(.system(size: 15, weight: .medium))
                Text(prompt.content).font(.system(size: 13)).foregroundColor(.gray).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .allowsHitTesting(false)
            HStack(spacing: 8) {
                Button(action: {
                    editingPromptId = prompt.id
                }) {
                    Image(systemName: "pencil").foregroundColor(.blue).frame(width: 24, height: 24)
                }
                .buttonStyle(PlainButtonStyle())
                Button(action: {
                    promptToDelete = (index, prompt.title)
                    showingDeleteAlert = true
                }) {
                    Image(systemName: "trash").foregroundColor(.red).frame(width: 24, height: 24)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.leading, 8)
        }
        .padding(.vertical, 4)
    }

    private func editingPresetPromptRowView(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("提示词标题", text: $presetPrompts[index].title)
                Button("完成") {
                    editingPromptId = nil
                    savePresetPrompts() // 编辑完成直接保存
                }
            }
            TextEditor(text: $presetPrompts[index].content)
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5), lineWidth: 1))
        }
    }
    
    private var newPromptInputView: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("提示词标题", text: $tempNewPromptTitle).textFieldStyle(.roundedBorder)
            TextEditor(text: $tempNewPromptContent).frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5), lineWidth: 1))
            HStack {
                Spacer()
                Button("取消", action: cancelAddNewPrompt)
                Button("添加") { saveNewPrompt() }
                .disabled(tempNewPromptTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tempNewPromptContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding().background(Color.gray.opacity(0.1)).cornerRadius(8)
    }

    // MARK: - Data Handling
    private func loadBatchPrompt() {
        let key = "batchSummaryPrompt_\(selectedBatchScheme.rawValue)"
        batchSummaryPrompt = UserDefaults.standard.string(forKey: key) ?? Prompt.defaultBatchSummary(for: selectedBatchScheme)
    }
    
    private func saveBatchPrompt() {
        let key = "batchSummaryPrompt_\(selectedBatchScheme.rawValue)"
        UserDefaults.standard.set(batchSummaryPrompt, forKey: key)
        // You can add a success message here if needed.
    }
    
    private func loadPresetPrompts() {
        if let decoded = try? JSONDecoder().decode([Prompt].self, from: presetPromptsData) {
            presetPrompts = decoded
        } else {
            presetPrompts = Prompt.DEFAULT_PRESET_PROMPTS
        }
    }
    
    private func savePresetPrompts() {
        if let encoded = try? JSONEncoder().encode(presetPrompts) {
            presetPromptsData = encoded
        }
    }
    
    private func saveNewPrompt() {
        let newPrompt = Prompt(title: tempNewPromptTitle, content: tempNewPromptContent)
        presetPrompts.append(newPrompt)
        savePresetPrompts() // Add and save
        cancelAddNewPrompt()
    }
    
    private func deletePrompt(at index: Int) {
        presetPrompts.remove(at: index)
        // The save is handled in the alert confirmation
    }
    
    private func movePresetPrompt(from source: IndexSet, to destination: Int) {
        presetPrompts.move(fromOffsets: source, toOffset: destination)
        savePresetPrompts() // Move and save
    }
    
    private func cancelAddNewPrompt() {
        showingNewPromptInput = false
        tempNewPromptTitle = ""
        tempNewPromptContent = ""
    }
}

// 【新增】重新添加回来的辅助视图
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
