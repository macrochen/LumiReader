import SwiftUI
//import GCDWebServer
import CoreData
import Network

// 定义用于解析JSON的结构体 (与 ArticleListView 中的 ImportedArticle 相同)
//struct ImportedArticle: Codable {
//    let title: String
//    let url: String
//    let content: String
//}

struct WifiImportView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var webServer = WifiImportServer.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()
                
                Image(systemName: webServer.isRunning ? "wifi" : "wifi.slash")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(webServer.isRunning ? .blue : .gray)
                
                Text(webServer.isRunning ? "WiFi 导入服务器已启动" : "WiFi 导入服务器已停止")
                    .font(.title2)
                    .padding(.bottom)
                
                if webServer.isRunning {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("请在同一 WiFi 下的浏览器访问以下地址上传 JSON 文件：")
                            .font(.headline)
                        
                        if let serverURL = webServer.serverURL {
                            Link(serverURL.absoluteString, destination: serverURL)
                                .font(.title3)
                                .foregroundColor(.blue)
                        } else {
                            Text("获取服务器地址中...")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(10)
                    .shadow(radius: 5)
                    
                    if let uploadMessage = webServer.uploadMessage {
                        Text(uploadMessage)
                            .foregroundColor(webServer.uploadSuccess ? .green : .red)
                            .padding(.top)
                    }
                    
                } else {
                    // 服务器停止时的状态或错误信息
                    if let errorMessage = webServer.errorMessage {
                        Text("服务器启动失败: \(errorMessage)")
                            .foregroundColor(.red)
                            .padding(.top)
                    }
                }
                
                Spacer()
                
                Button(webServer.isRunning ? "停止服务器" : "启动服务器") {
                    if webServer.isRunning {
//                        webServer.stopServer()
                    } else {
//                        webServer.startServer(viewContext: viewContext)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
            }
            .padding()
            .navigationTitle("通过 WiFi 导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            // 界面消失时停止服务器，避免在后台运行
//            webServer.stopServer()
        }
    }
}

// MARK: - GCDWebServer 服务封装
class WifiImportServer: NSObject, ObservableObject {
    static let shared = WifiImportServer()
    
//    private var webServer: GCDWebServer? = nil
    @Published var isRunning = false
    @Published var serverURL: URL? = nil
    @Published var errorMessage: String? = nil
    @Published var uploadMessage: String? = nil
    @Published var uploadSuccess: Bool = false
    
    private override init() {
        super.init()
    }
    
//    func startServer(viewContext: NSManagedObjectContext) {
    //     if isRunning { return }
        
    //     webServer = GCDWebServer()
        
    //     // 设置上传文件处理器
    //     webServer?.addHandler(forMethod: "POST", path: "/upload", request: GCDWebServerMultiPartFormRequest.self) { request in
    //         guard let multipartRequest = request as? GCDWebServerMultiPartFormRequest else {
    //             return GCDWebServerDataResponse(statusCode: 400)
    //         }
            
    //         guard let file = multipartRequest.firstFile(forName: "file"),
    //               let data = file.data else {
    //             DispatchQueue.main.async {
    //                 self.uploadMessage = "上传失败：未收到文件"
    //                 self.uploadSuccess = false
    //             }
    //             return GCDWebServerDataResponse(statusCode: 400)
    //         }
            
    //         do {
    //             let decoder = JSONDecoder()
    //             let imported = try decoder.decode([ImportedArticle].self, from: data)
                
    //             // 保存到 Core Data
    //             viewContext.performAndWait { // 在主线程上执行Core Data操作
    //                 var importedCount = 0
    //                 for item in imported {
    //                     let article = Article(context: viewContext)
    //                     article.title = item.title
    //                     article.link = item.url // 使用 link 属性
    //                     article.content = item.content
    //                     article.importDate = Date()
    //                     importedCount += 1
    //                 }
    //                 try? viewContext.save()
    //                 DispatchQueue.main.async {
    //                     self.uploadMessage = "上传成功！成功导入 \(importedCount) 篇文章。"
    //                     self.uploadSuccess = true
    //                 }
    //             }
                
    //             return GCDWebServerDataResponse(statusCode: 200)
                
    //         } catch {
    //             DispatchQueue.main.async {
    //                 self.uploadMessage = "上传失败：解析JSON错误 - \(error.localizedDescription)"
    //                 self.uploadSuccess = false
    //             }
    //             return GCDWebServerDataResponse(statusCode: 400)
    //         }
    //     }
        
    //     // 设置一个简单的 HTML 上传页面处理器
    //     webServer?.addHandler(forMethod: "GET", path: "/", request: GCDWebServerRequest.self) { request in
    //          let html = """
    //         <!DOCTYPE html>
    //         <html>
    //         <head><title>上传文章 JSON</title></head>
    //         <body>
    //             <h1>上传文章 JSON 文件</h1>
    //             <form action="/upload" method="post" enctype="multipart/form-data">
    //                 <input type="file" name="file" accept=".json">
    //                 <input type="submit" value="上传">
    //             </form>
    //         </body>
    //         </html>
    //         """
    //         return GCDWebServerDataResponse(html: html)
    //     }

    //     // 尝试启动服务器
    //     let port: UInt = 8080 // 可以选择一个合适的端口
    //     do {
    //         try webServer?.start(options: [GCDWebServerOption_Port: port])
    //         DispatchQueue.main.async {
    //             self.isRunning = webServer?.isRunning ?? false
    //             self.serverURL = webServer?.serverURL
    //             self.errorMessage = nil
    //             self.uploadMessage = nil
    //             self.uploadSuccess = false
    //         }
    //         print("GCDWebServer started on \(webServer?.serverURL?.absoluteString ?? "Unknown URL")")
    //     } catch {
    //         DispatchQueue.main.async {
    //             self.isRunning = false
    //             self.serverURL = nil
    //             self.errorMessage = error.localizedDescription
    //             self.uploadMessage = nil
    //             self.uploadSuccess = false
    //         }
    //         print("GCDWebServer failed to start: \(error.localizedDescription)")
    //     }
    // }
    
    // func stopServer() {
    //     if !isRunning { return }
    //     webServer?.stop()
    //     webServer = nil
    //     DispatchQueue.main.async {
    //         self.isRunning = false
    //         self.serverURL = nil
    //         self.errorMessage = nil
    //         self.uploadMessage = nil
    //         self.uploadSuccess = false
    //     }
    //     print("GCDWebServer stopped")
    // }
}

// 预览提供者
struct WifiImportView_Previews: PreviewProvider {
    static var previews: some View {
        WifiImportView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
} 
