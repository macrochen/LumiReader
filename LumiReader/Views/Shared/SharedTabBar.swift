import SwiftUI

// MARK: - 自定义TabBar
enum TabType {
    case articleList, summary, aiChat, settings
}

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