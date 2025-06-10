import SwiftUI
import UniformTypeIdentifiers
import CoreData
import SafariServices


struct ImportedArticle: Codable {
    let title: String
    let url: String
    let textContent: String
}

struct SourceView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    // 使用新的 ViewModel 来管理文章数据
    @StateObject private var viewModel: SourceViewModel

    // 这个 FetchRequest 仍然可以保留，用于统计总数
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Article.importDate, ascending: false)],
        animation: .default)
    private var allArticles: FetchedResults<Article>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Article.importDate, ascending: false)],
        predicate: NSPredicate(format: "importDate >= %@", Calendar.current.startOfDay(for: Date()) as NSDate),
        animation: .default)
    private var todayArticles: FetchedResults<Article>

    @Binding var selectedTab: TabType
    @Binding var selectedArticleForChat: Article?

    @State private var selectedArticles: Set<ObjectIdentifier> = []
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingImportSuccess = false
    @State private var importedCount = 0
    @State private var isImportingLocalFile = false

    @State private var totalDeletedCount: Int = UserDefaults.standard.integer(forKey: "totalDeletedCount")
    @State private var todayDeletedCount: Int = UserDefaults.standard.integer(forKey: "todayDeletedCount")
    @State private var lastResetDate: Date = UserDefaults.standard.object(forKey: "lastResetDate") as? Date ?? Date()

    @State private var importError: String?
    @State private var isSummarizing = false
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BatchSummary.timestamp, ascending: false)],
        animation: .default)
    private var batchSummaries: FetchedResults<BatchSummary>
    
    init(selectedTab: Binding<TabType>, selectedArticleForChat: Binding<Article?>) {
        _selectedTab = selectedTab
        _selectedArticleForChat = selectedArticleForChat
        let context = PersistenceController.shared.container.viewContext
        _viewModel = StateObject(wrappedValue: SourceViewModel(context: context))
    }

    // MARK: - UI Views

    private var titleBar: some View {
        HStack {
            Text("") // 保持这个空文本和 Spacer，以维持原有布局和可能未来的标题位置
                .font(.system(size: 22, weight: .semibold))
            Spacer()
            // 【移除】导入按钮已从这里移走
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private var operationToolbarView: some View {
        HStack(spacing: 12) {
            // 【新增】导入按钮放在最左边，并调整样式使其区分
            Button(action: {
                isImportingLocalFile = true
            }) {
                Image(systemName: "square.and.arrow.down") // 导入图标
                    .font(.system(size: 20, weight: .medium)) // 调整字体大小使其与底部按钮更协调
                    .foregroundColor(Color(.secondaryLabel)) // 使用更中性的颜色
                    .padding(10) // 调整内边距
                    .background(Color(.systemBackground)) // 使用系统背景色，看起来更“干净”
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(.systemGray4), lineWidth: 1)) // 添加一个细边框增加质感
            }
            
            Button(action: selectAllArticles) {
                Text("全选")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.blue)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 16)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(10)
            }
            Button(action: selectFiveArticles) {
                Text("选5")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.blue)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 16)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(10)
            }
            Button(action: summarizeSelectedArticles) {
                Text("总结")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 16)
                    .background(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.pink]), startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(10)
            }
            .disabled(selectedArticles.isEmpty || isSummarizing)
            Button(action: confirmDelete) {
                Text("删选")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 16)
                    .background(Color.red)
                    .cornerRadius(10)
            }
            .disabled(selectedArticles.isEmpty)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(red: 0.85, green: 0.91, blue: 1.0)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var articleListContent: some View {
        ScrollView {
            GeometryReader { geometry in
                Color.clear.preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scrollView")).minY)
            }
            .frame(height: 0)

            VStack(spacing: 2) {
                if viewModel.articles.isEmpty && !viewModel.isLoadingPage {
                    Text("暂无文章，请点击左下角导入按钮导入") // 【修改】提示文字
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    ForEach(Array(viewModel.articles.enumerated()), id: \.element.objectID) { index, article in
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
                        .background(index % 2 == 0 ? Color(.systemGray5) : Color(.systemGray4))
                        .cornerRadius(14)
                    }
                    
                    if viewModel.canLoadMorePages {
                        if viewModel.isLoadingPage {
                            ProgressView()
                                .padding()
                        } else {
                            Color.clear
                                .frame(height: 1)
                                .onAppear {
                                    viewModel.fetchArticles()
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .coordinateSpace(name: "scrollView")
        .background(Color.clear)
        .frame(maxHeight: .infinity)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
             if value > 60 {
                 viewModel.refreshData()
             }
        }
    }
    
    private var statisticsView: some View {
        HStack(spacing: 12) {
            StatCard(title: "已读", value: "\(totalDeletedCount)", gradient: [Color.blue, Color.blue.opacity(0.8)])
            StatCard(title: "今读", value: "\(todayDeletedCount)", gradient: [Color.green, Color.green.opacity(0.8)])
            StatCard(title: "待读", value: "\(allArticles.count)", gradient: [Color.purple, Color.purple.opacity(0.8)])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .onAppear(perform: checkAndResetDailyCount)
    }

    @ViewBuilder
    private var summarizingOverlayView: some View {
        if isSummarizing {
            ZStack {
                Color.black.opacity(0.2).ignoresSafeArea()
                VStack {
                    ProgressView().scaleEffect(2.0)
                    Text("总结中...").font(.headline)
                }
                .padding(20)
                .background(Material.regular)
                .cornerRadius(12)
                .shadow(radius: 15)
            }
        }
    }
    
    private var finalBackgroundView: some View {
        LinearGradient(gradient: Gradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(red: 0.85, green: 0.91, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            finalBackgroundView

            VStack(spacing: 0) {
                titleBar
                statisticsView
                articleListContent
                Spacer(minLength: 0)
                operationToolbarView
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: -2)
            }
        }
        .overlay { summarizingOverlayView }
        .navigationTitle("文章列表")
        .navigationBarTitleDisplayMode(.inline)
        .alert("错误", isPresented: $showingError, presenting: errorMessage) { _ in Button("确定") {} } message: { msg in Text(msg) }
        .alert("导入成功", isPresented: $showingImportSuccess) { Button("确定") {} } message: { Text("成功导入 \(importedCount) 篇文章。") }
        .fileImporter(isPresented: $isImportingLocalFile, allowedContentTypes: [.json], onCompletion: handleFileImportResult)
        .onChange(of: showingImportSuccess) { success in
            if success {
                viewModel.refreshData()
            }
        }
    }

    // MARK: - Action Methods

    private func checkAndResetDailyCount() {
        if !Calendar.current.isDate(lastResetDate, inSameDayAs: Date()) {
            todayDeletedCount = 0
            lastResetDate = Date()
            UserDefaults.standard.set(todayDeletedCount, forKey: "todayDeletedCount")
            UserDefaults.standard.set(lastResetDate, forKey: "lastResetDate")
        }
    }

    private func selectAllArticles() {
        if selectedArticles.count == viewModel.articles.count && !viewModel.articles.isEmpty {
            selectedArticles.removeAll()
        } else {
            selectedArticles = Set(viewModel.articles.map { ObjectIdentifier($0) })
        }
    }

    private func selectFiveArticles() {
        let unselectedArticles = viewModel.articles.filter { !selectedArticles.contains(ObjectIdentifier($0)) }
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
            self.errorMessage = "无效的文章链接"
            self.showingError = true
            return
        }
        UIApplication.shared.open(url)
    }

    private func summarizeSelectedArticles() {
        guard !selectedArticles.isEmpty else { return }
        isSummarizing = true
        let apiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? ""
        let schemeRawValue = UserDefaults.standard.string(forKey: "selectedBatchScheme") ?? BatchPromptScheme.normal.rawValue
        let selectedScheme = BatchPromptScheme(rawValue: schemeRawValue) ?? .normal
        let promptKey = "batchSummaryPrompt_\(selectedScheme.rawValue)"
        let summaryPrompt = UserDefaults.standard.string(forKey: promptKey) ?? Prompt.defaultBatchSummary(for: selectedScheme)

        guard !apiKey.isEmpty else { return }

        let selectedArticlesData = viewModel.articles.filter { selectedArticles.contains(ObjectIdentifier($0)) }
            .map { ["title": $0.title ?? "", "content": $0.content ?? ""] }

        Task {
            do {
                let summaryText = try await GeminiService.summarizeArticles(articles: selectedArticlesData, apiKey: apiKey, summaryPrompt: summaryPrompt)
                let fetchRequest: NSFetchRequest<BatchSummary> = BatchSummary.fetchRequest()
                let existingSummaries = try viewContext.fetch(fetchRequest)
                existingSummaries.forEach(viewContext.delete)

                let newSummary = BatchSummary(context: viewContext)
                newSummary.id = UUID()
                newSummary.content = summaryText
                newSummary.timestamp = Date()
                try viewContext.save()

                await MainActor.run {
                    self.selectedTab = .summary
                    self.isSummarizing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "总结失败: \(error.localizedDescription)"
                    self.showingError = true
                    isSummarizing = false
                }
            }
        }
    }
    
    private func deleteSelectedArticles() {
        let articlesToDelete = viewModel.articles.filter { selectedArticles.contains(ObjectIdentifier($0)) }
        articlesToDelete.forEach(viewContext.delete)

        do {
            try viewContext.save()
            totalDeletedCount += articlesToDelete.count
            todayDeletedCount += articlesToDelete.count
            UserDefaults.standard.set(totalDeletedCount, forKey: "totalDeletedCount")
            UserDefaults.standard.set(todayDeletedCount, forKey: "todayDeletedCount")
            selectedArticles.removeAll()
            viewModel.refreshData()
        } catch {
            self.errorMessage = "删除文章失败: \(error.localizedDescription)"
            self.showingError = true
        }
    }

    private func confirmDelete() {
        let alert = UIAlertController(title: "确认删除", message: "您确定要删除选中的文章吗？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in self.deleteSelectedArticles() })
        UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true)
    }

    // MARK: - File Import Handling
    private func handleFileImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let selectedFile):
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
            DispatchQueue.main.async {
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
                viewContext.performAndWait {
                    do {
                        if viewContext.hasChanges {
                            try viewContext.save()
                        }
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
                DispatchQueue.main.async {
                    self.importError = "导入失败：私有上下文操作错误：\(error.localizedDescription)"
                    self.showingError = true
                }
            }
        }
    }
}

// MARK: - ArticleCard
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
                // 将标题包裹在 Button 中，实现点击效果
                Button(action: onViewOriginal) {
                    Text(article.title ?? "无标题")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.blue) // 颜色改为蓝色，使其看起来像链接
                        .lineLimit(2)
                        .multilineTextAlignment(.leading) // 确保多行文本左对齐
                }
                .buttonStyle(PlainButtonStyle()) // 使用 PlainButtonStyle 以避免影响整行点击
                
            }
            Spacer()
            
            // 移除 Safari 按钮，因为点击标题已经可以打开原文
            // Button(action: onViewOriginal) { ... }
            
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
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Material.thin)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Preview and other helpers
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let gradient: [Color]
    
    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundColor(.white.opacity(0.9))
            Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(LinearGradient(gradient: Gradient(colors: gradient), startPoint: .topLeading, endPoint: .bottomTrailing))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}