//
//  Persistence.swift
//  LumiReader
//
//  Created by jolin on 2025/5/31.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "LumiReader")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Error: \(error.localizedDescription)")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    // MARK: - Preview Helper
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        
        // 创建示例数据
        let viewContext = controller.container.viewContext
        
        // 创建示例文章
        let article = Article(context: viewContext)
        article.title = "示例文章"
        article.content = "这是示例文章的内容..."
        article.link = "https://example.com/article"
        article.importDate = Date()
        
        // 创建示例预设提示词
        let prompt = PresetPrompt(context: viewContext)
        prompt.title = "总结文章"
        prompt.content = "请总结这篇文章的主要内容..."
        prompt.createdAt = Date()
        
        // 创建示例设置
        let settings = Settings(context: viewContext)
        settings.apiKey = "your-api-key"
        settings.batchSummaryPrompt = "请对以下文章进行总结..."
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        
        return controller
    }()
}
