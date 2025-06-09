
import CoreData

// MARK: - ViewModel for Pagination
// 我创建了这个 ViewModel 来处理分页逻辑
@MainActor // 确保所有对外的属性和方法都在主线程上执行，简化UI更新
class SourceViewModel: ObservableObject {
    @Published var articles: [Article] = []
    @Published var isLoadingPage = false
    @Published var canLoadMorePages = true
    
    private var currentPage = 0
    private let pageSize = 20 // 你可以根据需要调整每页加载的数量
    private let viewContext: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.viewContext = context
        fetchArticles()
    }

    // 从 Core Data 加载文章
    func fetchArticles() {
        // 如果正在加载或者已经没有更多数据，则直接返回
        guard !isLoadingPage, canLoadMorePages else { return }

        isLoadingPage = true

        let request: NSFetchRequest<Article> = Article.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Article.importDate, ascending: false)]
        request.fetchOffset = currentPage * pageSize // 设置偏移量，跳过已加载的数据
        request.fetchLimit = pageSize // 设置获取数量

        viewContext.perform {
            do {
                let newArticles = try self.viewContext.fetch(request)
                
                DispatchQueue.main.async {
                    if self.currentPage == 0 {
                        self.articles = newArticles
                    } else {
                        self.articles.append(contentsOf: newArticles)
                    }
                    
                    // 如果返回的文章数量小于每页数量，说明已经没有更多了
                    self.canLoadMorePages = newArticles.count == self.pageSize
                    self.isLoadingPage = false
                    
                    // 只有在成功加载后才增加页码
                    if !newArticles.isEmpty {
                        self.currentPage += 1
                    }
                }
            } catch {
                print("Failed to fetch articles: \(error)")
                DispatchQueue.main.async {
                    self.isLoadingPage = false
                }
            }
        }
    }

    // 加载下一页
    func loadMoreContentIfNeeded(currentItem article: Article?) {
        guard let article = article else {
            fetchArticles()
            return
        }

        let thresholdIndex = articles.index(articles.endIndex, offsetBy: -5)
        if articles.firstIndex(where: { $0.objectID == article.objectID }) == thresholdIndex {
            fetchArticles()
        }
    }
    
    // 刷新数据
    func refreshData() {
        currentPage = 0
        canLoadMorePages = true
        articles = []
        fetchArticles()
    }
}