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
    // @State private var errorMessage: String? // Replaced by chatError
    // @State private var showingError = false // Replaced by chatError
    
    @State private var selectedPrompts: Set<Prompt> = []
    @AppStorage("aiPromptsData") private var aiPromptsData: Data = Data()
    @State private var presetPrompts: [Prompt] = Prompt.DEFAULT_PRESET_PROMPTS // Initialize with default
    
    @State private var clipboardContent: String = "" // Not directly used in this refactor but kept
    
    @State private var streamingMessageId: UUID?
    @State private var streamingContent: String = ""
    
    @State private var chatError: ChatError?
    @State private var lastFailedMessage: String?
    
    @State private var isInputFocused: Bool = false
    @State private var inputHeight: CGFloat = 35
    @State private var isComposing: Bool = false
    
    @State private var selectedMessageForMenu: ChatMessage?
    @State private var showingMessageMenu = false
    
    @State private var appearCount = 0


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
        ForEach(articles.prefix(10)) { articleItem in // Renamed to avoid conflict
            Text(articleItem.title ?? "无标题").tag(articleItem as Article?)
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
                if newArticleFromBinding != nil {
                     messages = [] // Clear messages if article changes
                     inputText = ""
                     chatError = nil
                }
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
        guard !trimmedInput.isEmpty, !isSending, let articleToChat = selectedArticle else { // Use selectedArticle
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
        selectedPrompts = [] // Clear selected prompts after sending
        
        let userMessage = ChatMessage(id: UUID(), sender: .user, content: trimmedInput)
        // Attempt to create AttributedString, fallback to plain string if markdown parsing fails
        var attributedUserContent: AttributedString
        do {
            attributedUserContent = try AttributedString(markdown: trimmedInput)
        } catch {
            attributedUserContent = AttributedString(trimmedInput)
        }
        let timestamp = MessageTimestamp()
        messages.append(ChatMessageItem(message: userMessage, attributedContent: attributedUserContent, timestamp: timestamp))
        
        let aiMessageId = UUID()
        streamingMessageId = aiMessageId
        streamingContent = ""
        // Add a temporary streaming placeholder to messages
        let placeholderAIMessage = ChatMessage(id: aiMessageId, sender: .gemini, content: "")
        messages.append(ChatMessageItem(message: placeholderAIMessage, attributedContent: AttributedString("▌"), timestamp: MessageTimestamp()))


        let apiHistory = messages.dropLast().map { $0.message } // Exclude the placeholder
        
        Task {
            do {
                let stream = try await GeminiService.chatWithGemini(
                    articleContent: articleToChat.content ?? "",
                    history: apiHistory,
                    newMessage: trimmedInput,
                    apiKey: apiKey
                )
                
                try await handleStreamingResponse(stream: stream, messageId: aiMessageId)
                await cleanupAfterSend()
            } catch {
                await MainActor.run {
                    // Remove placeholder on error before showing error
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
        streamingMessageId = nil
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
        // self.showingError = true // chatError change should trigger overlay
    }
    
    // private func retryLastMessage(_ message: String) { /* ... */ } // Seems unused, can remove if confirmed
    
    private func handleStreamingResponse(stream: AsyncThrowingStream<String, Error>, messageId: UUID) async throws {
        var accumulatedContent = ""
        print("Starting stream processing for message ID: \(messageId)")
        for try await chunk in stream {
            print("Received stream chunk: \(chunk)")
            accumulatedContent += chunk
            await updateStreamingMessage(fullContent: accumulatedContent, messageId: messageId)
            print("Finished updating UI for chunk.")
        }
        // Final update to ensure no trailing cursor and content is fully set
        print("Stream finished for message ID: \(messageId). Final accumulated content size: \(accumulatedContent.count)")
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index] = ChatMessageItem(
                message: ChatMessage(id: messageId, sender: .gemini, content: accumulatedContent), // Using accumulatedContent
                attributedContent: convertToMarkdownAttributedString(accumulatedContent), // Converting accumulatedContent to AttributedString
                timestamp: messages[index].timestamp // Keep original timestamp
            )
            print("Final message update successful for ID: \(messageId)")
        } else {
            print("Error: Could not find message with ID \(messageId) for final update.")
        }
    }

    @MainActor 
    private func updateStreamingMessage(fullContent: String, messageId: UUID) {
        print("Attempting to update message ID: \(messageId). Current messages count: \(messages.count)")
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            // Add a blinking cursor effect to the streaming content
            let streamingTextWithCursor = fullContent + "▌"
            messages[index] = ChatMessageItem(
                message: ChatMessage(id: messageId, sender: .gemini, content: fullContent), // Store raw full content
                attributedContent: convertToMarkdownAttributedString(streamingTextWithCursor),
                timestamp: messages[index].timestamp // Preserve original timestamp for the message
            )
            print("Successfully updated message ID: \(messageId) at index \(index)")
        } else {
            // This case should ideally not happen if placeholder is correctly added
            print("Warning: Message with ID \(messageId) not found in messages array during update.")
            // Optionally add the message if not found (might indicate initial placeholder was missed)
            // let attributedContent = convertToMarkdownAttributedString(fullContent + "▌")
            // messages.append(ChatMessageItem(message: ChatMessage(id: messageId, sender: .gemini, content: fullContent), attributedContent: attributedContent, timestamp: MessageTimestamp()))
        }
    }
    
    private func cleanupAfterSend() async {
        print("Starting cleanupAfterSend.")
        await MainActor.run {
            streamingMessageId = nil // Clear streaming ID
            isSending = false
            // The final message content is already set in handleStreamingResponse
        }
        print("Finished cleanupAfterSend.")
    }
    
    // Helper to convert markdown string to AttributedString
    // Helper to convert markdown string to AttributedString
    private func convertToMarkdownAttributedString(_ markdownString: String) -> AttributedString {
        do {
            // 1. 规范化换行符，将 \r\n 和 \r 统一替换为 \n
            // 这一步确保了后续处理的一致性，尽管大部分现代API会直接返回 \n
            let normalizedString = markdownString.replacingOccurrences(of: "\r\n", with: "\n")
                                            .replacingOccurrences(of: "\r", with: "\n")

            // 2. 使用 MarkdownParsingOptions 来保留空白和换行
            // .inlineOnlyPreservingWhitespace 会将单个 \n 解释为可见的换行符
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            
            // 打印处理前的字符串，方便调试
            // print("begin Normalized Markdown String for AttributedString:\n\(normalizedString)")
            
            let attributedString = try AttributedString(markdown: normalizedString, options: options)
            
            // 如果需要，可以在这里检查 attributedString 的内容或属性
            // print("end Normalized Markdown String for AttributedString:\n\(attributedString)")
            
            return attributedString
        } catch {
            // 如果 Markdown 解析失败，打印错误并回退到普通字符串
            print("Error parsing markdown for AttributedString: \(error). Falling back to plain string.")
            // 确保回退时也使用规范化后的字符串
            return AttributedString(markdownString.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
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
            
            Divider() // Add a divider

            presetPromptsView // This now has its own internal padding and title
            
            inputBarView
        }
        // .padding(.bottom, 50) // This might interfere with TabView safe area. Remove if it does.
    }
}

// ChatBubble and PreviewProvider, helper function, and extensions remain mostly the same
// Ensure ChatMessage and Prompt structs are defined or imported.
// For PreviewProvider, ensure you pass a Binding<String?> for pendingArticleID
struct ChatBubble: View {
    let message: ChatMessage
    let attributedContent: AttributedString
    let timestamp: MessageTimestamp
    let isStreaming: Bool // To indicate if this message is currently streaming
    let onLongPress: () -> Void
    
    // Add a callback for copy action if needed within the bubble itself
    let onCopy: (String) -> Void 
    let onShare: (String) -> Void

    @State private var isPressed = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.sender == .gemini {
                Image("gemini_icon") // Assuming you have gemini_icon in your assets
                    .resizable()
                    .frame(width: 28, height: 28) // Slightly smaller icon
                    .clipShape(Circle())
            }
            
            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 4) {
                // Message Content Bubble
                Text(attributedContent) // Display the AttributedString
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.sender == .user ? Color.blue : Color(.systemGray5))
                    .foregroundColor(message.sender == .user ? .white : Color(.label))
                    .cornerRadius(16)
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.sender == .user ? .trailing : .leading) // Limit bubble width
                    .scaleEffect(isPressed ? 0.98 : 1.0) // Subtle press effect
                    .textSelection(.enabled)
                
                // Timestamp and Actions (only for Gemini messages for now)
                HStack(spacing: 12) {
                    Text(timestamp.formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if message.sender == .gemini && !isStreaming && !message.content.isEmpty { // Show actions only for non-empty, non-streaming AI messages
                        Button { onCopy(message.content) } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }
                .font(.caption) // Make action buttons smaller
                .foregroundColor(.blue)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: message.sender == .user ? .trailing : .leading)

            }
            if message.sender == .user {
                Image("user_icon") // Assuming you have a user_icon
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
            }
        }
        .padding(message.sender == .user ? .leading : .trailing, UIScreen.main.bounds.width * 0.1) // Indent non-active side
        .padding(.vertical, 4) // Reduce vertical padding between messages
        .contentShape(Rectangle()) // Ensure the whole area is tappable for long press
        .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 10) {
            onLongPress()
        } onPressingChanged: { isPressing in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { // Adjusted animation
                isPressed = isPressing
            }
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
                            timestamp: messageItem.timestamp,
                            proxy: proxy // Pass proxy if needed by messageRow
                        )
                    }
                }
                .padding(.horizontal, 10) // Consistent horizontal padding
                .padding(.top, 10)
                // .padding(.bottom, inputHeight + 16) // Padding at bottom handled by overall layout
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
        // .frame(maxHeight: .infinity) // Let VStack manage height distribution
    }
    
    private func messageRow(
        message: ChatMessage,
        attributedContent: AttributedString,
        timestamp: MessageTimestamp,
        proxy: ScrollViewProxy // proxy might not be needed here if not used
    ) -> some View {
        ChatBubble(
            message: message,
            attributedContent: attributedContent,
            timestamp: timestamp,
            isStreaming: streamingMessageId == message.id && message.sender == .gemini,
            onLongPress: {
                selectedMessageForMenu = message
                // showingMessageMenu = true // Trigger contextMenu directly or a custom menu
            },
            onCopy: { contentToCopy in
                copyMessageContent(content: contentToCopy)
            },
            onShare: { contentToShare in
                shareContent(contentToShare)
            }
        )
        .id(message.id) // Ensure each row has a unique ID for ScrollViewReader
        // .frame(maxWidth: .infinity, alignment: message.sender == .user ? .trailing : .leading) // Handled in ChatBubble
        .contextMenu { // Using standard context menu
            Button { copyMessageContent(content: message.content) } label: { Label("复制", systemImage: "doc.on.doc") }
            if message.sender == .gemini { // Share only for Gemini messages
                Button { shareContent(message.content) } label: { Label("分享", systemImage: "square.and.arrow.up") }
            }
        }
    }
    
    private func shareContent(_ content: String) {
        let activityVC = UIActivityViewController(activityItems: [content], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }), // Get key window
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
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
            // .background(Color(.systemGray6)) // Background for the entire input bar
        }
        // .background(Material.thin) // Apply material to the whole input bar container for a modern look
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