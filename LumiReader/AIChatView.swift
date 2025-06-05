import SwiftUI
import CoreData
import UIKit // Import UIKit for UIPasteboard
//import Models // Import shared structures like ChatMessage and Prompt

// Define a struct for preset prompts (already exists, ensure Codable if needed for persistence later)
// struct PresetPrompt: Identifiable, Hashable { ... }

// 移除 SelectableUIKitTextView 结构体定义

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
enum ChatError: LocalizedError, Identifiable {
    case networkError(String)
    case apiError(String)
    case invalidApiKey
    case emptyResponse
    case unknown(String)
    
    // 添加 id 属性以满足 Identifiable 协议
    var id: String {
        switch self {
        case .networkError(let message):
            return "network_\(message)"
        case .apiError(let message):
            return "api_\(message)"
        case .invalidApiKey:
            return "invalid_api_key"
        case .emptyResponse:
            return "empty_response"
        case .unknown(let message):
            return "unknown_\(message)"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "网络错误：\(message)"
        case .apiError(let message):
            return message
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
    
    @Binding var article: Article? // Changed from pendingArticleID for directness as per latest context
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Article.importDate, ascending: false)],
        animation: .default)
    private var articles: FetchedResults<Article>
    
    @State private var selectedArticle: Article? // Internal state for Picker if @Binding article is nil
    
    @State private var messages: [ChatMessageItem] = []
    @State private var inputText: String = ""
    @State private var isSending = false
    
    @State private var selectedPrompts: Set<Prompt> = []
    @AppStorage("aiPromptsData") private var aiPromptsData: Data = Data()
    @State private var presetPrompts: [Prompt] = Prompt.DEFAULT_PRESET_PROMPTS
    
    @State private var clipboardContent: String = ""
    
    @State private var chatError: ChatError?
    @State private var lastFailedMessage: String?
    
    @State private var isInputFocused: Bool = false
    @State private var inputHeight: CGFloat = 35
    @State private var isComposing: Bool = false
    
    @State private var selectedMessageForMenu: ChatMessage?
    @State private var showingMessageMenu = false
    
    @State private var appearCount = 0

    // 【新增】流式输出相关的状态变量
    @State private var streamingMessageId: UUID? = nil // 正在流式输出的消息ID
    @State private var streamingContent: String = "" // 当前流式输出的内容
    
    // 【修改】用于在 Sheet 中传递 Identifiable 的内容
    @State private var selectedMessageContentToSelect: SelectableContent? = nil
    
    // 【新增】用于读取文字大小设置 (已移动到结构体内部)
    @AppStorage("chatSummaryFontSize") private var chatSummaryFontSize: Double = 15.0
    
    // Initialize and sync selectedArticle with the binding `article`
    init(article: Binding<Article?>) {
        self._article = article
        // Initialize _selectedArticle state with the initial value of the binding
        // This ensures that if an article is passed in, it's used.
        // If `article` is nil, then `selectedArticle` will also be nil, allowing Picker.
        self._selectedArticle = State(initialValue: article.wrappedValue) 
        // print("AIChatView init. Bound Article: \(article.wrappedValue?.title ?? "nil"), SelectedArticle: \(self.selectedArticle?.title ?? "nil")")
    }
    
    // Computed property for preset prompts view
    @ViewBuilder
    private var presetPromptsView: some View {
        if !presetPrompts.isEmpty {
            VStack(alignment: .leading, spacing: 8) { // Ensure leading alignment for title
                Text("选择预设提示词:") // Added a title for the section
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presetPrompts) { prompt in
                            let isSelected = selectedPrompts.contains(prompt)
                            let isExclusive = prompt.title.lowercased().contains("[x]")

                            Button(action: {
                                togglePromptSelection(prompt: prompt, isExclusive: isExclusive)
                                updateInputTextFromSelection()
                            }) {
                                Text(prompt.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(isSelected ? .white : (isExclusive ? Color.orange : Color.blue) ) // Distinct colors
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(isSelected ? (isExclusive ? Color.orange.opacity(0.8) : Color.blue.opacity(0.8)) : Color(.systemGray5))
                                    )
                                    // Removed .cornerRadius(16) here as it's on RoundedRectangle
                            }
                        }
                    }
                    .padding(.horizontal, 10) // Consistent padding
                    .padding(.bottom, 6) // Add some bottom padding
                }
            }
            .padding(.top, 6) // Padding for the whole section
            // .background(Color.white.opacity(0.5).blur(radius: 2)) // Kept background
        }
    }
    
    // Helper function to manage prompt selection logic
    private func togglePromptSelection(prompt: Prompt, isExclusive: Bool) {
        if isExclusive {
            if selectedPrompts.contains(prompt) { // If the exclusive is already selected, deselect it
                selectedPrompts.removeAll()
            } else { // Select this exclusive prompt, deselect all others
                selectedPrompts.removeAll()
                selectedPrompts.insert(prompt)
            }
        } else { // Non-exclusive prompt
            // If an exclusive prompt is currently selected, deselect it first
            if let exclusivePrompt = selectedPrompts.first(where: { $0.title.lowercased().contains("[x]") }) {
                selectedPrompts.remove(exclusivePrompt)
            }
            // Toggle selection for the current non-exclusive prompt
            if selectedPrompts.contains(prompt) {
                selectedPrompts.remove(prompt)
            } else {
                selectedPrompts.insert(prompt)
            }
        }
    }
    
    // Computed property for article picker content
    @ViewBuilder
    private var articlePickerContent: some View {
        Text("-- 选择文章开始对话 --").tag(nil as Article?)
        ForEach(articles) { articleItem in // 显示所有文章
            Text(articleItem.title ?? "无标题").tag(articleItem as Article?)
        }
    }
    
    @ViewBuilder
    private var primaryContentView: some View {
        VStack(spacing: 0) {
            // Article display/picker
            // Always display the Picker
            Picker("选择文章开始对话", selection: $selectedArticle) { // Picker now binds to @State selectedArticle
                articlePickerContent
            }
            .pickerStyle(MenuPickerStyle())
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider() // Add a divider

            chatContentListView
            .frame(maxHeight: .infinity) // 【新增/修改】让聊天内容列表占据所有剩余空间


            Divider() // Add a divider

            presetPromptsView // This now has its own internal padding and title

            inputBarView
        }
        // 【修改】模态视图用于文本选择，绑定到 selectedMessageContentToSelect
        .sheet(item: $selectedMessageContentToSelect) { contentToSelectWrapper in
            // Sheet 的内容闭包接收到 Identifiable 的包装类型
            SelectTextView(attributedContent: contentToSelectWrapper.attributedContent)
        }
    }
    
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(red: 0.85, green: 0.91, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            primaryContentView
        }
        .onAppear {
            appearCount += 1
            print("AIChatView onAppear (\(appearCount)). Bound Article: \(article?.title ?? "nil"), SelectedArticle: \(selectedArticle?.title ?? "nil")")
            loadPrompts()
            // Sync selectedArticle with the binding `article` if it changes externally or on initial appear
            if selectedArticle?.objectID != article?.objectID { // Compare by objectID for CoreData entities
                selectedArticle = article
                if article != nil {
                    messages = [] // Clear messages if a new article is selected via binding
                    inputText = ""
                    chatError = nil
                }
            }
        }
        .onChange(of: article) { newArticleFromBinding in
            print("AIChatView @Binding article changed to: \(newArticleFromBinding?.title ?? "nil")")
            if selectedArticle?.objectID != newArticleFromBinding?.objectID {
                selectedArticle = newArticleFromBinding
                messages = [] // Clear messages if article changes
                inputText = ""
                chatError = nil
            }
        }
        .alert(item: $chatError) { error in
            Alert(
                title: Text(error.errorDescription ?? "错误"),
                message: Text(error.recoverySuggestion ?? "请稍后重试。"),
                primaryButton: .default(Text("重试"), action: {
                    if let lastMessage = lastFailedMessage {
                        inputText = lastMessage
                        sendMessage()
                    }
                }),
                secondaryButton: .cancel(Text("关闭"))
            )
        }
    }
    
    private func loadPrompts() {
        if let decoded = try? JSONDecoder().decode([Prompt].self, from: aiPromptsData) {
            if !decoded.isEmpty { // Only assign if decoded is not empty
                presetPrompts = decoded
            } else {
                presetPrompts = Prompt.DEFAULT_PRESET_PROMPTS // Fallback to default
                // Optionally save defaults if none were loaded
                // if let encodedDefaults = try? JSONEncoder().encode(Prompt.DEFAULT_PRESET_PROMPTS) {
                //     aiPromptsData = encodedDefaults
                // }
            }
        } else {
            presetPrompts = Prompt.DEFAULT_PRESET_PROMPTS
        }
    }
    
    private func sendMessage() {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty, !isSending, let articleToChat = selectedArticle else {
            if selectedArticle == nil {
                self.chatError = .unknown("请先选择一篇文章开始对话。")
            }
            return
        }
        
        let apiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? ""
        guard !apiKey.isEmpty else {
            self.chatError = .invalidApiKey
            return
        }
        
        isSending = true
        inputText = ""
        lastFailedMessage = trimmedInput
        selectedPrompts = []
        
        let userMessage = ChatMessage(id: UUID(), sender: .user, content: trimmedInput)
        let attributedUserContent = convertToMarkdownAttributedString(trimmedInput)
        let timestamp = MessageTimestamp()
        messages.append(ChatMessageItem(message: userMessage, attributedContent: attributedUserContent, timestamp: timestamp))
        
        // 【新增】为流式 AI 回复添加一个占位符消息
        let aiMessageId = UUID()
        streamingMessageId = aiMessageId
        streamingContent = ""
        // 使用一个临时的 AttributedString，例如显示一个光标
        let placeholderAttributedContent = convertToMarkdownAttributedString("▌")
        let placeholderAIMessage = ChatMessage(id: aiMessageId, sender: .gemini, content: "")
        messages.append(ChatMessageItem(message: placeholderAIMessage, attributedContent: placeholderAttributedContent, timestamp: MessageTimestamp()))

        // 【修改】使用流式 API
        let apiHistory = messages.dropLast().map { $0.message } // 排除掉最新的占位符消息

        Task {
            do {
                let stream = try await GeminiService.chatWithGemini(
                    articleContent: articleToChat.content ?? "",
                    history: apiHistory,
                    newMessage: trimmedInput,
                    apiKey: apiKey
                )
                
                // 【修改】处理流式响应
                try await handleStreamingResponse(stream: stream, messageId: aiMessageId)
                await cleanupAfterSend()
            } catch {
                await MainActor.run {
                    // 【新增】如果在流式过程中发生错误，移除占位符消息
                    if let index = messages.firstIndex(where: { $0.id == aiMessageId }) {
                         messages.remove(at: index)
                    }
                    handleError(error)
                }
            }
        }
    }
    
    private func copyMessageContent(content: String) { // Added parameter
        #if canImport(UIKit)
        UIPasteboard.general.string = content
        #endif
    }
    
    private func updateInputTextFromSelection() {
        var combinedText = ""
        let sortedPrompts = selectedPrompts.sorted { $0.title < $1.title }
        
        if selectedPrompts.count == 1, let prompt = selectedPrompts.first, prompt.title.lowercased().contains("[x]") {
            #if canImport(UIKit)
            if let clipboardString = UIPasteboard.general.string, !clipboardString.isEmpty {
                combinedText = prompt.content.replacingOccurrences(of: "[x]", with: clipboardString, options: .caseInsensitive)
            } else {
                combinedText = prompt.content.replacingOccurrences(of: "[x]", with: "", options: .caseInsensitive) // Replace [x] with empty if clipboard is empty
            }
            #else
            combinedText = prompt.content.replacingOccurrences(of: "[x]", with: "", options: .caseInsensitive) // Fallback for non-UIKit
            #endif
        } else {
            combinedText = sortedPrompts.map { $0.content }.joined(separator: "\n\n") // Add double newline for clarity
        }
        
        DispatchQueue.main.async {
            inputText = combinedText
        }
    }
    
    private func handleError(_ error: Error) {
        isSending = false
        
        let specificError: ChatError = {
            if let chatErr = error as? ChatError {
                return chatErr
            } else if let urlError = error as? URLError {
                return .networkError(urlError.localizedDescription)
            } else if let geminiError = error as? GeminiServiceError {
                switch geminiError {
                case .networkError(let description):
                    return .networkError(description)
                case .apiError(let message):
                    return .apiError(message)
                case .invalidAPIKey:
                    return .invalidApiKey
                case .emptyResponse:
                    return .emptyResponse
                case .httpError(let statusCode):
                    // For httpError, create a message including the status code
                    return .apiError("HTTP Status Code: \(statusCode)")
                case .unknown(let underlyingError):
                    // For unknown GeminiServiceError, wrap the underlying error's description
                    return .unknown(underlyingError.localizedDescription)
                case .invalidResponseType:
                    // Handle the case where the response is not an HTTPURLResponse
                    return .unknown("API 返回了无效的响应类型。")
                }
            } else {
                return .unknown(error.localizedDescription)
            }
        }()
        
        self.chatError = specificError
    }
    
    private func cleanupAfterSend() async {
        // 【修改】清空 streamingMessageId
        await MainActor.run { streamingMessageId = nil; isSending = false }
    }

    // 【新增】复制文章信息和AI回复内容
    private func copyArticleAndResponse(attributedContent: AttributedString, articleTitle: String?, articleLink: String?) {
        var combinedContent = ""
        combinedContent += "文章标题: \(articleTitle ?? "无标题")\n"
        if let link = articleLink, !link.isEmpty {
            combinedContent += "文章链接: \(link)\n"
        }
        combinedContent += "\nAI回复内容:\n"
        // 将 AttributedString 转换为纯文本
        combinedContent += NSAttributedString(attributedContent).string

        #if canImport(UIKit)
        UIPasteboard.general.string = combinedContent
        #endif
        print("Copied combined content:")
        print(combinedContent)
    }

    // 【新增】处理流式响应
    private func handleStreamingResponse(stream: AsyncThrowingStream<String, Error>, messageId: UUID) async throws {
        var accumulatedContent = ""
        for try await chunk in stream {
            accumulatedContent += chunk
            await updateStreamingMessage(fullContent: accumulatedContent, messageId: messageId)
        }
        // Final update to ensure no trailing cursor and content is fully set
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index] = ChatMessageItem(
                message: ChatMessage(id: messageId, sender: .gemini, content: accumulatedContent),
                attributedContent: convertToMarkdownAttributedString(accumulatedContent),
                timestamp: messages[index].timestamp // Keep original timestamp
            )
        }
    }

    // 【新增】在主线程更新流式消息内容
    @MainActor
    private func updateStreamingMessage(fullContent: String, messageId: UUID) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            // Add a blinking cursor effect to the streaming content
            let streamingTextWithCursor = fullContent + "▌"
            messages[index] = ChatMessageItem(
                message: ChatMessage(id: messageId, sender: .gemini, content: fullContent), // Store raw full content
                attributedContent: convertToMarkdownAttributedString(streamingTextWithCursor),
                timestamp: messages[index].timestamp
            )
        }
    }

    // Helper to convert markdown string to AttributedString
    private func convertToMarkdownAttributedString(_ markdownString: String) -> AttributedString {
        do {
            let normalizedString = markdownString.replacingOccurrences(of: "\r\n", with: "\n")
                                            .replacingOccurrences(of: "\r", with: "\n")
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            return try AttributedString(markdown: normalizedString, options: options)
        } catch {
            print("Error parsing markdown for AttributedString: \(error). Falling back to plain string.")
            return AttributedString(markdownString.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        }
    }
}

// ChatBubble and PreviewProvider, helper function, and extensions remain mostly the same
// Ensure ChatMessage and Prompt structs are defined or imported.
// For PreviewProvider, ensure you pass a Binding<String?> for pendingArticleID
struct ChatBubble: View {
    let message: ChatMessage
    let attributedContent: AttributedString
    let timestamp: MessageTimestamp
    // 【新增】指示当前消息是否正在流式输出
    let isStreaming: Bool
    
    // 【新增】接收字体大小设置
    let fontSize: CGFloat
    
    // 【新增】接收外部状态和回调
    @Binding var showingSelectTextView: Bool
    @Binding var selectedMessageContentToSelect: SelectableContent?
    let onCopyMessage: (String) -> Void // 用于复制纯文本消息内容
    let onCopyArticleAndMessage: (AttributedString, String?, String?) -> Void // 用于复制文章信息+消息内容
    
    // Article info (passed for the second copy option)
    let articleTitle: String?
    let articleLink: String?
    
    @State private var isPressed = false

    // 你可能需要根据你的 App 主题或者具体需求来定义这些字体和颜色
    private var bubbleFont: UIFont {
        // 例如，可以根据消息发送者或其他条件返回不同的字体
        // 【修改】使用设置中的文字大小
        return UIFont.systemFont(ofSize: fontSize)
    }

    private var bubbleTextColor: UIColor {
        return message.sender == .user ? UIColor.white : UIColor.label // .label 对应系统深浅模式的文字颜色
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 4) {
                // 【修改】使用 Text 组件替代 SelectableUIKitTextView
                Text(attributedContent)
                    // 【新增】启用文本选择
                    .textSelection(.enabled)
                    // 【新增】应用文字大小设置
                    .font(.system(size: fontSize))
                    // 应用原 SelectableUIKitTextView 的修饰符
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.sender == .user ? Color.blue : Color(.systemGray5))
                    .cornerRadius(16)
                    // 应用外部宽度约束和对齐
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.9, alignment: message.sender == .user ? .trailing : .leading)
                    // Text 默认支持高度自适应和换行，fixedSize vertical true 可以加强这一点
                    .fixedSize(horizontal: false, vertical: true)
                
                // Timestamp and Actions
                HStack(spacing: 12) {
                    Text(timestamp.formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if message.sender == .gemini && !message.content.isEmpty {
                        // 【修改】仅当消息不是流式输出中时才显示复制按钮
                        if !isStreaming {
                            // Copy message content
                            Button {
                                onCopyMessage(message.content) // 复制纯文本内容
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }

                            // Copy article info + message content
                            Button {
                                onCopyArticleAndMessage(attributedContent, articleTitle, articleLink) // 复制文章信息+消息内容
                            } label: {
                                Image(systemName: "doc.on.clipboard.fill")
                            }
                        }
                    }
                }
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: message.sender == .user ? .trailing : .leading)
                .layoutPriority(0)
            }
        }
        // 【修改】调整气泡左右的 padding 来控制宽度
        .padding(message.sender == .user ? .leading : .trailing, UIScreen.main.bounds.width * 0.05)
        .padding(.vertical, 4)
        // 【恢复】长按 Context Menu
        .contextMenu {
            // 标准复制选项
            Button {
                onCopyMessage(message.content)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }

            // 【恢复】选中文字选项
            Button {
                // 将 AttributedString 包装在 Identifiable 结构体中
                selectedMessageContentToSelect = SelectableContent(attributedContent: attributedContent)
            } label: {
                Label("选中文字", systemImage: "text.cursor")
            }

            // 分享选项 (如果需要)
            // if message.sender == .gemini { // Share only for Gemini messages
            //     Button { shareContent(message.content) } label: { Label("分享", systemImage: "square.and.arrow.up") }
            // }
        }
    }
}


struct AIChatView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.title = "示例文章"
        article.content = "这是示例文章的内容"
        try? context.save() // Save to get a permanent ID if needed by init logic
        
        // Prepare some mock messages
        let mockMessages = [
            ChatMessageItem(message: ChatMessage(id: UUID(), sender: .user, content: "你好，AI！"), attributedContent: AttributedString("你好，AI！"), timestamp: MessageTimestamp(date: Date().addingTimeInterval(-600))),
            ChatMessageItem(message: ChatMessage(id: UUID(), sender: .gemini, content: "你好！有什么可以帮助你的吗？"), attributedContent: AttributedString("你好！有什么可以帮助你的吗？"), timestamp: MessageTimestamp(date: Date().addingTimeInterval(-540)))
        ]
        
        // Create a version of AIChatView that accepts messages for preview
        // This might require a temporary init or a way to inject state for preview
        
        return Group {
            AIChatView(article: .constant(article))
                .environment(\.managedObjectContext, context)
                .previewDisplayName("With Article")
            
            AIChatView(article: .constant(nil))
                .environment(\.managedObjectContext, context)
                .previewDisplayName("No Article (Picker)")
        }
    }
}

// MARK: - Helper Function for AIChatView (outside the struct)

// Function to update inputText based on selected prompts (kept outside for clarity)
// This function is now called from within AIChatView, so it needs access to its properties
// or have them passed as parameters. For now, it's a global helper.
// Consider making it a private func inside AIChatView or passing $inputText as @Binding.

// MARK: - 视图分解

extension AIChatView {
    @ViewBuilder private var chatContentListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) { // Reduced spacing
                    ForEach(messages) { messageItem in
                        messageRow(
                            message: messageItem.message,
                            attributedContent: messageItem.attributedContent,
                            timestamp: messageItem.timestamp
                        )
                    }
                }
                .padding(.horizontal, 10) // Consistent horizontal padding
                .padding(.top, 10)
            }
            .onChange(of: messages.count) { _ in // Use messages.count to re-trigger on new message
                if let lastMessage = messages.last {
                    DispatchQueue.main.async { // Ensure UI updates on main thread
                        withAnimation(.spring()) { // Smoother scroll
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color.clear) // Ensure ScrollView background is clear
    }
    
    private func messageRow(
        message: ChatMessage,
        attributedContent: AttributedString,
        timestamp: MessageTimestamp
    ) -> some View {
        ChatBubble(
            message: message,
            attributedContent: attributedContent,
            timestamp: timestamp,
            isStreaming: streamingMessageId == message.id && message.sender == .gemini,
            fontSize: CGFloat(chatSummaryFontSize),
            showingSelectTextView: $showingMessageMenu,
            selectedMessageContentToSelect: $selectedMessageContentToSelect,
            onCopyMessage: {
                contentToCopy in
                copyMessageContent(content: contentToCopy)
            },
            onCopyArticleAndMessage: { content, title, link in
                copyArticleAndResponse(attributedContent: content, articleTitle: title, articleLink: link)
            },
            articleTitle: selectedArticle?.title,
            articleLink: selectedArticle?.link
        )
        .id(message.id) // Ensure each row has a unique ID for ScrollViewReader
        .frame(maxWidth: UIScreen.main.bounds.width * 0.75)  // Handled in ChatBubble
        .onChange(of: message) { newMessage in
            // 在消息内容变化时打印信息
            print("ChatBubble onChange - Message ID: \(newMessage.id), Sender: \(newMessage.sender), Content (Plain Text): \(newMessage.content)")
        }
    }
    
    @ViewBuilder
    private var inputBarView: some View {
        VStack(spacing: 0) { // Wrap in VStack to allow for potential elements above TextEditor
            Divider() // Visual separation
            HStack(alignment: .bottom, spacing: 10) {
                TextEditor(text: $inputText)
                    .frame(minHeight: inputHeight, maxHeight: 120) // Use calculated inputHeight
                    .padding(.horizontal, 8) // Internal padding for TextEditor text
                    .padding(.vertical, 6)   // Internal padding for TextEditor text
                    .background(Color(.systemGray6)) // Background for TextEditor area
                    .clipShape(RoundedRectangle(cornerRadius: 10)) // Clip shape for TextEditor
                    .font(.system(size: 16)) // Consistent font size
                    .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification)) { _ in isInputFocused = true }
                    .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidEndEditingNotification)) { _ in isInputFocused = false }
                    .onChange(of: inputText) { newValue in // Using new syntax for onChange
                        // Auto-adjust height of TextEditor
                        let newHeight = calculateTextEditorHeight(text: newValue)
                        if abs(inputHeight - newHeight) > 1 { // Only update if change is significant
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                inputHeight = newHeight
                            }
                        }
                        isComposing = !newValue.isEmpty // Simplified composing state
                    }
                    // Placeholder logic directly on ZStack if preferred, or overlay
                    .overlay(alignment: .topLeading) {
                         if inputText.isEmpty {
                             Text("输入您的问题...")
                                 .foregroundColor(Color(.placeholderText))
                                 .font(.system(size: 16))
                                 .padding(.horizontal, 12) // Match TextEditor's internal padding
                                 .padding(.vertical, 10)   // Match TextEditor's internal padding
                                 .allowsHitTesting(false) // Let taps pass through to TextEditor
                         }
                     }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
    
    // Helper to calculate TextEditor height
    private func calculateTextEditorHeight(text: String) -> CGFloat {
        let textView = UITextView()
        textView.text = text
        textView.font = UIFont.systemFont(ofSize: 16) // Match TextEditor font
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8) // Match padding
        let fixedWidth = UIScreen.main.bounds.width - 24 /* H paddings */ - 32 /* Button width */ - 10 /* Spacing */ - 16 /* TextEditor internal H paddings */
        let size = textView.sizeThatFits(CGSize(width: fixedWidth, height: .greatestFiniteMagnitude))
        return min(max(35, size.height), 120) // Clamp between min and max height
    }
}

// 【新增】用于在模态视图中显示可选择文本的 UIViewRepresentable
struct SelectableTextViewRepresentable: UIViewRepresentable {
    let attributedText: NSAttributedString
    @Binding var textView: UITextView
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false // 不可编辑，只用于显示和选择
        textView.isSelectable = true // 启用文本选择
        textView.isScrollEnabled = true // 允许在模态视图中滚动
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        // 可以根据需要配置字体、颜色等，或者从 AttributedString 中继承
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = attributedText
        // 【新增】打印 NSAttributedString 内容进行调试
        print("SelectableTextViewRepresentable updateUIView - Received NSAttributedString (length: \(attributedText.length))")
        print("Content Preview: \(attributedText.string.prefix(200))...")
        // 确保文本视图内容可以滚动和选择
        uiView.isSelectable = true
        uiView.isScrollEnabled = true
    }
}

// 【新增】用于模态显示的文本选择视图
struct SelectTextView: View {
    @Environment(\.dismiss) var dismiss
    let contentToSelect: AttributedString
    
    // 【新增】用于获取 UITextView 实例以便访问选中内容
    @State private var textView = UITextView() 
    
    // 将 AttributedString 转换为 NSAttributedString 以便传递给 UITextView
    private var nsAttributedString: NSAttributedString {
        // 确保在这里正确转换 AttributedString 到 NSAttributedString
        return NSAttributedString(contentToSelect as Foundation.AttributedString)
    }
    
    // 【修改】显式添加一个带有参数标签的初始化方法
    init(attributedContent: AttributedString) {
        self.contentToSelect = attributedContent
        // 【新增】打印 AttributedString 内容进行调试
        print("SelectTextView initialized with AttributedString (length: \(contentToSelect.characters.count))")
        print("Content Preview: \(String(contentToSelect.characters.prefix(200)))... ")
    }
    
    var body: some View {
        NavigationView { // 使用 NavigationView 提供标题和关闭按钮
            VStack {
                // 使用我们创建的 UIViewRepresentable，并将 UITextView 实例绑定到 @State 变量
                SelectableTextViewRepresentable(attributedText: nsAttributedString, textView: $textView)
                    .padding() // 添加一些内边距
            }
            .navigationTitle("选中文字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// 【新增】用于包装 AttributedString 并使其遵循 Identifiable
struct SelectableContent: Identifiable {
    let id = UUID()
    let attributedContent: AttributedString
} 
