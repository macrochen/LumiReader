import SwiftUI
import CoreData
import AVFoundation // <--- 新增的导入

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
    
    // 正则表达式模式 (保持不变)
    private let pattern = "(?s)```markdown\\n(.*?)\\n```"

    // 预处理 Markdown 文本 (保持不变)
    private func preprocessMarkdownSummary(_ rawSummary: String) -> String {
        // print("raw: \(rawSummary)") // 调试时可以取消注释
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsRange = NSRange(rawSummary.startIndex..<rawSummary.endIndex, in: rawSummary)
            
            if let match = regex.firstMatch(in: rawSummary, options: [], range: nsRange) {
                if match.numberOfRanges > 1 {
                    let contentRange = match.range(at: 1)
                    if let swiftRange = Range(contentRange, in: rawSummary) {
                        return String(rawSummary[swiftRange])
                    }
                }
            }
        } catch {
            print("[SummaryView] Error creating or using regex for markdown stripping: \(error)")
        }
        return rawSummary
    }

    // TTS 控制面板视图 (包含进度条)
    private var ttsControlPanel: some View {
        VStack(spacing: 12) { // 整体 VStack
            // 播放控制按钮组
            HStack(spacing: 16) { // 包含按钮和滑块的 HStack
                Button(action: {
                    if let latestSummary = batchSummaries.first,
                       let content = latestSummary.content {
                        if !ttsService.isPlaying && !ttsService.isPaused {
                            let textToSpeak = preprocessMarkdownSummary(content)
                            if !textToSpeak.isEmpty {
                                ttsService.speak(textToSpeak)
                            } else {
                                print("[SummaryView] Processed text is empty, not starting TTS.")
                            }
                        } else {
                            ttsService.togglePlayPause()
                        }
                    } else {
                        print("[SummaryView] No summary content to play.")
                    }
                }) {
                    Image(systemName: ttsService.isPlaying ? "pause.circle.fill" : (ttsService.isPaused ? "play.circle.fill" : "play.circle.fill"))
                        .font(.system(size: 32))
                        .foregroundColor(ttsService.isPlaying || ttsService.isPaused ? .blue : .gray) // 播放或暂停时为蓝色，否则灰色
                }
                
                Button(action: {
                    ttsService.stop()
                }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor( (ttsService.isPlaying || ttsService.isPaused) ? .red : .gray) // 播放或暂停时为红色，否则灰色
                }
                .disabled(!ttsService.isPlaying && !ttsService.isPaused) // 仅在播放或暂停时启用停止按钮
                
                // 语速控制
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("语速")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .frame(width: 40, alignment: .leading)
                        Slider(value: $ttsService.currentRate, in: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate) // 使用AVFoundation的范围
                            .onChange(of: ttsService.currentRate) { newValue in
                                ttsService.updateRate(newValue)
                            }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGray6)) // 使用更现代的背景色
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1) // 细微阴影

            // 朗读进度条
            if ttsService.totalCharacters > 0 && (ttsService.isPlaying || ttsService.isPaused) {
                VStack(spacing: 5) { // 包含进度条和文本的VStack
                    ProgressView(value: ttsService.playbackProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                        .animation(.linear(duration: 0.1), value: ttsService.playbackProgress) // 平滑动画
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
                .padding(.horizontal, 16) // 与按钮组的水平 padding 保持一致
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 16) // 给整个控制面板统一的水平 padding
        // .padding(.vertical, 8) // 这个可以根据整体布局调整
    }

    @State private var needsReload = false
    @State private var showCopyToast = false // 新增：Toast显示标志

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.92, green: 0.96, blue: 1.0), Color(red: 0.88, green: 0.93, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
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

                                let processedMarkdownContent = preprocessMarkdownSummary(markdownContent)
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
                                    }
                                )
                                .id(needsReload)
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
                }
                .background(Color.clear)
                
                ttsControlPanel
                    .padding(.top, 8)
            }
            .padding(.top, UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0)

            // Toast 提示
            if showCopyToast {
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
            }
        }
        .navigationBarHidden(true)
        .onDisappear {
            // 当视图消失时，可以选择停止 TTS，防止在其他页面继续播放
            // if ttsService.isPlaying || ttsService.isPaused {
            //     ttsService.stop()
            // }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            needsReload.toggle()
        }
    }
}

// Preview Provider (保持不变，但确保 TTSService 能够被 preview 环境访问，通常单例会自动工作)
struct SummaryView_Previews: PreviewProvider {
    static var previews: some View {
        // ... (你的 Preview 代码保持不变)
        SummaryView(selectedTab: .constant(.summary), selectedArticleForChat: .constant(nil))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
