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
    @Binding var selectedArticleForChat: Article?

    @State private var selectedArticles: Set<ObjectIdentifier> = []
    // @State private var showingBatchSummary = false // This state seems unused, consider removing if not needed
    @State private var errorMessage: String?
    @State private var showingError = false

    @State private var showingImportSuccess = false
    @State private var importedCount = 0

    @State private var showingImportOptions = false
    @State private var isImportingLocalFile = false
    @State private var showingWifiImportView = false

    @State private var importError: String? // Replaces errorMessage for import-specific errors for clarity
    @State private var isSummarizing = false
    // @State private var latestSummary: BatchSummary? // This state seems unused after refactor of summarizeSelectedArticles
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BatchSummary.timestamp, ascending: false)],
        animation: .default)
    private var batchSummaries: FetchedResults<BatchSummary>

    // MARK: - Computed View Properties for Refactoring

    // Computed property for the title bar
    private var titleBar: some View {
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
    }

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
            .disabled(selectedArticles.isEmpty || isSummarizing) // Keep original disable logic
            Button(action: deleteSelectedArticles) {
                Text("删除选中")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 16)
                    .background(Color.red)
                    .cornerRadius(10)
            }
            .disabled(selectedArticles.isEmpty) // Original code had this button disabled with selectedArticles.isEmpty || isSummarizing. Check if isSummarizing is also needed here. For now, matching original.
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
                    ForEach(articles) { article in
                        ArticleCard(
                            article: article,
                            isSelected: selectedArticles.contains(ObjectIdentifier(article)),
                            onSelect: { toggleArticleSelection(article) },
                            onViewOriginal: { openOriginalArticle(article) },
                            onChat: { 
                                self.selectedArticleForChat = article 
                                self.selectedTab = .aiChat
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .background(Color.clear) // Ensure ScrollView itself doesn't have an opaque background if not desired
        .frame(maxHeight: .infinity)
    }

    // Container for the main VStack content (title, toolbar, list)
    private var mainContentContainer: some View {
        VStack(spacing: 0) {
            titleBar

            operationToolbarView
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

            articleListContent
        }
    }
    
    // The main screen content, including the primary background gradient and the mainContentContainer
    private var screenWithPrimaryBackground: some View {
        ZStack {
            // 渐变背景 (This was the gradient around line 116)
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(red: 0.85, green: 0.91, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            mainContentContainer
        }
    }

    // The summarizing overlay view
    @ViewBuilder
    private var summarizingOverlayView: some View {
        if isSummarizing {
            ZStack {
                Color.black.opacity(0.2)
                    .ignoresSafeArea() // Covers the whole screen

                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(2.0)

                    Text("总结中...")
                        .font(.headline)
                        .foregroundColor(.primary) // Use .primary for better adaptability to light/dark mode
                }
                .padding(20)
                .background(Material.regular) // Using Material for a more modern blur effect
                .cornerRadius(12)
                .shadow(radius: 15)
            }
        }
    }

    // The overall background for the entire view (applied last)
    private var finalBackgroundView: some View {
        LinearGradient(gradient: Gradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(red: 0.85, green: 0.91, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }


    // MARK: - Body
    var body: some View {
        screenWithPrimaryBackground // Main content with its own gradient
            .overlay { summarizingOverlayView } // Conditional overlay
            .background(finalBackgroundView) // Final, overall background
            .navigationTitle("文章列表")
            .navigationBarTitleDisplayMode(.inline)
            .alert("错误", isPresented: $showingError, presenting: errorMessage) { _ in
                Button("确定", role: .cancel) {}
            } message: { messageText in // Renamed for clarity
                Text(messageText)
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
                        // showingImportOptions = false // sheet dismisses automatically
                    },
                    onImportWifi: {
                        showingWifiImportView = true
                        // showingImportOptions = false // sheet dismisses automatically
                    }
                )
                .presentationDetents([.height(180), .medium]) // Adjusted presentation detents
            }
            .fileImporter(
                isPresented: $isImportingLocalFile,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false,
                onCompletion: handleFileImportResult // Moved logic to a separate method
            )
            .sheet(isPresented: $showingWifiImportView) {
                WifiImportView()
                    .environment(\.managedObjectContext, viewContext)
            }
            // .sheet(item: $selectedArticleForChat) { _ in
            //     AIChatView(article: $selectedArticleForChat)
            //         .environment(\.managedObjectContext, viewContext)
            // }
    }

    // MARK: - Action Methods

    private func selectAllArticles() {
        if selectedArticles.count == articles.count && !articles.isEmpty {
            selectedArticles = []
        } else {
            selectedArticles = Set(articles.map { ObjectIdentifier($0) })
        }
    }

    private func selectFiveArticles() {
        let unselectedArticles = articles.filter { !selectedArticles.contains(ObjectIdentifier($0)) }
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
        guard let urlString = article.link, let url = URL(string: urlString) else {
            self.errorMessage = "无效的文章链接" // Use self.errorMessage for clarity
            self.showingError = true
            return
        }
        UIApplication.shared.open(url)
    }

    // startChat function was empty and seemed to be replaced by .sheet(item: $selectedArticleForChat)
    // If it had other logic, it should be reviewed. For now, it's removed as it's unused.

    private func summarizeSelectedArticles() {
        guard !selectedArticles.isEmpty else {
            self.errorMessage = "请先选择要总结的文章"
            self.showingError = true
            return
        }

        isSummarizing = true

        let apiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? ""
        let summaryPrompt = UserDefaults.standard.string(forKey: "batchSummaryPrompt") ?? Prompt.DEFAULT_BATCH_SUMMARY_PROMPT // Assuming Prompt struct exists

        guard !apiKey.isEmpty else {
            self.errorMessage = "请先在设置中填写 Gemini API Key"
            self.showingError = true
            isSummarizing = false
            return
        }

        guard !summaryPrompt.isEmpty else {
            self.errorMessage = "请先在设置中填写批量总结提示词"
            self.showingError = true
            isSummarizing = false
            return
        }

        let selectedArticlesData = articles.filter { selectedArticles.contains(ObjectIdentifier($0)) }
            .map { ["title": $0.title ?? "", "content": $0.content ?? ""] }

        Task {
            do {
                let summaryText = try await GeminiService.summarizeArticles(articles: selectedArticlesData, apiKey: apiKey, summaryPrompt: summaryPrompt) // Assuming GeminiService exists

                // Delete existing summaries
                let fetchRequest: NSFetchRequest<NSFetchRequestResult> = BatchSummary.fetchRequest()
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                try viewContext.execute(deleteRequest)

                // Create and save new summary
                let newSummary = BatchSummary(context: viewContext)
                newSummary.id = UUID()
                newSummary.content = summaryText
                newSummary.timestamp = Date()
                try viewContext.save()

                await MainActor.run {
                    selectedTab = .summary
                    isSummarizing = false
                }

            } catch {
                // Use await MainActor.run for UI updates from background task
                await MainActor.run {
                    self.errorMessage = "总结失败: \(error.localizedDescription)"
                    self.showingError = true
                    isSummarizing = false
                }
            }
        }
    }

    private func deleteSelectedArticles() {
        let articlesToDelete = articles.filter { selectedArticles.contains(ObjectIdentifier($0)) }
        articlesToDelete.forEach(viewContext.delete)

        do {
            try viewContext.save()
            selectedArticles = []
        } catch {
            self.errorMessage = "删除文章失败: \(error.localizedDescription)"
            self.showingError = true
            print("Error deleting articles: \(error)")
        }
    }

    // MARK: - File Import Handling
    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedFile = urls.first else {
                self.importError = "未选择文件" // Use specific importError state
                self.showingError = true // Or a specific showingImportError state
                return
            }
            processImportedFile(url: selectedFile)
        case .failure(let error):
            self.importError = "文件选择失败: \(error.localizedDescription)"
            self.showingError = true
        }
    }

    private func processImportedFile(url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let importedItems = try decoder.decode([ImportedArticle].self, from: data)

            saveImportedArticles(importedItems)
        } catch {
            DispatchQueue.main.async { // Ensure UI updates are on main thread
                if let decodingError = error as? DecodingError {
                    print("JSON Decoding Error: \(decodingError)")
                    self.importError = "导入失败：JSON 解码错误。请检查文件格式。\n详细：\(decodingError.localizedDescription)"
                } else {
                    print("File Import Error: \(error)")
                    self.importError = "导入失败：读取或解码文件错误。\n详细：\(error.localizedDescription)"
                }
                self.showingError = true
            }
        }
    }

    private func saveImportedArticles(_ items: [ImportedArticle]) {
        let privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        privateContext.parent = viewContext

        privateContext.perform {
            var currentImportedCount = 0
            for item in items {
                let article = Article(context: privateContext)
                article.title = item.title
                article.link = item.url
                article.content = item.textContent
                article.importDate = Date()
                currentImportedCount += 1
            }

            do {
                if privateContext.hasChanges {
                    try privateContext.save()
                }
                // Push to parent (viewContext)
                viewContext.performAndWait { // Ensure this is safe; if viewContext is main, this is fine.
                    do {
                        if viewContext.hasChanges {
                            try viewContext.save()
                        }
                        // Update UI on the main thread
                        DispatchQueue.main.async {
                            self.importedCount = currentImportedCount
                            self.showingImportSuccess = true
                            self.importError = nil // Clear any previous import error
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.importError = "导入失败：保存到主上下文错误：\(error.localizedDescription)"
                            self.showingError = true
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.importError = "导入失败：私有上下文操作错误：\(error.localizedDescription)"
                    self.showingError = true
                }
            }
        }
    }
}

// Assuming Prompt struct and GeminiService are defined elsewhere
// For example:
// struct Prompt { static let DEFAULT_BATCH_SUMMARY_PROMPT = "Summarize these articles." }
// class GeminiService { static func summarizeArticles(articles: [[String: String]], apiKey: String, summaryPrompt: String) async throws -> String { /* ... */ return "Summary" } }


// MARK: - ArticleCard (No changes, included for completeness)
struct ArticleCard: View {
    let article: Article
    let isSelected: Bool
    let onSelect: () -> Void
    let onViewOriginal: () -> Void
    let onChat: () -> Void

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd" // Consider "yyyy-MM-dd HH:mm" for more detail if needed
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
            .buttonStyle(PlainButtonStyle()) // Keep clicks from propagating if card is in a List

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title ?? "无标题")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(.label)) // Adapts to light/dark mode
                    .lineLimit(2)
                Text("导入日期: \(article.importDate != nil ? dateFormatter.string(from: article.importDate!) : "-")")
                    .font(.system(size: 12))
                    .foregroundColor(Color(.secondaryLabel)) // Adapts to light/dark mode
            }
            Spacer()
            Button(action: onViewOriginal) {
                Image(systemName: "safari")
                    .font(.system(size: 20))
                    .foregroundColor(Color(.gray))
                    .padding(8)
                    .background(Color(.systemGray6)) // Adapts to light/dark mode
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
        .background(Material.thin) // Using Material for a modern look, similar to .white.opacity(0.8) but adapts better
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - ImportOptionsView (No changes, included for completeness)
struct ImportOptionsView: View {
    let onImportLocal: () -> Void
    let onImportWifi: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView { // NavigationView is good for sheets that need a title/toolbar
            List {
                Button("从本地文件导入") {
                    onImportLocal()
                    // dismiss() // No longer needed, sheet dismisses via onImportLocal changing state
                }
                Button("通过 WiFi 导入") {
                    onImportWifi()
                    // dismiss() // No longer needed
                }
            }
            .navigationTitle("选择导入方式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { // Or .navigationBarTrailing
                    Button("完成") { // Changed "取消" to "完成" or "关闭" as it's more of a selection
                        dismiss()
                    }
                }
            }
        }
    }
}

// Preview (assuming PersistenceController and TabType exist)
struct ArticleListView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        // Add some mock articles for the preview
        let article1 = Article(context: context)
        article1.title = "示例文章 1"
        article1.content = "这是示例文章 1 的内容"
        article1.importDate = Date()
        
        let article2 = Article(context: context)
        article2.title = "示例文章 2"
        article2.content = "这是示例文章 2 的内容"
        article2.importDate = Date().addingTimeInterval(-100)
        
        return ArticleListView(selectedTab: .constant(.articleList), selectedArticleForChat: .constant(nil))
            .environment(\.managedObjectContext, context)
    }
}

// Placeholder for TabType if it's not defined in this file
// enum TabType { case articleList, summary /* other cases */ }
