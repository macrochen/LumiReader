import SwiftUI
import CoreData
import UIKit
import AVFoundation

// MARK: - 辅助结构体和枚举定义 (位于文件顶部，确保可见性)

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
    
    init(message: ChatMessage, attributedContent: AttributedString, timestamp: MessageTimestamp) {
        self.id = message.id
        self.message = message
        self.attributedContent = attributedContent
        self.timestamp = timestamp
    }
    
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

// MARK: - 辅助文本选择视图 (已移动到文件顶部)

// 用于包装 AttributedString 并使其遵循 Identifiable
struct SelectableContent: Identifiable {
    let id = UUID()
    let attributedContent: AttributedString
    let fontSize: CGFloat
}

// 用于在模态视图中显示可选择文本的 UIViewRepresentable
struct SelectableTextViewRepresentable: UIViewRepresentable {
    let attributedText: NSAttributedString
    @Binding var textView: UITextView
    let fontSize: CGFloat
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.font = UIFont.systemFont(ofSize: fontSize)
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = attributedText
        uiView.isSelectable = true
        uiView.isScrollEnabled = true
        uiView.font = UIFont.systemFont(ofSize: fontSize)
    }
}

// 用于模态显示的文本选择视图
struct SelectTextView: View {
    @Environment(\.dismiss) var dismiss
    let contentToSelect: AttributedString
    let fontSize: CGFloat
    
    @State private var textView = UITextView()
    
    private var nsAttributedString: NSAttributedString {
        return NSAttributedString(contentToSelect as Foundation.AttributedString)
    }
    
    init(attributedContent: AttributedString, fontSize: CGFloat) {
        self.contentToSelect = attributedContent
        self.fontSize = fontSize
    }
    
    var body: some View {
        NavigationView {
            VStack {
                SelectableTextViewRepresentable(attributedText: nsAttributedString, textView: $textView, fontSize: fontSize)
                    .padding()
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

// MARK: - AIChatView 主视图

struct AIChatView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) var dismiss
    
    @Binding var article: Article?
    @Binding var selectedTab: TabType
    let previousTabType: TabType?
    
    @State private var includeHistory: Bool = false
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Article.importDate, ascending: false)],
        animation: .default)
    private var articles: FetchedResults<Article>
    
    @State private var selectedArticle: Article?
    
    @State private var messages: [ChatMessageItem] = []
    @State private var inputText: String = ""
    @State private var isSending = false
    
    @State private var selectedPrompts: Set<Prompt> = []
    @AppStorage("presetPromptsData") private var presetPromptsData: Data = Data()
    @State private var presetPrompts: [Prompt] = Prompt.DEFAULT_PRESET_PROMPTS
    
    @State private var clipboardContent: String = ""
    
    @State private var chatError: ChatError? = nil

    @State private var retryMessageContent: String? = nil
    @State private var showingRetryIcon: Bool = false
    
    @State private var lastFailedMessage: String?
    
    @State private var isInputFocused: Bool = false
    @State private var inputHeight: CGFloat = 35
    @State private var isComposing: Bool = false
    
    @State private var selectedMessageForMenu: ChatMessage?
    @State private var showingMessageMenu = false
    
    @State private var appearCount = 0

    @State private var streamingMessageId: UUID? = nil
    @State private var streamingContent: String = ""
    
    @State private var selectedMessageContentToSelect: SelectableContent? = nil 
    
    @AppStorage("chatSummaryFontSize") private var chatSummaryFontSize: Double = 15.0

    @Binding var dragOffset: CGSize
    @State private var currentDragTranslation: CGSize = .zero

    // MARK: - 引入 TTSService
    @StateObject private var ttsService = TTSService.shared

    // MARK: - 复制成功浮窗状态
    @State private var showCopyToast = false
    @State private var copyToastMessage: String = ""

    init(article: Binding<Article?>, selectedTab: Binding<TabType>, previousTabType: TabType?, dragOffset: Binding<CGSize>) {
        self._article = article
        self._selectedTab = selectedTab
        self._dragOffset = dragOffset
        self._currentDragTranslation = State(initialValue: .zero)
        self.previousTabType = previousTabType
        self._selectedArticle = State(initialValue: article.wrappedValue)
    }
    
    @ViewBuilder
    private var presetPromptsView: some View {
        if !presetPrompts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
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
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(isSelected ? .white : (isExclusive ? Color.orange : Color.blue) )
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(isSelected ? (isExclusive ? Color.orange.opacity(0.8) : Color.blue.opacity(0.8)) : Color(.systemGray5))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            }
            .padding(.top, 6)
        }
    }
    
    private func togglePromptSelection(prompt: Prompt, isExclusive: Bool) {
        if isExclusive {
            if selectedPrompts.contains(prompt) {
                selectedPrompts.removeAll()
            } else {
                // MARK: - 修复：selectedPromalls -> selectedPrompts
                selectedPrompts.removeAll() 
                selectedPrompts.insert(prompt)
            }
        } else {
            if let exclusivePrompt = selectedPrompts.first(where: { $0.title.lowercased().contains("[x]") }) {
                selectedPrompts.remove(exclusivePrompt)
            }
            if selectedPrompts.contains(prompt) {
                selectedPrompts.remove(prompt)
            } else {
                selectedPrompts.insert(prompt)
            }
        }
    }
    
    @ViewBuilder
    private var articlePickerContent: some View {
        Text("-- 选择文章开始对话 --").tag(nil as Article?)
        ForEach(articles) { articleItem in
            Text(articleItem.title ?? "无标题").tag(articleItem as Article?)
        }
    }
    
    @ViewBuilder
    private func primaryContentView(fontSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            Picker("选择文章开始对话", selection: $selectedArticle) {
                articlePickerContent
            }
            .pickerStyle(MenuPickerStyle())
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .onChange(of: selectedArticle) { newArticle in
                if let newArticle = newArticle {
                    messages = []
                    inputText = ""
                    chatError = nil
                    article = newArticle
                    ttsService.stop() // 文章改变时停止 TTS 朗读
                }
            }

            Divider()

            chatContentListView(fontSize: fontSize)
            .frame(maxHeight: .infinity)

            Divider()

            presetPromptsView

            inputBarView
        }
        .sheet(item: $selectedMessageContentToSelect) { contentToSelectWrapper in
            SelectTextView(attributedContent: contentToSelectWrapper.attributedContent, fontSize: contentToSelectWrapper.fontSize)
        }
    }
    
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(red: 0.85, green: 0.91, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            primaryContentView(fontSize: CGFloat(chatSummaryFontSize))

            // 复制成功浮窗视图
            toastOverlayView
        }
        .overlay(alignment: .topTrailing) {
            GeometryReader { geometry in
                if let previousTab = previousTabType {
                    Button(action: {
                        selectedTab = previousTab
                        ttsService.stop() // 返回前一个 Tab 时停止 TTS 朗读
                    }) {
                        Image(systemName: previousTab == .source ? "list.bullet.rectangle.fill" : "text.magnifyingglass")
                            .font(.system(size: 20))
                            .padding(10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                            .shadow(radius: 8)
                    }
                    .offset(x: dragOffset.width + currentDragTranslation.width, y: dragOffset.height + currentDragTranslation.height)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                currentDragTranslation = value.translation
                            }
                            .onEnded { value in
                                dragOffset.width += value.translation.width
                                dragOffset.height += value.translation.height
                                currentDragTranslation = .zero
                            }
                    )
                    .zIndex(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .onAppear {
                        if dragOffset == .zero {
                            let buttonHeight: CGFloat = 45
                            let middleY = geometry.size.height / 2
                            let initialVerticalOffset = middleY - (buttonHeight / 2)
                            dragOffset = CGSize(width: 0, height: initialVerticalOffset)
                        }
                    }
                } else {
                    // print("【浮窗】previousTabType 为 nil，不显示浮窗")
                }
            }
        }
        .onAppear {
            appearCount += 1
            loadPrompts()
            if selectedArticle?.objectID != article?.objectID {
                selectedArticle = article
                if article != nil {
                    messages = []
                    inputText = ""
                    chatError = nil
                    ttsService.stop()
                }
            }
        }
        .onChange(of: article) { newArticleFromBinding in
            if selectedArticle?.objectID != newArticleFromBinding?.objectID {
                selectedArticle = newArticleFromBinding
                if newArticleFromBinding != nil {
                    messages = []
                    inputText = ""
                    chatError = nil
                    ttsService.stop()
                }
            }
        }
        .alert(item: $chatError) { error in
             Alert(
                 title: Text(error.errorDescription ?? "错误"),
                 message: Text(error.recoverySuggestion ?? "请稍后重试。"),
                 primaryButton: .default(Text("重试"), action: {
                     if let contentToRetry = retryMessageContent {
                         sendMessage(with: contentToRetry)
                     }
                 }),
                 secondaryButton: .cancel(Text("关闭"))
             )
         }
        .onDisappear {
            ttsService.stop()
        }
    }
    
    private func loadPrompts() {
        if let decoded = try? JSONDecoder().decode([Prompt].self, from: presetPromptsData) {
            if !decoded.isEmpty {
                presetPrompts = decoded
            } else {
                presetPrompts = Prompt.DEFAULT_PRESET_PROMPTS
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

        retryMessageContent = trimmedInput
        showingRetryIcon = false

        inputText = ""
        selectedPrompts = []

        let aiMessageId = UUID()
        streamingMessageId = aiMessageId
        streamingContent = ""

        let apiHistory = includeHistory ? messages.map { $0.message } : []

        Task {
            do {
                let stream = try await GeminiService.chatWithGemini(
                    articleContent: articleToChat.content ?? "",
                    history: apiHistory,
                    newMessage: trimmedInput,
                    apiKey: apiKey
                )

                try await handleStreamingResponse(stream: stream, messageId: aiMessageId, userMessageContent: trimmedInput)

                await cleanupAfterSend()

            } catch {
                await MainActor.run {
                    handleError(error)
                    showingRetryIcon = true
                }
            }
        }
    }
    
    private func copyMessageContent(content: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = content
        #endif
        showCopyToast(message: "已复制")
    }
    
    private func updateInputTextFromSelection() {
        var combinedText = ""
        let sortedPrompts = selectedPrompts.sorted { $0.title < $1.title }
        
        if selectedPrompts.count == 1, let prompt = selectedPrompts.first, prompt.title.lowercased().contains("[x]") {
            #if canImport(UIKit)
            if let clipboardString = UIPasteboard.general.string, !clipboardString.isEmpty {
                combinedText = prompt.content.replacingOccurrences(of: "[x]", with: clipboardString, options: .caseInsensitive)
            } else {
                combinedText = prompt.content.replacingOccurrences(of: "[x]", with: "", options: .caseInsensitive)
            }
            #else
            combinedText = prompt.content.replacingOccurrences(of: "[x]", with: "", options: .caseInsensitive)
            #endif
        } else {
            combinedText = sortedPrompts.map { $0.content }.joined(separator: "\n\n")
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
                switch geminiError { // 编译错误就是在这里
                case .networkError(let description):
                    return .networkError(description)
                case .apiError(let message):
                    return .apiError(message)
                case .invalidAPIKey:
                    return .invalidApiKey
                case .emptyResponse:
                    return .emptyResponse
                case .httpError(let statusCode):
                    return .apiError("HTTP Status Code: \(statusCode)")
                case .unknown(let underlyingError):
                    // 尝试提取更具体的错误信息，或者直接使用 localizedDescription
                    if let concreteError = underlyingError as? LocalizedError {
                        return .unknown(concreteError.errorDescription ?? underlyingError.localizedDescription)
                    }
                    return .unknown(underlyingError.localizedDescription)
                case .invalidResponseType:
                    return .unknown("API 返回了无效的响应类型。")
                case .jsonConversionError(let description): // <-- 新增的 case 处理
                    return .apiError("数据处理失败: JSON 转换错误 - \(description)")
                }
            } else {
                return .unknown(error.localizedDescription)
            }
        }()
        
        self.chatError = specificError
    }
    
    private func cleanupAfterSend() async {
        await MainActor.run { streamingMessageId = nil; isSending = false }
    }

    private func copyArticleAndResponse(attributedContent: AttributedString, articleTitle: String?, articleLink: String?) {
        var combinedContent = ""
        combinedContent += "《\(articleTitle ?? "无标题")》\n"
        if let link = articleLink, !link.isEmpty {
            combinedContent += "\(link)\n"
        }
        combinedContent += NSAttributedString(attributedContent).string

        #if canImport(UIKit)
        UIPasteboard.general.string = combinedContent
        #endif
        showCopyToast(message: "文章和回复已复制！")
    }

    private func handleStreamingResponse(stream: AsyncThrowingStream<String, Error>, messageId: UUID, userMessageContent: String) async throws {
        var receivedContent = ""
        let userMessageId = UUID()

        let attributedUserContent = convertToMarkdownAttributedString(userMessageContent)
        let userMessageItem = ChatMessageItem(message: ChatMessage(id: userMessageId, sender: .user, content: userMessageContent), attributedContent: attributedUserContent, timestamp: MessageTimestamp())
        await MainActor.run { messages.append(userMessageItem) }

        let placeholderAttributedContent = convertToMarkdownAttributedString("▌")
        let placeholderAIMessageItem = ChatMessageItem(message: ChatMessage(id: messageId, sender: .gemini, content: ""), attributedContent: placeholderAttributedContent, timestamp: MessageTimestamp())
        await MainActor.run { messages.append(placeholderAIMessageItem) }

        do {
            for try await chunk in stream {
                receivedContent += chunk
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == messageId }) {
                        let updatedMessageItem = ChatMessageItem(
                            message: ChatMessage(id: messageId, sender: .gemini, content: receivedContent),
                            attributedContent: convertToMarkdownAttributedString(receivedContent + "▌"),
                            timestamp: messages[index].timestamp
                        )
                        messages[index] = updatedMessageItem
                    }
                }
            }

            await MainActor.run {
                if let index = messages.firstIndex(where: { $0.id == messageId }) {
                    let finalMessageItem = ChatMessageItem(
                        message: ChatMessage(id: messageId, sender: .gemini, content: receivedContent),
                        attributedContent: convertToMarkdownAttributedString(receivedContent),
                        timestamp: messages[index].timestamp
                    )
                    messages[index] = finalMessageItem
                }
                retryMessageContent = nil
                showingRetryIcon = false
            }

        } catch {
            await MainActor.run {
                if let index = messages.firstIndex(where: { $0.id == messageId }) {
                     messages.remove(at: index)
                }
            }
            throw error
        }
    }

    private func retrySendMessage() {
        guard let contentToRetry = retryMessageContent, !isSending, let articleToChat = selectedArticle else {
            return
        }
        retryMessageContent = nil
        showingRetryIcon = false
        sendMessage(with: contentToRetry)
    }

    private func sendMessage(with content: String) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSending, let articleToChat = selectedArticle else {
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
         showingRetryIcon = false

         let aiMessageId = UUID()
         streamingMessageId = aiMessageId
         streamingContent = ""

         let apiHistory = messages.map { $0.message }

         Task {
             do {
                 let stream = try await GeminiService.chatWithGemini(
                     articleContent: articleToChat.content ?? "",
                     history: apiHistory,
                     newMessage: content,
                     apiKey: apiKey
                 )

                 try await handleStreamingResponse(stream: stream, messageId: aiMessageId, userMessageContent: content)

                 await cleanupAfterSend()

             } catch {
                 await MainActor.run {
                     handleError(error)
                     retryMessageContent = content
                     showingRetryIcon = true
                 }
             }
         }
    }

    @ViewBuilder
    private func RetryIconView(for messageItem: ChatMessageItem) -> some View {
        if showingRetryIcon && messageItem.message.sender == .user && messageItem.message.content == retryMessageContent {
             Button(action: retrySendMessage) {
                 Image(systemName: "arrow.clockwise.circle.fill")
                     .foregroundColor(.red)
             }
             .padding(.leading, 4)
             .buttonStyle(PlainButtonStyle())
        }
    }

    private func convertToMarkdownAttributedString(_ markdownString: String) -> AttributedString {
        do {
            let normalizedString = markdownString.replacingOccurrences(of: "\r\n", with: "\n")
                                            .replacingOccurrences(of: "\r", with: "\n")
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            return try AttributedString(markdown: normalizedString, options: options)
        } catch {
            return AttributedString(markdownString.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        }
    }

    private func speakAIMessage(_ messageContent: String) {
        ttsService.speak(messageContent)
    }

    // MARK: - 复制成功浮窗视图
    private var toastOverlayView: some View {
        Group {
            if showCopyToast {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(copyToastMessage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 24)
                            .background(Color.black.opacity(0.85))
                            .cornerRadius(20)
                        Spacer()
                    }
                    .padding(.bottom, 60)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: showCopyToast)
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - 显示复制成功浮窗的辅助函数
    private func showCopyToast(message: String) {
        copyToastMessage = message
        showCopyToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            showCopyToast = false
        }
    }
}

// MARK: - 视图分解 Extension

extension AIChatView {
    @ViewBuilder private func chatContentListView(fontSize: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) { 
                    ForEach(messages) { messageItem in
                        messageRow(
                            message: messageItem.message,
                            attributedContent: messageItem.attributedContent,
                            timestamp: messageItem.timestamp,
                            fontSize: fontSize 
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }
            .onChange(of: messages.count) { _ in 
                if let lastMessage = messages.last {
                    DispatchQueue.main.async { 
                        withAnimation(.spring()) { 
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color.clear)
    }
    
    private func messageRow(
        message: ChatMessage,
        attributedContent: AttributedString,
        timestamp: MessageTimestamp,
        fontSize: CGFloat 
    ) -> some View {
        ChatBubble(
            message: message,
            attributedContent: attributedContent,
            timestamp: timestamp,
            isStreaming: streamingMessageId == message.id && message.sender == .gemini,
            fontSize: fontSize,
            showingSelectTextView: $showingMessageMenu,
            selectedMessageContentToSelect: $selectedMessageContentToSelect,
            onCopyMessage: {
                contentToCopy in
                copyMessageContent(content: contentToCopy) 
            },
            onCopyArticleAndMessage: { content, title, link in
                copyArticleAndResponse(attributedContent: content, articleTitle: title, articleLink: link) 
            },
            onSpeakAIMessage: { content in
                speakAIMessage(content)
            },
            articleTitle: selectedArticle?.title,
            articleLink: selectedArticle?.link
        )
        .id(message.id)
        .frame(maxWidth: UIScreen.main.bounds.width * 0.75)  
        .onChange(of: message) { newMessage in
        }
    }
    
    @ViewBuilder
    private var inputBarView: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 10) {

                TextEditor(text: $inputText)
                    .frame(minHeight: inputHeight, maxHeight: 120)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .font(.system(size: 16))
                    .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification)) { _ in isInputFocused = true }
                    .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidEndEditingNotification)) { _ in isInputFocused = false }
                    .onChange(of: inputText) { newValue in
                        let newHeight = calculateTextEditorHeight(text: newValue)
                        if abs(inputHeight - newHeight) > 1 {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                inputHeight = newHeight
                            }
                        }
                        isComposing = !newValue.isEmpty
                    }
                    .overlay(alignment: .topLeading) {
                         if inputText.isEmpty {
                             Text("输入您的问题...")
                                 .foregroundColor(Color(.placeholderText))
                                 .font(.system(size: 16))
                                 .padding(.horizontal, 12)
                                 .padding(.vertical, 10)
                                 .allowsHitTesting(false)
                         }
                     }

                    VStack(spacing: 8) {
                        Button(action: {
                            includeHistory.toggle()
                        }) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 24))
                                .foregroundColor(includeHistory ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)

                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                        }
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }
    
    private func calculateTextEditorHeight(text: String) -> CGFloat {
        let textView = UITextView()
        textView.text = text
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        let fixedWidth = UIScreen.main.bounds.width - 24 /* H paddings */ - 32 /* Button width */ - 10 /* Spacing */ - 16 /* TextEditor internal H paddings */
        let size = textView.sizeThatFits(CGSize(width: fixedWidth, height: .greatestFiniteMagnitude))
        return min(max(35, size.height), 120)
    }
}


// MARK: - ChatBubble 结构体

struct ChatBubble: View {
    let message: ChatMessage
    let attributedContent: AttributedString
    let timestamp: MessageTimestamp
    let isStreaming: Bool // 指示当前消息是否正在流式输出
    
    let fontSize: CGFloat // 接收字体大小设置
    
    @Binding var showingSelectTextView: Bool
    @Binding var selectedMessageContentToSelect: SelectableContent?
    let onCopyMessage: (String) -> Void // 用于复制纯文本消息内容
    let onCopyArticleAndMessage: (AttributedString, String?, String?) -> Void // 用于复制文章信息+消息内容
    
    let onSpeakAIMessage: (String) -> Void // 朗读 AI 消息的闭包
    
    let articleTitle: String?
    let articleLink: String?
    
    @GestureState private var isReadButtonPressing: Bool = false
    @GestureState private var isCopyMessageButtonPressing: Bool = false
    @GestureState private var isCopyArticleButtonPressing: Bool = false

    // MARK: - 新增：用于控制用户消息折叠状态的 State 变量
    @State private var isUserMessageExpanded: Bool = false
    // 默认折叠的行数阈值
    private let collapsedLineLimit: Int = 1 
    // 文本内容长度阈值，超过这个长度才可能折叠
    private let contentLengthThreshold: Int = 50 // 比如50个字符
    
    private var bubbleFont: UIFont {
        return UIFont.systemFont(ofSize: fontSize)
    }

    private var bubbleTextColor: UIColor {
        return message.sender == .user ? UIColor.white : UIColor.label
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.sender == .user {
                Spacer() // 用户消息靠右对齐
            }

            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 4) {
                // MARK: - 修改：用户消息的文本显示逻辑，实现折叠
                if message.sender == .user {
                    Text(attributedContent)
                        .textSelection(.enabled)
                        .font(.system(size: fontSize))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue) // 用户消息背景
                        .cornerRadius(16)
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.9, alignment: .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        // MARK: - 折叠/展开逻辑应用在这里
                        .lineLimit(isUserMessageExpanded ? nil : collapsedLineLimit) // 根据状态设置行数限制
                        .overlay(alignment: .bottomTrailing) { // “展开”按钮的定位
                            // 只有当消息是用户发送的，且内容长度超过阈值，且当前未展开时才显示“展开”按钮
                            if message.sender == .user && message.content.count > contentLengthThreshold && !isUserMessageExpanded {
                                Button("展开") {
                                    withAnimation(.easeOut) {
                                        isUserMessageExpanded = true
                                    }
                                }
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.8))
                                .cornerRadius(8)
                                .offset(x: -8, y: -4) // 稍微向上/左偏移，避免与内容重叠
                            }
                        }
                } else { // AI 消息保持不变
                    Text(attributedContent)
                        .textSelection(.enabled)
                        .font(.system(size: fontSize))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5)) // AI 消息背景
                        .cornerRadius(16)
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.9, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // 时间戳和操作按钮区域
                HStack(spacing: 12) {
                    Text(timestamp.formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    // 仅当是 AI 消息且内容不为空且非流式输出时，显示朗读和复制按钮
                    if message.sender == .gemini && !message.content.isEmpty && !isStreaming {
                        Button(action: {
                            onSpeakAIMessage(message.content)
                        }) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .sensoryFeedback(.impact(weight: .light), trigger: isReadButtonPressing) 
                        .scaleEffect(isReadButtonPressing ? 0.85 : 1.0) 
                        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isReadButtonPressing) 
                        .simultaneousGesture( 
                            DragGesture(minimumDistance: 0)
                                .updating($isReadButtonPressing) { value, state, _ in
                                    state = true
                                }
                        )
                        
                        Button {
                            onCopyMessage(message.content)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .sensoryFeedback(.impact(weight: .light), trigger: isCopyMessageButtonPressing)
                        .scaleEffect(isCopyMessageButtonPressing ? 0.85 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isCopyMessageButtonPressing)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .updating($isCopyMessageButtonPressing) { value, state, _ in
                                    state = true
                                }
                        )
                        
                        Button {
                            onCopyArticleAndMessage(attributedContent, articleTitle, articleLink)
                        } label: {
                            Image(systemName: "doc.on.clipboard.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .sensoryFeedback(.impact(weight: .light), trigger: isCopyArticleButtonPressing)
                        .scaleEffect(isCopyArticleButtonPressing ? 0.85 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isCopyArticleButtonPressing)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .updating($isCopyArticleButtonPressing) { value, state, _ in
                                    state = true
                                }
                        )
                    } else if message.sender == .user {
                        // MARK: - 用户消息：如果已展开且内容超过阈值，显示“收起”按钮
                        if isUserMessageExpanded && message.content.count > contentLengthThreshold {
                            Button("收起") {
                                withAnimation(.easeOut) {
                                    isUserMessageExpanded = false
                                }
                            }
                            .font(.caption2)
                            .foregroundColor(.blue) // 收起按钮可以是蓝色
                        }
                    }
                }
                .font(.caption) 
                .foregroundColor(.blue) 
                .padding(.top, 2) 
                .frame(maxWidth: .infinity, alignment: message.sender == .user ? .trailing : .leading)
                .layoutPriority(0) 
            }

            if message.sender == .gemini {
                Spacer() 
            }
        }
        .padding(message.sender == .user ? .leading : .trailing, UIScreen.main.bounds.width * 0.05)
        .padding(.vertical, 4)
        // MARK: - 长按菜单保持不变
        .contextMenu {
            Button {
                onCopyMessage(message.content)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }

            Button {
                selectedMessageContentToSelect = SelectableContent(
                    attributedContent: attributedContent,
                    fontSize: fontSize 
                )
            } label: {
                Label("选中文字", systemImage: "text.cursor")
            }
        }
    }
}


// MARK: - PreviewProvider
struct AIChatView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.title = "示例文章标题"
        article.content = "这是一段很长的示例文章内容，旨在测试多行文本显示和 TTS 朗读功能。AI的回答也会包含各种 Markdown 格式，例如 **粗体**、*斜体* 和 `代码块`。这是一个测试，测试测试测试。这是一段测试朗读，看看有没有声音。这是一段测试朗读，看看有没有声音。这是一段测试朗读，看看有没有声音。这是一段测试朗读，看看有没有声音。这是一段测试朗读，看看有没有声音。"
        try? context.save()
        
        return Group {
            AIChatView(article: .constant(article), selectedTab: .constant(.source), previousTabType: nil, dragOffset: .constant(.zero))
                .environment(\.managedObjectContext, context)
                .previewDisplayName("With Article")
            
            AIChatView(article: .constant(nil), selectedTab: .constant(.source), previousTabType: nil, dragOffset: .constant(.zero))
                .environment(\.managedObjectContext, context)
                .previewDisplayName("No Article (Picker)")
        }
    }
}