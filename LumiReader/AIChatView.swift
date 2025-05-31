import SwiftUI

struct AIChatView: View {
    // 聊天消息模型
    struct ChatMessage: Identifiable {
        let id = UUID()
        let isUser: Bool
        let text: String
    }
    // 预设提示词模型
    struct PresetPrompt: Identifiable, Hashable {
        let id = UUID()
        let text: String
    }
    
    // 示例数据
    @State private var messages: [ChatMessage] = [
        ChatMessage(isUser: false, text: "你好！关于\"优雅的清新主义美学与功能的完美平衡探索\"这篇文章，你有什么具体想了解的吗？例如，你可以问我它的核心观点、关键细节，或者让我针对某个方面进行更深入的解读。"),
        ChatMessage(isUser: true, text: "这篇文章的主要论点是什么？请用一句话概括。"),
        ChatMessage(isUser: false, text: "当然，这篇文章的主要论点是：在产品设计中，清新主义美学不仅仅是视觉上的追求，更是实现功能易用性和提升用户体验的关键途径，需要设计师在留白、色彩、排版等多个维度上找到美感与实用性的最佳平衡点。")
    ]
    @State private var inputText: String = ""
    @State private var selectedPrompts: Set<PresetPrompt> = [PresetPrompt(text: "列出案例")]
    let presetPrompts: [PresetPrompt] = [
        PresetPrompt(text: "全文总结"),
        PresetPrompt(text: "批判性思考"),
        PresetPrompt(text: "列出案例"),
        PresetPrompt(text: "新颖见解")
    ]
    let articleTitle: String = "优雅的清新主义美学..."
    
    var body: some View {
        ZStack {
            // 渐变背景
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.88, green: 0.99, blue: 0.95), Color(red: 0.80, green: 0.94, blue: 0.91)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    Spacer()
                    Text("对话: \(articleTitle)")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color(.label))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 8)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                
                // 聊天记录区
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { msg in
                            HStack {
                                if msg.isUser { Spacer() }
                                ChatBubble(text: msg.text, isUser: msg.isUser)
                                if !msg.isUser { Spacer() }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 16)
                .background(Color.clear)
                .frame(maxHeight: .infinity)
                
                // 预设提示词区
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presetPrompts) { prompt in
                            PresetPromptTag(prompt: prompt, isSelected: selectedPrompts.contains(prompt)) {
                                if selectedPrompts.contains(prompt) {
                                    selectedPrompts.remove(prompt)
                                } else {
                                    selectedPrompts.insert(prompt)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.top, 2)
                .padding(.bottom, 2)
                
                // 输入区
                HStack(alignment: .bottom, spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $inputText)
                            .frame(minHeight: 38, maxHeight: 80)
                            .padding(6)
                            .background(Color.white)
                            .cornerRadius(14)
                            .font(.system(size: 15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                        if inputText.isEmpty {
                            Text("输入您的问题...")
                                .foregroundColor(Color(.systemGray3))
                                .font(.system(size: 15))
                                .padding(.top, 10)
                                .padding(.leading, 12)
                        }
                    }
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.blue)
                            .cornerRadius(14)
                            .shadow(color: Color.blue.opacity(0.18), radius: 4, x: 0, y: 2)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.7).blur(radius: 2))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color(.systemGray5)), alignment: .top
                )
                
                // 底部TabBar
                Divider()
                CustomTabBar(selected: .aiChat)
                    .padding(.bottom, 6)
            }
        }
    }
    
    // 发送消息逻辑
    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(isUser: true, text: trimmed))
        inputText = ""
        // TODO: 触发AI回复
    }
}

// MARK: - 聊天气泡
struct ChatBubble: View {
    let text: String
    let isUser: Bool
    var body: some View {
        Text(text)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(isUser ? Color.blue : Color.white.opacity(0.9))
            .foregroundColor(isUser ? .white : Color(.gray))
            .font(.system(size: 15))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isUser ? Color.blue : Color(.systemGray5), lineWidth: isUser ? 0 : 1)
            )
            .shadow(color: isUser ? Color.blue.opacity(0.08) : Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            .frame(maxWidth: 420, alignment: isUser ? .trailing : .leading)
            .padding(isUser ? .leading : .trailing, 60)
    }
}

// MARK: - 预设提示词标签
struct PresetPromptTag: View {
    let prompt: AIChatView.PresetPrompt
    let isSelected: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .resizable()
                    .frame(width: 15, height: 15)
                    .foregroundColor(isSelected ? Color.blue : Color(.systemGray3))
                Text(prompt.text)
                    .font(.system(size: 13))
                    .foregroundColor(Color(.darkGray))
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AIChatView_Previews: PreviewProvider {
    static var previews: some View {
        AIChatView()
    }
} 