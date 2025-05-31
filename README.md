# LumiRead

LumiRead 是一个 iPad 应用程序，旨在帮助用户导入文章、生成内容总结以及与 AI 进行文章相关的对话。该应用集成了 Google Drive 文件导入、Google Gemini API 进行 AI 处理，并使用 Core Data 进行本地数据存储。

## 主要功能

- **文章导入**: 从 Google Drive 导入 JSON 格式的文章文件。
- **内容总结**: 利用 AI 对文章进行批量总结。
- **AI 对话**: 与 AI 就特定文章进行互动式问答。
- **数据持久化**: 使用 Core Data 存储文章、总结和聊天记录。

## 项目结构

项目采用 SwiftUI 和 Core Data 构建，遵循 MVVM 架构模式，主要包含以下组件：

- **Models**: Core Data 实体定义 (Article, BatchSummary, Chat, Message, PresetPrompt, Settings)。
- **Views**: SwiftUI 视图组件 (MainTabView, ArticleListView, ContentSummaryView, AIChatView, SettingsView)。
- **ViewModels**: 视图模型，负责视图的状态管理和业务逻辑。
- **Services**: 业务逻辑服务 (AIService, GoogleDriveService, ArticleImportService)。
- **Persistence**: Core Data 持久化控制器。

## 安装与运行

待补充...

## 配置

待补充...

## 贡献

待补充...

## 许可证

待补充...