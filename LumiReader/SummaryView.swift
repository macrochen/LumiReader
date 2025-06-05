import SwiftUI
import CoreData

struct SummaryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    // ... (FetchRequest remains the same)
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BatchSummary.timestamp, ascending: false)],
        animation: .default)
    private var batchSummaries: FetchedResults<BatchSummary>
    
    // Fetch all articles to link in MarkdownWebView
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Article.importDate, ascending: false)],
        animation: .default)
    private var allArticles: FetchedResults<Article>

    @State private var markdownViewHeight: CGFloat = 20 // Start with a small non-zero height to avoid initial layout issues
    @Binding var selectedTab: TabType // Add binding for selected tab
    @Binding var selectedArticleForChat: Article? // Add binding for selected article for chat

    // 【新增】用于读取文字大小设置
    @AppStorage("chatSummaryFontSize") private var chatSummaryFontSize: Double = 15.0

    /// 预处理 Markdown 文本，移除包裹的 ```markdown ... ``` 代码块。
    private func preprocessMarkdownSummary(_ rawSummary: String) -> String {
        // 正则表达式模式：匹配 ```markdown\n(内容)\n```
        // (?s) 标志允许 . 匹配换行符，等效于 [\s\S]
        // *? 表示非贪婪匹配
        let pattern = "(?s)```markdown\\n(.*?)\\n```"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsRange = NSRange(rawSummary.startIndex..<rawSummary.endIndex, in: rawSummary)
            
            // 查找第一个匹配项
            if let match = regex.firstMatch(in: rawSummary, options: [], range: nsRange) {
                // 捕获组的索引从1开始 (0是整个匹配)
                if match.numberOfRanges > 1 {
                    let contentRange = match.range(at: 1) // 提取第一个捕获组 (括号内的内容)
                    if let swiftRange = Range(contentRange, in: rawSummary) {
                        // print("[SummaryView] Stripped markdown code block. Original length: \(rawSummary.count), New length: \(rawSummary[swiftRange].count)")
                        return String(rawSummary[swiftRange])
                    }
                }
            }
        } catch {
            print("[SummaryView] Error creating or using regex for markdown stripping: \(error)")
        }
        
        // 如果没有匹配到代码块，或者正则出错，则返回原始文本
        // print("[SummaryView] No markdown code block found to strip, or regex error.")
        return rawSummary
    }

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(red: 0.85, green: 0.91, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea() // Keep this if you want the gradient to fill the whole screen

            VStack(spacing: 0) {
                // If you have a custom title bar or want space at the top, add it here.
                // For example, to respect the top safe area for content:
                // Spacer().frame(height: UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0)
                // Or simply add padding to the ScrollView or its content.

                ScrollView {
                    // This VStack is the direct content of the ScrollView
                    VStack(alignment: .leading, spacing: 20) {
                        if batchSummaries.isEmpty {
                            Text("暂无总结内容，请在文章列表中选择文章进行批量总结。")
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40) // Padding for empty state
                        } else {
                            if let latestSummary = batchSummaries.first {
                                let markdownContent = latestSummary.content ?? ""
                                if !markdownContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                                    // 2. 对原始 Markdown 进行预处理
                                    let processedMarkdownContent = preprocessMarkdownSummary(markdownContent)
                                    // Use MarkdownWebView with allArticles
                                    MarkdownWebView(
                                        markdownText: processedMarkdownContent,
                                        articlesToLink: Array(allArticles), // Pass all fetched articles
                                        fontSize: CGFloat(chatSummaryFontSize),
                                        dynamicHeight: $markdownViewHeight,
                                        onDialogueButtonTapped: { contextInfo in // <--- 添加了这个回调
                                            // contextInfo 应该是 Article 的唯一标识符，
                                            // 我们在 MarkdownWebView 中设置的是 article.objectID.uriRepresentation().absoluteString
                                            print("[SummaryView] Dialogue button tapped for context (Article ID URI): \(contextInfo)")

                                            // 根据 contextInfo (它是一个 URI 字符串) 查找对应的 Article 对象
                                            if let articleIDURL = URL(string: contextInfo),
                                            let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: articleIDURL),
                                            let articleForChat = try? viewContext.existingObject(with: objectID) as? Article {
                                                self.selectedArticleForChat = articleForChat // 设置选中的文章
                                                print("[SummaryView] Found article: \(articleForChat.title ?? "N/A") for chat.")
                                            } else {
                                                print("[SummaryView] Could not find article for context URI: \(contextInfo)")
                                                self.selectedArticleForChat = nil // 未找到则清空
                                            }

                                            // 切换到 AI 对话 Tab
                                            // 假设你的 TabType 枚举有一个表示 AI 对话页的 case，例如 .aiChat
                                            self.selectedTab = .aiChat // 修改这个 .aiChat 为你实际的 TabType case
                                        })
                                        .frame(height: markdownViewHeight)
                                        // .background(Color.red.opacity(0.3)) // 调试用
                                        // Ensure MarkdownView itself doesn't get unnecessary horizontal padding
                                        // The parent VStack already has horizontal padding.
                                } else {
                                    Text("总结内容为空。") // Handle empty content string
                                        .foregroundColor(.gray)
                                        .padding(.top, 20)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .padding(.bottom, 80) // Add a fixed bottom padding here
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // .background(Color.yellow.opacity(0.3)) // 调试用
                .background(Color.clear)

                // 预设提示词 和 输入框 也会在这个 VStack 中
                // presetPromptsView
                // inputBarView
            }.padding(.top)
        }
        .navigationBarHidden(true)
        // .edgesIgnoringSafeArea(.all) // Alternative to ZStack's ignoresSafeArea, apply with caution
    }
    // ... (itemFormatter and PreviewProvider remain the same)
}

// Preview Provider
struct SummaryView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext

        // Create mock data for preview
        let mockArticleA = Article(context: context)
        mockArticleA.title = "相关的文章 A"
        mockArticleA.link = "https://example.com/articleA"
        mockArticleA.content = "这是相关的文章 A 的内容。"
        mockArticleA.importDate = Date().addingTimeInterval(-100)

        let mockArticleB = Article(context: context)
        mockArticleB.title = "相关的文章 B"
        mockArticleB.link = "https://example.com/articleB"
        mockArticleB.content = "这是相关的文章 B 的内容。"
        mockArticleB.importDate = Date().addingTimeInterval(-150)

//        mockArticleB.addToBatchSummaries(mockSummary)
        
        // Add another mock article not linked to this summary, but should be searchable
        let mockArticleC = Article(context: context)
        mockArticleC.title = "不相关的文章 C"
        mockArticleC.link = "https://example.com/articleC"
        mockArticleC.content = "这是不相关的文章 C 的内容。"
        mockArticleC.importDate = Date().addingTimeInterval(-200)

        // Pass dummy bindings for the preview
        return SummaryView(selectedTab: .constant(.summary), selectedArticleForChat: .constant(nil))
    }
}
 