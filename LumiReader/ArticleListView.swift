import SwiftUI
import UniformTypeIdentifiers
import CoreData
import SafariServices // Import SafariServices for opening links

struct ImportedArticle: Codable {
    let title: String
    let url: String
    let textContent: String
}

struct ArticleListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Article.importDate, ascending: false)],
        animation: .default)
    private var articles: FetchedResults<Article>
    
    @Binding var selectedTab: TabType
    
    @State private var selectedArticles: Set<ObjectIdentifier> = []
    @State private var showingBatchSummary = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    @State private var showingImportSuccess = false
    @State private var importedCount = 0
    
    @State private var showingImportOptions = false
    @State private var isImportingLocalFile = false
    @State private var showingWifiImportView = false
    
    @State private var importError: String?
    @State private var isSummarizing = false
    @State private var latestSummary: BatchSummary?
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BatchSummary.timestamp, ascending: false)],
        animation: .default)
    private var batchSummaries: FetchedResults<BatchSummary>
    
    // State to track the article selected for chat
    @State private var selectedArticleForChat: Article? = nil
    
    // Computed property for the operation toolbar
    private var operationToolbarView: some View {
        HStack(spacing: 12) {
            Button(action: selectAllArticles) {
                Text("全部选中")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.blue)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 16)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(10)
            }
            Button(action: selectFiveArticles) {
                Text("选中5篇")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.blue)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 16)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(10)
            }
            Button(action: summarizeSelectedArticles) {
                Text("批量总结")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 16)
                    .background(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.pink]), startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(10)
            }
            Button(action: deleteSelectedArticles) {
                Text("删除选中")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 16)
                    .background(Color.red)
                    .cornerRadius(10)
            }
            .disabled(selectedArticles.isEmpty || isSummarizing)
        }
    }
    
    // Computed property for the article list content
    private var articleListContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if articles.isEmpty {
                    Text("暂无文章，请点击右上角按钮导入")
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    ForEach(articles) {
                        article in
                        ArticleCard(
                            article: article,
                            isSelected: selectedArticles.contains(ObjectIdentifier(article)),
                            onSelect: { toggleArticleSelection(article) },
                            onViewOriginal: { openOriginalArticle(article) },
                            onChat: { selectedArticleForChat = article }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .background(Color.clear)
        .frame(maxHeight: .infinity)
    }
    
    var body: some View {
        ZStack {
            // 渐变背景
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(red: 0.85, green: 0.91, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    Text("文章列表")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Color(.label))
                    Spacer()
                    Button(action: {
                        showingImportOptions = true
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(Color(.gray))
                            .padding(8)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                
                // 操作工具栏
                operationToolbarView
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.5).blur(radius: 2))
                
                // 文章列表
                articleListContent
                
            }
        }
        .overlay {
            if isSummarizing {
                ZStack {
                    Color.black.opacity(0.2)
                        .edgesIgnoringSafeArea(.all)
                        .ignoresSafeArea(edges: .all)
                    
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(2.0) // Increased scale
                        
                        Text("总结中...")
                            .font(.headline) // Larger font
                            .foregroundColor(.primary)
                    }
                    .padding(20) // Padding around the loading content
                    .background(Color.white.opacity(0.9)) // Adjusted background
                    .cornerRadius(12) // Adjusted corner radius
                    .shadow(radius: 15) // Adjusted shadow
                }
            }
        }
        .background(
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(red: 0.85, green: 0.91, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        )
        .navigationTitle("文章列表")
        .navigationBarTitleDisplayMode(.inline)
        .alert("错误", isPresented: $showingError, presenting: errorMessage) { _ in
            Button("确定", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .alert("导入成功", isPresented: $showingImportSuccess) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("成功导入 \(importedCount) 篇文章。")
        }
        .sheet(isPresented: $showingImportOptions) {
            ImportOptionsView(
                onImportLocal: {
                    isImportingLocalFile = true
                    showingImportOptions = false
                },
                onImportWifi: {
                    showingWifiImportView = true
                    showingImportOptions = false
                }
            )
            .presentationDetents([.medium, .large])
        }
        .fileImporter(
            isPresented: $isImportingLocalFile,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let selectedFile: URL = try result.get().first else {
                    importError = "未选择文件"
                    showingError = true
                    return
                }
                let didStartAccessing = selectedFile.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        selectedFile.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: selectedFile)
                let decoder = JSONDecoder()
                let imported = try decoder.decode([ImportedArticle].self, from: data)

                // 使用私有上下文进行导入和保存
                let privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                privateContext.parent = viewContext // 将私有上下文的父级设置为视图上下文

                privateContext.perform { // 在私有上下文的队列中执行
                    do {
                        var currentImportedCount = 0
                        for item in imported {
                            let article = Article(context: privateContext) // 在私有上下文中创建
                            article.title = item.title
                            article.link = item.url
                            article.content = item.textContent
                            article.importDate = Date()
                            currentImportedCount += 1
                        }

                        if privateContext.hasChanges {
                            try privateContext.save() // 保存私有上下文
                        }

                        // 将更改推送到父上下文 (viewContext)
                        viewContext.performAndWait { // 在主队列执行
                            do {
                                if viewContext.hasChanges {
                                    try viewContext.save() // 保存主上下文
                                }
                                // Update UI on the main thread
                                DispatchQueue.main.async {
                                    self.importedCount = currentImportedCount
                                    self.showingImportSuccess = true
                                    self.importError = nil
                                }
                            } catch {
                                DispatchQueue.main.async {
                                    self.importError = "导入失败：保存到主上下文错误：\(error.localizedDescription)"
                                    self.showingError = true
                                }
                            }
                        }

                    } catch {
                        // Handle errors during private context operations
                        DispatchQueue.main.async {
                            self.importError = "导入失败：私有上下文操作错误：\(error.localizedDescription)"
                            self.showingError = true
                        }
                    }
                }

            } catch {
                // Handle errors during file selection or decoding
                
                // 增加对 DecodingError 的详细日志输出
                if let decodingError = error as? DecodingError {
                    print("JSON Decoding Error: \(decodingError)")
                    importError = "导入失败：JSON 解码错误：请检查文件格式是否正确。\n详细：\(decodingError.localizedDescription)"
                } else {
                    print("File Import Error: \(error)")
                    importError = "导入失败：读取或解码文件错误：\(error.localizedDescription)"
                }
                showingError = true
            }
        }
        .sheet(isPresented: $showingWifiImportView) {
            WifiImportView()
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(item: $selectedArticleForChat) { article in
            AIChatView(article: article)
                .environment(\.managedObjectContext, viewContext)
        }
    }
    
    private func selectAllArticles() {
        // Toggle select all/deselect all
        if selectedArticles.count == articles.count && !articles.isEmpty {
            selectedArticles = [] // Deselect all
        } else {
            selectedArticles = Set(articles.map { ObjectIdentifier($0) }) // Select all
        }
    }
    
    private func selectFiveArticles() {
        let unselectedArticles = articles.filter { article in
            !selectedArticles.contains(ObjectIdentifier(article))
        }
        let articlesToSelect = Array(unselectedArticles.prefix(5))
        selectedArticles.formUnion(articlesToSelect.map { ObjectIdentifier($0) })
    }
    
    private func toggleArticleSelection(_ article: Article) {
        let id = ObjectIdentifier(article)
        if selectedArticles.contains(id) {
            selectedArticles.remove(id)
        } else {
            selectedArticles.insert(id)
        }
    }
    
    private func openOriginalArticle(_ article: Article) {
        guard let urlString = article.link,
              let url = URL(string: urlString) else {
            errorMessage = "无效的文章链接"
            showingError = true
            return
        }
        UIApplication.shared.open(url)
    }
    
    private func startChat(_ article: Article) {
        // No longer shows error, navigation is handled by NavigationLink
        // Implement actual chat start logic in AIChatView.onAppear
    }

    private func summarizeSelectedArticles() {
        guard !selectedArticles.isEmpty else {
            errorMessage = "请先选择要总结的文章"
            showingError = true
            return
        }

        isSummarizing = true

        // TODO: 获取 Gemini API Key 和总结提示词
        let apiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? ""
        // Use the shared default prompt if UserDefaults is empty
        let summaryPrompt = UserDefaults.standard.string(forKey: "batchSummaryPrompt") ?? Prompt.DEFAULT_BATCH_SUMMARY_PROMPT

        guard !apiKey.isEmpty else {
            errorMessage = "请先在设置中填写 Gemini API Key"
            showingError = true
            isSummarizing = false
            return
        }

        guard !summaryPrompt.isEmpty else {
            errorMessage = "请先在设置中填写批量总结提示词"
            showingError = true
            isSummarizing = false
            return
        }

        // 准备要总结的文章数据
        let selectedArticlesData = articles.filter { selectedArticles.contains(ObjectIdentifier($0)) }
            .map { ["title": $0.title ?? "", "content": $0.content ?? ""] }

        // 调用 Gemini API 进行批量总结
        Task {
            do {
                let summary = try await GeminiService.summarizeArticles(articles: selectedArticlesData, apiKey: apiKey, summaryPrompt: summaryPrompt)

                // --- Start: Delete existing summaries before saving new one ---
                let fetchRequest: NSFetchRequest<NSFetchRequestResult> = BatchSummary.fetchRequest()
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

                try viewContext.execute(deleteRequest)
                // --- End: Delete existing summaries ---

                // 创建一个新的 BatchSummary 对象
                let newSummary = BatchSummary(context: viewContext)
                newSummary.id = UUID()
                newSummary.content = summary
                newSummary.timestamp = Date()

                // 保存到 Core Data
                try viewContext.save()
                // latestSummary = newSummary // This state is no longer needed here
                
                // Navigate to the Summary tab after successful save
                await MainActor.run { // Ensure UI update happens on the main actor
                    selectedTab = .summary
                    isSummarizing = false
                }

            } catch {
                errorMessage = "总结失败: \(error.localizedDescription)"
                showingError = true
                isSummarizing = false // Ensure loading indicator is hidden on error
            }
        }
    }

    private func deleteSelectedArticles() {
        let articlesToDelete = articles.filter { selectedArticles.contains(ObjectIdentifier($0)) }
        
        for article in articlesToDelete {
            viewContext.delete(article)
        }
        
        do {
            try viewContext.save()
            selectedArticles = [] // Clear selection after deletion
        } catch {
            // Handle the error appropriately
            print("Error deleting articles: \(error)")
            errorMessage = "删除文章失败: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// MARK: - 文章卡片
struct ArticleCard: View {
    let article: Article
    let isSelected: Bool
    let onSelect: () -> Void
    let onViewOriginal: () -> Void
    let onChat: () -> Void
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    var body: some View {
        HStack(spacing: 14) {
            Button(action: onSelect) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .resizable()
                    .frame(width: 22, height: 22)
                    .foregroundColor(isSelected ? Color.blue : Color.gray.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title ?? "无标题")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(.label))
                    .lineLimit(2)
                Text("导入日期: \(article.importDate != nil ? dateFormatter.string(from: article.importDate!) : "-")")
                    .font(.system(size: 12))
                    .foregroundColor(Color(.systemGray))
            }
            Spacer()
            Button(action: onViewOriginal) {
                Image(systemName: "safari")
                    .font(.system(size: 20))
                    .foregroundColor(Color(.gray))
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            Button(action: onChat) {
                Text("对话")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 18)
                    .background(LinearGradient(gradient: Gradient(colors: [Color.purple, Color.pink]), startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(16)
                    .shadow(color: Color.pink.opacity(0.18), radius: 4, x: 0, y: 2)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.8))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - 导入方式选择 Sheet View
struct ImportOptionsView: View {
    let onImportLocal: () -> Void
    let onImportWifi: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                Button("从本地文件导入") {
                    onImportLocal()
                    dismiss()
                }
                Button("通过 WiFi 导入") {
                    onImportWifi()
                    dismiss()
                }
            }
            .navigationTitle("选择导入方式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ArticleListView_Previews: PreviewProvider {
    static var previews: some View {
        ArticleListView(selectedTab: .constant(.articleList))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
} 
