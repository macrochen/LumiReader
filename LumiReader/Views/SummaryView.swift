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

    private var playPauseImage: some View {
        Image(systemName: ttsService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
            .font(.system(size: 32))
            .foregroundColor(ttsService.isPlaying || ttsService.isPaused ? .blue : .gray)
    }

    // MARK: - 修改：ttsControlPanel 移除了进度条显示部分
    private func ttsControlPanel(processedMarkdown: String, segmentedSummaryContentForHTML: [(text: String, originalRange: NSRange)]) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button(action: {
                    if !processedMarkdown.isEmpty {
                        if ttsService.isPlaying || ttsService.isPaused {
                            ttsService.togglePlayPause()
                        } else {
                            ttsService.speak(processedMarkdown)
                        }
                    } else {
                        print("[SummaryView] No summary content to play.")
                    }
                }) {
                    playPauseImage 
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)

            // MARK: - 移除此处显示进度条和百分比的 VStack
            // if ttsService.totalCharacters > 0 && (ttsService.isPlaying || ttsService.isPaused) {
            //     VStack(spacing: 5) {
            //         ProgressView(value: ttsService.playbackProgress)
            //             .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
            //             .animation(.linear(duration: 0.1), value: ttsService.playbackProgress)
            //             .padding(.horizontal)
                    
            //         HStack {
            //             Text(String(format: "%.0f%%", ttsService.playbackProgress * 100))
            //                 .font(.caption2)
            //                 .foregroundColor(.secondary)
            //             Spacer()
            //             Text("\(ttsService.spokenCharacters)/\(ttsService.totalCharacters)")
            //                 .font(.caption2)
            //                 .foregroundColor(.secondary)
            //         }
            //         .padding(.horizontal)
            //     }
            //     .padding(.horizontal, 16)
            //     .padding(.bottom, 8)
            // }
        }
        .padding(.horizontal, 16)
    }

    @State private var needsReload = false
    @State private var showCopyToast = false

    private let markdownWebViewID = "markdownContentWebView"

    private var mainContentStack: some View {
        let latestSummaryContent = batchSummaries.first?.content ?? ""
        let (processedMarkdown, segmentedSummaryContentForHTML) = preprocessMarkdownSummary(latestSummaryContent)

        return VStack(spacing: 0) {
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 16) {
                        if batchSummaries.isEmpty {
                            Text("暂无总结内容，请在文章列表中选择文章进行批量总结。")
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 50)
                        } else if processedMarkdown.isEmpty && !batchSummaries.isEmpty {
                            Text("总结内容为空。")
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 50)
                        } else {
                            MarkdownWebView(
                                markdownText: processedMarkdown, // 传递实时计算的数据
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
                                segmentedSentencesForHTML: segmentedSummaryContentForHTML, // 传递实时计算的数据，供 WebView 高亮用
                                highlightedSentenceIndex: $currentHighlightedSentenceIndex,
                                onScrollToSentence: { offsetTop in
                                    guard self.markdownViewHeight > 0 else { return }
                                    let relativeY = offsetTop / self.markdownViewHeight
                                    let anchorPoint = UnitPoint(x: 0.5, y: relativeY)
                                    withAnimation(.easeOut) {
                                        proxy.scrollTo(markdownWebViewID, anchor: anchorPoint)
                                    }
                                }
                            )
                            .id(markdownWebViewID)
                            .frame(minHeight: markdownViewHeight)
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .onChange(of: batchSummaries.first?.content) { oldContent, newContent in
                        if newContent != oldContent {
                            print("Summary content changed! Resetting TTS and scroll position.")
                            ttsService.stop()
                            
                            withAnimation(.easeOut) {
                                proxy.scrollTo(markdownWebViewID, anchor: .top)
                            }
                        }
                    }
                }
                .background(Color.clear)
            }
            
            // 传递实时计算的数据给控制面板
            ttsControlPanel(processedMarkdown: processedMarkdown, segmentedSummaryContentForHTML: segmentedSummaryContentForHTML)
                .padding(.top, 8)
        }
        .padding(.top, UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0)
    }

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

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.92, green: 0.96, blue: 1.0), Color(red: 0.88, green: 0.93, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            mainContentStack 
            
            toastOverlayView 
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