import SwiftUI

struct SummaryArticle {
    let title: String
    let url: String
}

struct SummaryBlock: Identifiable {
    let id = UUID()
    let title: String
    let url: String
    var content: String
}

struct ContentSummaryView: View {
    // 示例原始内容
    let rawContent: String = """
好的，明白了。我会按照你提供的格式和要求，对JSON格式的文档进行总结和处理。

```markdown
[1] 《要止盈止损吗？》

**阅读建议**: 评分7/10分，值得一读。

**主要内容**: 文章主要讨论了在可转债投资中是否应该设置止盈止损，并分享了作者的量化交易经验和对市场的一些观察。

**核心观点**: 作者认为，在可转债投资中，用轮动代替止盈止损可能更好，并且通过量化回测发现，设置止盈止损不一定能提高收益。

**关键细节**:
- 微盘股指数盘中创新高，但小市值股票下跌，北证50上涨。
- 市场降息对银行的影响是双向的，银行股息率相对市场利息仍有吸引力。
- 宁德时代和比亚迪的H股相对A股出现折价，说明外资看好中国新能源行业。
- 作者通过量化回测发现，设置止损反而降低了收益率，设置止盈今年的效果也不好。
- 满足强赎条件的博俊转债和博瑞转债都折价了，但明天可能满足强赎条件的豪24转债、润达转债、九洲转2中的润达转债溢价率高达17.34%、九洲转2高达5.18%。

**深度解读**: 作者通过自己的量化交易经验，指出止盈止损并非万能，需要结合自身情况和市场环境进行判断。同时，作者也提醒投资者，要理性看待市场波动，不要盲目跟风。关于润达转债的高溢价，暗示市场可能存在非理性预期，投资者需谨慎。

[2] 《两个指数双双创出历史新高》

**阅读建议**: 评分7/10分，值得一读。

**主要内容**: 文章记录了当天股市行情，北证50和微盘股指数双双创出历史新高，并对比了小市值策略和可转债策略的风险收益特征。

**核心观点**: 小市值策略虽然收益率高，但风险也高，作者更倾向于风险较低的可转债多因子轮动策略。选择适合自己的方法最重要。

**关键细节**:
- 北证50和微盘股指数创历史新高，但小市值策略的夏普比率和最大回撤率不如可转债多因子策略。
- 周末出台的重组新规放松了要求，可能是小市值股票火爆的原因之一。
- 作者在前年年底放弃了小市值策略，因为风险较高。
- CCTV2记者采访作者，作者建议新股民找到适合自己的方法，通过量化回测证伪亏钱的方法。

**深度解读**: 作者通过对比不同策略的风险收益特征，强调了风险控制的重要性，并建议投资者根据自身情况选择适合自己的投资方法。放弃小市值策略，体现了作者的风险偏好和投资理念。
```
"""

    // 示例文章标题列表
    let articles: [SummaryArticle] = [
        SummaryArticle(title: "[1] 《要止盈止损吗？》", url: "https://example.com/article1"),
        SummaryArticle(title: "[2] 《两个指数双双创出历史新高》", url: "https://example.com/article2")
    ]

    // 清理 markdown 代码块
    private func extractMarkdown(_ text: String) -> String {
        let pattern = "```markdown\\n([\\s\\S]*?)\\n```"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return String(text[range])
        }
        return text
    }

    // 按标题列表拆分内容
    private func splitMarkdownByTitles(markdown: String, articles: [SummaryArticle]) -> [SummaryBlock] {
        var result: [SummaryBlock] = []
        var remaining = markdown
        for (i, article) in articles.enumerated() {
            if let range = remaining.range(of: article.title) {
                let before = String(remaining[..<range.lowerBound])
                if i > 0 {
                    result[result.count - 1].content += before
                }
                result.append(SummaryBlock(title: article.title, url: article.url, content: ""))
                remaining = String(remaining[range.upperBound...])
            }
        }
        if !result.isEmpty {
            result[result.count - 1].content += remaining
        }
        return result
    }

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.88, green: 0.95, blue: 0.99), Color(red: 0.80, green: 0.91, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    Spacer()
                    Text("内容总结")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Color(.label))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                
                // 批量总结提示
                HStack {
                    Text("针对2篇文章的批量总结 (2025-05-26 10:15)")
                        .font(.system(size: 12))
                        .foregroundColor(Color(.systemGray))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 2)
                .padding(.bottom, 2)
                
                // 总结卡片列表
                ScrollView {
                    VStack(spacing: 16) {
                        let markdownContent = extractMarkdown(rawContent)
                        let blocks = splitMarkdownByTitles(markdown: markdownContent, articles: articles)
                        ForEach(blocks) { block in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .center, spacing: 8) {
                                    Link(block.title, destination: URL(string: block.url)!)
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                    Button("对话") {
                                        // 触发对话逻辑
                                    }
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 16)
                                    .background(LinearGradient(gradient: Gradient(colors: [Color.purple, Color.pink]), startPoint: .leading, endPoint: .trailing))
                                    .cornerRadius(16)
                                }
                                Text(.init(block.content))
                                    .font(.body)
                                    .foregroundColor(.primary)
                            }
                            .padding(16)
                            .background(Color.white.opacity(0.85))
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .background(Color.clear)
                .frame(maxHeight: .infinity)
                
                // 底部TabBar
                Divider()
                CustomTabBar(selected: .summary)
                    .padding(.bottom, 6)
            }
            .padding(.top)
        }
    }
}

struct ContentSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        ContentSummaryView()
    }
} 