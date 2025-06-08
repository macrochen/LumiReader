import SwiftUI
import CoreData
import AVFoundation

struct SummaryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BatchSummary.timestamp, ascending: false)],
        animation: .default)
    private var batchSummaries: FetchedResults<BatchSummary>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Article.importDate, ascending: false)],
        animation: .default)
    private var allArticles: FetchedResults<Article>

    @State private var markdownViewHeight: CGFloat = 20
    @Binding var selectedTab: TabType
    @Binding var selectedArticleForChat: Article?

    @AppStorage("chatSummaryFontSize") private var chatSummaryFontSize: Double = 15.0

    // TTS 服务
    @StateObject private var ttsService = TTSService.shared
    
    @State private var currentHighlightedSentenceIndex: Int? = nil
    @State private var segmentedSummaryContentForHTML: [(text: String, originalRange: NSRange)] = []

    private let pattern = "(?s)```markdown\\n(.*?)\\n```"

    private func preprocessMarkdownSummary(_ rawSummary: String) -> (processedText: String, segmentedSentences: [(text: String, originalRange: NSRange)]) {
        var markdownText = rawSummary
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsRange = NSRange(rawSummary.startIndex..<rawSummary.endIndex, in: rawSummary)
            
            if let match = regex.firstMatch(in: rawSummary, options: [], range: nsRange) {
                if match.numberOfRanges > 1 {
                    let contentRange = match.range(at: 1)
                    if let swiftRange = Range(contentRange, in: rawSummary) {
                        markdownText = String(rawSummary[swiftRange])
                    }
                }
            }
        } catch {
            print("[SummaryView] Error creating or using regex for markdown stripping: \(error)")
        }

        var sentences: [(text: String, originalRange: NSRange)] = []
        (markdownText as NSString).enumerateSubstrings(in: NSRange(location: 0, length: markdownText.utf16.count), options: .bySentences) { (substring, substringRange, enclosingRange, stop) in
            if let sentence = substring, !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sentences.append((text: sentence, originalRange: substringRange))
            }
        }
        
        return (processedText: markdownText, segmentedSentences: sentences)
    }

    // MARK: - 提取播放/暂停按钮的 Image 视图为私有计算属性
    private var playPauseImage: some View {
        Image(systemName: ttsService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
            .font(.system(size: 32))
            .foregroundColor(ttsService.isPlaying || ttsService.isPaused ? .blue : .gray)
    }

    // MARK: - TTS 控制面板视图
    private var ttsControlPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button(action: {
                    if let latestSummary = batchSummaries.first,
                       let content = latestSummary.content {
                        let (textToSpeak, segments) = preprocessMarkdownSummary(content)
                        if !textToSpeak.isEmpty {
                            if ttsService.isPlaying || ttsService.isPaused {
                                ttsService.togglePlayPause()
                            } else {
                                self.segmentedSummaryContentForHTML = segments
                                ttsService.speak(textToSpeak)
                            }
                        } else {
                            print("[SummaryView] Processed text is empty, not starting TTS.")
                        }
                    } else {
                        print("[SummaryView] No summary content to play.")
                    }
                }) {
                    playPauseImage 
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("语速")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .frame(width: 40, alignment: .leading)
                        Slider(value: $ttsService.currentRate, in: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
                            .onChange(of: ttsService.currentRate) { newValue in
                                ttsService.updateRate(newValue)
                            }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)

            if ttsService.totalCharacters > 0 && (ttsService.isPlaying || ttsService.isPaused) {
                VStack(spacing: 5) {
                    ProgressView(value: ttsService.playbackProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                        .animation(.linear(duration: 0.1), value: ttsService.playbackProgress)
                        .padding(.horizontal)
                    
                    HStack {
                        Text(String(format: "%.0f%%", ttsService.playbackProgress * 100))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(ttsService.spokenCharacters)/\(ttsService.totalCharacters)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 16)
    }

    @State private var needsReload = false
    @State private var showCopyToast = false

    private let markdownWebViewID = "markdownContentWebView"

    // MARK: - 提取主内容视图 (修正结构)
    private var mainContentStack: some View {
        VStack(spacing: 0) { // <--- 这个 VStack 是 mainContentStack 的根视图
            ScrollView { // <--- ScrollView 是 VStack 的第一个子视图
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 16) {
                        if batchSummaries.isEmpty {
                            Text("暂无总结内容，请在文章列表中选择文章进行批量总结。")
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 50)
                        } else {
                            if let latestSummary = batchSummaries.first,
                               let markdownContent = latestSummary.content,
                               !markdownContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                                let (processedMarkdownContent, segments) = preprocessMarkdownSummary(markdownContent)
                                
                                MarkdownWebView(
                                    markdownText: processedMarkdownContent,
                                    articlesToLink: Array(allArticles),
                                    fontSize: CGFloat(chatSummaryFontSize),
                                    dynamicHeight: $markdownViewHeight,
                                    onDialogueButtonTapped: { contextInfo in
                                        if let articleIDURL = URL(string: contextInfo),
                                        let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: articleIDURL),
                                        let articleForChat = try? viewContext.existingObject(with: objectID) as? Article {
                                            self.selectedArticleForChat = articleForChat
                                        } else {
                                            self.selectedArticleForChat = nil
                                        }
                                        self.selectedTab = .aiChat
                                    },
                                    onAutoCopy: {
                                        showCopyToast = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                            showCopyToast = false
                                        }
                                    },
                                    segmentedSentencesForHTML: segmentedSummaryContentForHTML,
                                    highlightedSentenceIndex: $currentHighlightedSentenceIndex,
                                    // MARK: - 修复：scrollTo 参数不再包含 offset
                                    onScrollToSentence: { offsetTop in
                                        // 确保 markdownViewHeight 大于0，避免除以零
                                        guard self.markdownViewHeight > 0 else { return }

                                        // 计算句子在 WebView 中的相对Y位置 (0.0 - 1.0)
                                        let relativeY = offsetTop / self.markdownViewHeight
                                        
                                        // 创建一个 UnitPoint 作为锚点。x为0.5表示水平居中，y为相对Y位置
                                        let anchorPoint = UnitPoint(x: 0.5, y: relativeY)

                                        withAnimation(.easeOut) { // 添加动画使滚动更平滑
                                            proxy.scrollTo(markdownWebViewID, anchor: anchorPoint)
                                        }
                                    }
                                )
                                .id(markdownWebViewID)
                                .frame(minHeight: markdownViewHeight)
                                .padding(.top, 8)
                            } else {
                                Text("总结内容为空。")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 50)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                } // <--- ScrollViewReader 结束
                .background(Color.clear) // 适用于 ScrollView
                .onAppear {
                    if let latestSummary = batchSummaries.first,
                       let content = latestSummary.content {
                        let (_, segments) = preprocessMarkdownSummary(content)
                        self.segmentedSummaryContentForHTML = segments
                    } else {
                        self.segmentedSummaryContentForHTML = []
                    }
                }
                .onChange(of: batchSummaries.first?.content) { oldContent, newContent in
                    if let newContent = newContent {
                        let (_, segments) = preprocessMarkdownSummary(newContent)
                        self.segmentedSummaryContentForHTML = segments
                    } else {
                        self.segmentedSummaryContentForHTML = []
                    }
                }
            } // <--- ScrollView 结束 (这里是关键)
            
            // <--- ttsControlPanel 应该作为 VStack 的第二个子视图，与 ScrollView 同级
            ttsControlPanel
                .padding(.top, 8) // 这个 padding 适用于 ttsControlPanel
        } // <--- 这个 VStack 结束
        .padding(.top, UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0) // 这个 padding 适用于整个 mainContentStack 的根 VStack
    }

    // MARK: - 提取 Toast 视图
    private var toastOverlayView: some View {
        Group { 
            if showCopyToast {
                AnyView(
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("已复制")
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
                )
            } else {
                AnyView(EmptyView())
            }
        }
    }

    // MARK: - 简化 body
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.92, green: 0.96, blue: 1.0), Color(red: 0.88, green: 0.93, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            mainContentStack // 使用提取的主内容
            
            toastOverlayView // 使用提取的 Toast 视图
        }
        .navigationBarHidden(true)
        .onReceive(ttsService.$currentSpeakingSentenceIndex) { index in
            self.currentHighlightedSentenceIndex = index
        }
        .onDisappear {
            ttsService.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            needsReload.toggle()
        }
    }
}

struct SummaryView_Previews: PreviewProvider {
    static var previews: some View {
        SummaryView(selectedTab: .constant(.summary), selectedArticleForChat: .constant(nil))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}