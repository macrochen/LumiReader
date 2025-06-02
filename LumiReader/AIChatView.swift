import SwiftUI
import CoreData
import UIKit // Import UIKit for UIPasteboard
//import Models // Import shared structures like ChatMessage and Prompt

// Define a struct for preset prompts (already exists, ensure Codable if needed for persistence later)
// struct PresetPrompt: Identifiable, Hashable { ... }

// 添加消息时间戳结构
struct MessageTimestamp: Equatable {
    let date: Date
    let formattedTime: String
    
    init(date: Date = Date()) {
        self.date = date
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        self.formattedTime = formatter.string(from: date)
    }
}

// 添加消息项结构体
struct ChatMessageItem: Identifiable, Equatable {
    let id: UUID
    let message: ChatMessage
    let attributedContent: AttributedString
    let timestamp: MessageTimestamp
    
    // Equatable conformance can often be synthesized if all members are Equatable
    // We still need to make sure ChatMessage, AttributedString, and MessageTimestamp are Equatable
    
    init(message: ChatMessage, attributedContent: AttributedString, timestamp: MessageTimestamp) {
        self.id = message.id
        self.message = message
        self.attributedContent = attributedContent
        self.timestamp = timestamp
    }
    
    // Manual conformance for Equatable
    static func == (lhs: ChatMessageItem, rhs: ChatMessageItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.message == rhs.message &&
        lhs.attributedContent == rhs.attributedContent &&
        lhs.timestamp == rhs.timestamp
    }
}

// 定义错误类型
enum ChatError: LocalizedError {
    case networkError(String)
    case apiError(String)
    case invalidApiKey
    case emptyResponse
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "网络错误：\(message)"
        case .apiError(let message):
            return "API 错误：\(message)"
        case .invalidApiKey:
            return "无效的 API Key，请在设置中检查"
        case .emptyResponse:
            return "AI 返回了空响应"
        case .unknown(let message):
            return "未知错误：\(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "请检查网络连接后重试"
        case .apiError:
            return "请稍后重试"
        case .invalidApiKey:
            return "请在设置中更新 API Key"
        case .emptyResponse:
            return "请重新发送消息"
        case .unknown:
            return "请重试或联系支持"
        }
    }
    
    var icon: String {
        switch self {
        case .networkError:
            return "wifi.slash"
        case .apiError:
            return "exclamationmark.triangle"
        case .invalidApiKey:
            return "key.fill"
        case .emptyResponse:
            return "bubble.left"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

// 自定义错误提示视图
struct ErrorAlertView: View {
    let error: ChatError
    let retryAction: () -> Void
    let dismissAction: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: error.icon)
                .font(.system(size: 40))
                .foregroundColor(.red)
            
            Text(error.errorDescription ?? "发生错误")
                .font(.headline)
                .multilineTextAlignment(.center)
            
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            HStack(spacing: 20) {
                Button(action: dismissAction) {
                    Text("关闭")
                        .frame(minWidth: 100)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }
                
                Button(action: retryAction) {
                    Text("重试")
                        .frame(minWidth: 100)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 10)
        .padding(.horizontal, 40)
    }
}

struct AIChatView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) var dismiss
    
    // Make article optional
    let article: Article?
    
    // Fetch all articles
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Article.importDate, ascending: false)],
        animation: .default)
    private var articles: FetchedResults<Article>
    
    // State to hold the selected article
    @State private var selectedArticle: Article? = nil
    
    // Use ChatMessageItem instead of tuple
    @State private var messages: [ChatMessageItem] = []
    @State private var inputText: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    // State for preset prompts (load from UserDefaults/Settings later)
    @State private var selectedPrompts: Set<Prompt> = []
    @AppStorage("aiPromptsData") private var aiPromptsData: Data = Data()
    @State private var presetPrompts: [Prompt] = [] // Use the Prompt struct from Models
    
    // State to temporarily hold clipboard content for [x] prompts
    @State private var clipboardContent: String = ""
    
    // Add state for streaming response
    @State private var streamingMessageId: UUID?
    @State private var streamingContent: String = ""
    
    // 更新错误状态
    @State private var chatError: ChatError?
    @State private var lastFailedMessage: String?
    
    // 添加输入框状态
    @State private var isInputFocused: Bool = false
    @State private var inputHeight: CGFloat = 35
    @State private var isComposing: Bool = false
    
    // 添加长按菜单状态
    @State private var selectedMessageForMenu: ChatMessage?
    @State private var showingMessageMenu = false
    
    
    
    // Computed property for preset prompts view
    @ViewBuilder
    private var presetPromptsView: some View {
        if !presetPrompts.isEmpty {
            VStack(spacing: 8) {
                // 提示词标签
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presetPrompts) { prompt in
                            Button(action: {
                                if prompt.content.contains("[x]") {
                                    // 处理 [x] 类型的提示词
                                    if let clipboardString = UIPasteboard.general.string {
                                        clipboardContent = clipboardString
                                        inputText = prompt.content.replacingOccurrences(of: "[x]", with: clipboardString)
                                    }
                                } else {
                                    inputText = prompt.content
                                }
                            }) {
                                Text(prompt.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(LinearGradient(gradient: Gradient(colors: [Color.purple, Color.pink]), startPoint: .leading, endPoint: .trailing))
                                    .cornerRadius(16)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.top, 4)
                .padding(.bottom, 2)
            }
            .background(Color.white.opacity(0.5).blur(radius: 2))
        }
    }
    
    // Computed property for article picker content
    @ViewBuilder
    private var articlePickerContent: some View {
        Text("-- 选择文章开始对话 --").tag(nil as Article?)
        ForEach(articles.prefix(10)) {
            article in
            Text(article.title ?? "无标题").tag(article as Article?)
        }
    }
    
    
    var body: some View {
        ZStack {
            // 渐变背景
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.95, green: 0.91, blue: 1.0), Color(red: 0.91, green: 0.84, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            primaryContentView
        }
        .onAppear(perform: loadPrompts)
        .alert("错误", isPresented: $showingError, presenting: errorMessage) { _ in
            Button("确定", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .overlay {
            if let error = chatError {
                ErrorAlertView(
                    error: error,
                    retryAction: {
                        if let lastMessage = lastFailedMessage {
                            inputText = lastMessage
                            sendMessage()
                        }
                        chatError = nil
                    },
                    dismissAction: {
                        chatError = nil
                    }
                )
            }
        }
    }
    
    private func loadPrompts() {
        if let decoded = try? JSONDecoder().decode([Prompt].self, from: aiPromptsData) {
            presetPrompts = decoded
        } else {
            presetPrompts = Prompt.DEFAULT_PRESET_PROMPTS
        }
    }
    
    private func sendMessage() {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Ensure an article is selected and input is not empty
        guard !trimmedInput.isEmpty, !isSending, let article = selectedArticle else { return }
        
        // 检查 API Key
        let apiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? ""
        guard !apiKey.isEmpty else {
            self.chatError = .invalidApiKey
            self.showingError = true
            return
        }
        
        isSending = true
        inputText = ""
        lastFailedMessage = trimmedInput
        
        // Create user message with timestamp
        let userMessage = ChatMessage(id: UUID(), sender: .user, content: trimmedInput)
        let attributedUserMessage = AttributedString(trimmedInput)
        let timestamp = MessageTimestamp()
        messages.append(ChatMessageItem(message: userMessage, attributedContent: attributedUserMessage, timestamp: timestamp))
        
        // Create a placeholder for the AI response
        let aiMessageId = UUID()
        streamingMessageId = aiMessageId
        streamingContent = ""
        
        // Prepare history for API call
        let apiHistory = messages.map { $0.message }
        
        // Call GeminiService.chatWithGemini
        Task {
            do {
                let stream = try await GeminiService.chatWithGemini(
                    articleContent: article.content ?? "", // Use content of the selected article
                    history: apiHistory,
                    newMessage: trimmedInput,
                    apiKey: apiKey
                )
                
                try await handleStreamingResponse(stream: stream, messageId: aiMessageId)
                await cleanupAfterSend()
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }
    
    private func copyMessageContent() {
        if let rawContent = messages.last?.message.content, !rawContent.isEmpty {
            #if canImport(UIKit)
            UIPasteboard.general.string = rawContent
            #endif
        } else {
            print("Attempted to copy empty or nil content.")
        }
    }
    
    private func updateInputTextFromSelection() {
        var combinedText = ""
        let sortedPrompts = selectedPrompts.sorted { $0.title < $1.title } // Sort for consistent order
        
        if selectedPrompts.count == 1, let prompt = selectedPrompts.first, prompt.title.lowercased().hasSuffix("[x]") {
            // Special case: single prompt with [x], combine with clipboard
            // Reading pasteboard needs to be async in some contexts, but within onChange
            // and triggered by a user action (tap), UIPasteboard.general.string is usually safe.
            if let clipboardContent = UIPasteboard.general.string, !clipboardContent.isEmpty {
                combinedText = prompt.content + "\n\n" + clipboardContent
            } else {
                combinedText = prompt.content
            }
        } else {
            // Multiple prompts or single prompt without [x]
            combinedText = sortedPrompts.map { $0.content }.joined(separator: "\n")
        }
        
        // Update inputText on the main thread (though onChange is usually on main thread)
        DispatchQueue.main.async {
            inputText = combinedText
        }
    }
    
    private func handleError(_ error: Error) {
        streamingMessageId = nil
        isSending = false
        
        // 将系统错误转换为我们的 ChatError，并确保类型转换安全
        let chatError: ChatError = {
            if let chatErr = error as? ChatError {
                return chatErr
            } else if let urlError = error as? URLError {
                return .networkError(urlError.localizedDescription)
            } else {
                return .unknown(error.localizedDescription)
            }
        }()
        
        self.chatError = chatError
        self.showingError = true
    }
    
    private func retryLastMessage(_ message: String) {
        inputText = message
        sendMessage()
    }
    
    // 新的函数来处理流式响应
    private func handleStreamingResponse(stream: AsyncThrowingStream<String, Error>, messageId: UUID) async throws {
        for try await chunk in stream {
            await updateStreamingMessage(chunk: chunk, messageId: messageId)
        }
    }
    
    // 新的函数来处理流式响应的 UI 更新
    @MainActor // Ensure this runs on the main actor
    private func updateStreamingMessage(chunk: String, messageId: UUID) {
        streamingContent += chunk
        // Update the streaming message in the UI
        if let index = messages.firstIndex(where: { $0.message.id == messageId }) {
            let attributedContent = AttributedString(streamingContent)
            messages[index] = ChatMessageItem(
                message: ChatMessage(id: messageId, sender: .gemini, content: streamingContent),
                attributedContent: attributedContent,
                timestamp: MessageTimestamp()
            )
        } else {
            // If the message's item doesn't exist yet, create it
            let attributedContent = AttributedString(streamingContent)
            messages.append(ChatMessageItem(
                message: ChatMessage(id: messageId, sender: .gemini, content: streamingContent),
                attributedContent: attributedContent,
                timestamp: MessageTimestamp()
            ))
        }
    }
    
    // 新的函数来处理发送后的清理工作
    private func cleanupAfterSend() async {
        await MainActor.run {
            streamingMessageId = nil
            isSending = false
        }
    }
    
    // 新的计算属性来分解 body
    @ViewBuilder
    private var primaryContentView: some View {
        VStack(spacing: 0) {
            // 文章选择器
            if let article = article {
                Text(article.title ?? "无标题")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
            } else {
                Picker("选择文章", selection: $selectedArticle) {
                    articlePickerContent
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            
            chatContentListView
            
            // 预设提示词选择区
            presetPromptsView
            
            inputBarView
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    let attributedContent: AttributedString
    let timestamp: MessageTimestamp
    let isStreaming: Bool
    let onLongPress: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.sender == .gemini {
                Image(systemName: "brain")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                    .frame(width: 30, height: 30)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(radius: 2)
            }
            
            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 4) {
                    if message.sender == .user {
                        Text(timestamp.formattedTime)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Text(attributedContent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(message.sender == .user ? Color.blue : Color.white)
                                .shadow(color: message.sender == .user ? Color.blue.opacity(0.3) : Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        )
                        .foregroundColor(message.sender == .user ? .white : .primary)
                        .scaleEffect(isPressed ? 0.98 : 1.0)
                        .animation(.spring(response: 0.3), value: isPressed)
                    
                    if message.sender == .gemini {
                        Text(timestamp.formattedTime)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                if message.sender == .gemini {
                    HStack(spacing: 12) {
                        Button(action: {
                            UIPasteboard.general.string = message.content
                        }) {
                            Label("复制", systemImage: "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: {
                            let activityVC = UIActivityViewController(
                                activityItems: [message.content],
                                applicationActivities: nil
                            )
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let window = windowScene.windows.first,
                               let rootVC = window.rootViewController {
                                rootVC.present(activityVC, animated: true)
                            }
                        }) {
                            Label("分享", systemImage: "square.and.arrow.up")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.leading, 4)
                }
            }
        }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 10) {
            onLongPress()
        } onPressingChanged: { isPressing in
            withAnimation(.spring(response: 0.3)) {
                isPressed = isPressing
            }
        }
    }
}

struct AIChatView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        // Create a sample article for preview
        let article = Article(context: context)
        article.title = "示例文章"
        article.content = "这是示例文章的内容"
        return Group {
            // Preview with article
            AIChatView(article: article)
                .environment(\.managedObjectContext, context)
            
            // Preview without article
            AIChatView(article: nil)
                .environment(\.managedObjectContext, context)
        }
    }
}

// MARK: - Helper Function for AIChatView (outside the struct)

// Function to update inputText based on selected prompts
private func updateInputText(selectedPrompts: Set<Prompt>, inputText: inout String) {
    var combinedText = ""
    let sortedPrompts = selectedPrompts.sorted { $0.title < $1.title } // Sort for consistent order
    
    if selectedPrompts.count == 1, let prompt = selectedPrompts.first, prompt.title.lowercased().hasSuffix("[x]") {
        // Special case: single prompt with [x], combine with clipboard
        if let clipboardContent = UIPasteboard.general.string, !clipboardContent.isEmpty {
            combinedText = prompt.content + "\n\n" + clipboardContent
        } else {
            combinedText = prompt.content
        }
    } else {
        // Multiple prompts or single prompt without [x]
        combinedText = sortedPrompts.map { $0.content }.joined(separator: "\n")
    }
    
    inputText = combinedText
}

// MARK: - 视图分解

extension AIChatView {
    // 新的计算属性来分解聊天内容区
    @ViewBuilder
    private var chatContentListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { messageItem in
                        messageRow(
                            message: messageItem.message,
                            attributedContent: messageItem.attributedContent,
                            timestamp: messageItem.timestamp,
                            proxy: proxy
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, inputHeight + 16) // Add padding at the bottom
            }
            .onChange(of: messages) { newMessages in
                if let lastMessage = newMessages.last {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color.clear)
        .frame(maxHeight: .infinity)
    }
    
    // Helper computed property for a single message row
    private func messageRow(
        message: ChatMessage,
        attributedContent: AttributedString,
        timestamp: MessageTimestamp,
        proxy: ScrollViewProxy
    ) -> some View {
        ChatBubble(
            message: message,
            attributedContent: attributedContent,
            timestamp: timestamp,
            isStreaming: streamingMessageId == message.id
        ) {
            selectedMessageForMenu = message
            showingMessageMenu = true
        }
        .id(message.id)
        .frame(maxWidth: .infinity, alignment: message.sender == .user ? .trailing : .leading)
        .contextMenu {
            Button(action: { UIPasteboard.general.string = message.content }) {
                Label("复制", systemImage: "doc.on.doc")
            }
            if message.sender == .gemini {
                Button(action: {
                    let activityVC = UIActivityViewController(activityItems: [message.content], applicationActivities: nil)
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootVC = window.rootViewController {
                        rootVC.present(activityVC, animated: true)
                    }
                }) { Label("分享", systemImage: "square.and.arrow.up") }
            }
        }
    }
    
    // 新的计算属性来分解输入区域
    @ViewBuilder
    private var inputBarView: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $inputText)
                    .frame(minHeight: 35, maxHeight: 120)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.9))
                            .shadow(color: isInputFocused ? Color.blue.opacity(0.2) : Color.clear, radius: 4, x: 0, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isInputFocused ? Color.blue : Color(.systemGray4), lineWidth: 1)
                    )
                    .font(.system(size: 15))
                    .foregroundColor(Color(.label))
                    .onChange(of: inputText) { _ in
                        withAnimation(.spring(response: 0.3)) {
                            // 根据内容自动调整高度
                            let size = CGSize(width: UIScreen.main.bounds.width - 100, height: .infinity)
                            let estimatedSize = inputText.boundingRect(
                                with: size,
                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                attributes: [.font: UIFont.systemFont(ofSize: 15)],
                                context: nil
                            )
                            inputHeight = min(max(35, estimatedSize.height + 16), 120)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification)) { _ in
                        withAnimation(.spring(response: 0.3)) {
                            isInputFocused = true
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidEndEditingNotification)) { _ in
                        withAnimation(.spring(response: 0.3)) {
                            isInputFocused = false
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidChangeNotification)) { _ in
                        isComposing = true
                        // 重置输入状态
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isComposing = false
                        }
                    }
                
                if inputText.isEmpty {
                    Text("输入您的问题...")
                        .foregroundColor(Color(.systemGray))
                        .font(.system(size: 15))
                        .padding(.top, 16)
                        .padding(.leading, 16)
                        .opacity(isInputFocused ? 0.5 : 1)
                }
            }
            .frame(height: inputHeight)
            
            // 发送按钮
            Button(action: sendMessage) {
                ZStack {
                    Circle()
                        .fill(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(.systemGray5) : Color.blue)
                        .frame(width: 32, height: 32)
                        .shadow(color: isInputFocused ? Color.blue.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 2)
                    
                    Image(systemName: isSending ? "arrow.up.circle" : "arrow.up.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(isSending ? 360 : 0))
                        .animation(isSending ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isSending)
                }
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending || isComposing)
            .scaleEffect(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.9 : 1.0)
            .animation(.spring(response: 0.3), value: inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color.white.opacity(0.8)
                .blur(radius: 2)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color(.systemGray5)),
                    alignment: .top
                )
        )
        .animation(.spring(response: 0.3), value: isInputFocused)
    }
} 
