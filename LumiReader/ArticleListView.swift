import SwiftUI

struct ArticleListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Article.importDate, ascending: false)],
        animation: .default)
    private var articles: FetchedResults<Article>
    
    @State private var selectedArticles: Set<ObjectIdentifier> = []
    @State private var showingImportSheet = false
    @State private var showingBatchSummary = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
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
                    Button(action: { showingImportSheet = true }) {
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
                    Button(action: { showingBatchSummary = true }) {
                        Text("批量总结选中")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 16)
                            .background(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.pink]), startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(10)
                    }
                    .disabled(selectedArticles.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.5).blur(radius: 2))
                
                // 文章列表
                ScrollView {
                    VStack(spacing: 16) {
                        if articles.isEmpty {
                            Text("暂无文章，请从Google Drive导入")
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
                                    onChat: { startChat(article) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .background(Color.clear)
                .frame(maxHeight: .infinity)
                
                // 底部TabBar
                Divider()
                CustomTabBar(selected: .articleList)
                    .padding(.bottom, 6)
            }
        }
        .sheet(isPresented: $showingImportSheet) {
            GoogleDriveImportView()
        }
        .alert("错误", isPresented: $showingError, presenting: errorMessage) { _ in
            Button("确定", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }
    
    private func selectAllArticles() {
        selectedArticles = Set(articles.map { ObjectIdentifier($0) })
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
        // TODO: 实现跳转到AI对话页面
        errorMessage = "AI对话功能尚未实现"
        showingError = true
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

// MARK: - 自定义TabBar
enum TabType { case articleList, summary, aiChat, settings }

struct CustomTabBar: View {
    let selected: TabType
    var body: some View {
        HStack {
            tabItem(icon: "list.bullet.rectangle", label: "文章列表", active: selected == .articleList)
            tabItem(icon: "doc.text.magnifyingglass", label: "内容总结", active: selected == .summary)
            tabItem(icon: "ellipsis.bubble", label: "AI对话", active: selected == .aiChat)
            tabItem(icon: "gearshape", label: "系统设置", active: selected == .settings)
        }
        .padding(.top, 4)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: -1)
    }
    
    @ViewBuilder
    private func tabItem(icon: String, label: String, active: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(active ? Color.blue : Color(.systemGray3))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(active ? Color.blue : Color(.systemGray3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}

struct ArticleListView_Previews: PreviewProvider {
    static var previews: some View {
        ArticleListView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
} 