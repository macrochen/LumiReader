import SwiftUI
import CoreData

struct ArticleRow: View {
    let article: Article
    let isSelected: Bool
    let onSelect: () -> Void
    let onViewOriginal: () -> Void
    let onChat: () -> Void
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    var body: some View {
        HStack {
            // 复选框
            Button(action: onSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            
            // 文章信息
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title ?? "无标题")
                    .font(.headline)
                    .lineLimit(2)
                
                if let importDate = article.importDate {
                    Text("导入时间：\(dateFormatter.string(from: importDate))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // 操作按钮
            HStack(spacing: 12) {
                Button(action: onViewOriginal) {
                    Image(systemName: "safari")
                        .foregroundColor(.blue)
                }
                
                Button(action: onChat) {
                    Image(systemName: "bubble.left")
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct ArticleRow_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let article = Article(context: context)
        article.title = "示例文章标题"
        article.importDate = Date()
        
        return ArticleRow(
            article: article,
            isSelected: false,
            onSelect: {},
            onViewOriginal: {},
            onChat: {}
        )
        .previewLayout(.sizeThatFits)
        .padding()
    }
} 
