import SwiftUI

// 提示词结构体
struct Prompt: Identifiable {
    let id = UUID()
    var title: String
    var content: String
}

struct SettingsView: View {
    // 示例数据
    @StateObject private var driveService = GoogleDriveService.shared
    @State private var googleAccount: String = "developer@example.com"
    @State private var apiKey: String = "sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    @State private var batchSummaryPrompt: String = "请针对以下多篇文章内容，为每一篇都生成包含\"主要内容\"、\"核心观点\"、\"关键细节\"和\"深度解读\"的结构化总结报告。将所有文章的总结合并为一个统一的文本块输出。"
    @State private var aiPrompts: [Prompt] = [
        Prompt(title: "全文总结", content: "请对这篇文章进行全面的总结，包括主要观点、关键论据和重要结论。"),
        Prompt(title: "批判性思考", content: "请从批判性思维的角度分析这篇文章，指出其优点、局限性和可能的改进空间。")
    ]
    @State private var editingPromptIndex: Int? = nil
    @State private var newPromptTitle: String = ""
    @State private var newPromptContent: String = ""
    @State private var showingFilePicker = false
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            // 渐变背景
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.95, green: 0.91, blue: 1.0), Color(red: 0.91, green: 0.84, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    Spacer()
                    Text("系统设置")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Color(.label))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                
                // 设置内容区
                ScrollView {
                    VStack(spacing: 20) {
                        // Google Drive账户
                        SettingGroupBox(title: "Google Drive 账户") {
                            VStack(spacing: 0) {
                                SettingItem {
                                    HStack {
                                        Text("当前账户")
                                        Spacer()
                                        Text(driveService.currentUser?.profile?.email ?? "未登录")
                                            .foregroundColor(.gray)
                                            .font(.system(size: 14))
                                    }
                                }
                                Divider()
                                SettingItem {
                                    HStack {
                                        Button(action: {
                                            showingFilePicker = true
                                        }) {
                                            Text("切换账户")
                                                .foregroundColor(.blue)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                                Divider()
                                SettingItem {
                                    HStack {
                                        Button(action: {
                                            driveService.signOut()
                                        }) {
                                            Text("断开连接")
                                                .foregroundColor(.red)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }
                        }
                        // AI服务配置
                        SettingGroupBox(title: "AI 服务配置") {
                            VStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("API Key:")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.gray)
                                    HStack(spacing: 8) {
                                        TextField("请输入API Key", text: $apiKey)
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
                                        Button(action: { /* 恢复默认 */ }) {
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
                                                    Button(action: { editingPromptIndex = nil }) {
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
                                                        Button(action: { aiPrompts.remove(at: idx) }) {
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
                                    Button(action: {
                                        aiPrompts.append(Prompt(title: "", content: ""))
                                        editingPromptIndex = aiPrompts.count - 1
                                    }) {
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
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Color.clear)
                .frame(maxHeight: .infinity)
                
                // 底部TabBar
                Divider()
                CustomTabBar(selected: .settings)
                    .padding(.bottom, 6)
            }
        }
        .sheet(isPresented: $showingFilePicker) {
            GoogleDriveFilePicker { files in
                // 处理选中的文件
                Task {
                    do {
                        for file in files {
                            let data = try await driveService.downloadFile(file)
                            // TODO: 处理下载的文件数据
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .alert("错误", isPresented: .constant(errorMessage != nil)) {
            Button("确定") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
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
