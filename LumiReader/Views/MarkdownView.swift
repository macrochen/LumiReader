import SwiftUI
import WebKit
import Down // 确保 Down 已经导入
import CoreData // 导入 CoreData 以使用 Article 类型

// 定义JS消息处理器的名称
let JAVASCRIPT_MESSAGE_HANDLER_NAME = "iOSNative"
// 定义JS函数名，用于从网页获取内容高度
let JS_GET_CONTENT_HEIGHT_FUNCTION = "getContentHeight"
// 定义JS函数名，用于网页内按钮点击时调用
let JS_BUTTON_CLICK_FUNCTION = "onDialogueButtonClick"

// ArticleLinkInfo 结构体不再需要，我们将直接使用 Article NSManagedObject

struct MarkdownWebView: UIViewRepresentable {
    let markdownText: String
    let articlesToLink: [Article] // 直接使用 CoreData 的 Article 模型
    
    @Binding var dynamicHeight: CGFloat
    var onDialogueButtonTapped: ((String) -> Void)?

    // MARK: - UIViewRepresentable 方法
    func makeUIView(context: Context) -> WKWebView {
        let preferences = WKPreferences()
        let configuration = WKWebViewConfiguration()
        configuration.preferences = preferences
        configuration.userContentController.add(context.coordinator, name: JAVASCRIPT_MESSAGE_HANDLER_NAME)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.clear
        
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let processedHtml = htmlForMarkdown(markdownText, articles: articlesToLink, context: context)
        
        if context.coordinator.lastLoadedHTML != processedHtml {
            webView.loadHTMLString(processedHtml, baseURL: nil)
            context.coordinator.lastLoadedHTML = processedHtml
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - HTML 处理和注入
    private func htmlForMarkdown(_ markdown: String, articles: [Article], context: Context) -> String {
        var currentHtml: String
        do {
            currentHtml = try Down(markdownString: markdown).toHTML([.hardBreaks, .unsafe])
        } catch {
            print("[MarkdownWebView] Markdown to HTML conversion error: \(error)")
            currentHtml = "<p>Error rendering markdown.</p>"
        }

        // 遍历提供的文章列表，对每个文章的标题在HTML中进行查找和修改
        // 为了避免因修改字符串长度导致后续查找索引失效，我们每次替换后都从头开始搜索下一个文章标题，
        // 或者更健壮的方式是：对每个文章标题，找到它在当前HTML中的所有位置，然后一次性构建新的HTML。
        // 这里采用一种迭代方式：对每个 article，处理它在当前 currentHtml 中的所有出现。
        
        for article in articles {
            guard let articleTitle = article.title?.trimmingCharacters(in: .whitespacesAndNewlines), 
                  !articleTitle.isEmpty,
                  let articleLink = article.link, !articleLink.isEmpty else {
                // print("[MarkdownWebView] Skipping article due to missing title or link: \(article.title ?? "N/A")")
                continue
            }
            
            let articleIDForJS = article.objectID.uriRepresentation().absoluteString

            // 构建查找模式："[可选编号]《标题》"
            // 1. 匹配可选的 "[数字]" (例如 "[1]", "[12]")
            let optionalNumberPattern = "(\\[\\d+\\]\\s*)?" // 捕获组1: 可选的编号和空格
            // 2. 匹配书名号和标题
            let titleInBracketsPattern = "《\(NSRegularExpression.escapedPattern(for: articleTitle))》" // 精确匹配书名号内的标题

            // 完整查找模式
            let searchPattern = optionalNumberPattern + titleInBracketsPattern
            
            var newHtmlContent = ""
            var searchStartIndex = currentHtml.startIndex
            var modified = false

            while searchStartIndex < currentHtml.endIndex {
                // 在 searchStartIndex 之后查找
                let rangeToSearch = searchStartIndex..<currentHtml.endIndex
                
                // 使用正则表达式查找模式
                guard let regex = try? NSRegularExpression(pattern: searchPattern),
                      let match = regex.firstMatch(in: currentHtml, options: [], range: NSRange(rangeToSearch, in: currentHtml)) else {
                    // 没有更多匹配项，跳出内部while循环
                    break
                }
                
                modified = true
                let matchRange = Range(match.range, in: currentHtml)!

                // 添加匹配之前的部分
                newHtmlContent.append(String(currentHtml[searchStartIndex..<matchRange.lowerBound]))

                // 提取匹配到的完整字符串，例如 "[1] 《标题》"
                let matchedFullTitleString = String(currentHtml[matchRange])
                
                // 提取可选的编号部分 (捕获组1)
                var numberPrefix = ""
                if match.numberOfRanges > 1 { // 确保捕获组存在
                    let numberRangeInMatch = match.range(at: 1) // 对应 (\[\d+\]\s*)?
                    if numberRangeInMatch.location != NSNotFound, let swiftNumberRange = Range(numberRangeInMatch, in: currentHtml) {
                        numberPrefix = String(currentHtml[swiftNumberRange])
                    }
                }
                
                // 创建链接化的标题 (只链接书名号内的部分)
                // title="${articleTitle.replacingOccurrences(of: "\"", with: "&quot;")}"
                let linkedTitleHTML = "<a href=\"\(articleLink)\" target=\"_blank\">\(articleTitle)</a>"
                
                // 创建对话按钮HTML
                let encodedButtonContext = articleIDForJS.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let dialogueButtonHtml = "<button class=\"dialogue-button\" onclick=\"\(JS_BUTTON_CLICK_FUNCTION)('\(encodedButtonContext)')\">对话</button>"

                // 拼接：可选编号 + 《 + 链接标题 + 》 + 对话按钮
                newHtmlContent.append(numberPrefix) // 添加编号（如果存在）
                newHtmlContent.append("《")      // 添加左书名号
                newHtmlContent.append(linkedTitleHTML) // 添加链接化的核心标题
                newHtmlContent.append("》")      // 添加右书名号
                newHtmlContent.append(dialogueButtonHtml) // 添加对话按钮
                
                searchStartIndex = matchRange.upperBound // 更新下一次搜索的起始位置
            }
            
            // 添加剩余的HTML部分
            if searchStartIndex < currentHtml.endIndex {
                newHtmlContent.append(String(currentHtml[searchStartIndex...]))
            }
            
            // 如果对当前文章标题进行了任何处理，则更新 currentHtml
            if modified {
                 currentHtml = newHtmlContent
            }
        }
        
        let finalHtml = """
        <!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, shrink-to-fit=no"><style>body{font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue","system-ui",sans-serif;font-size:\(UIFont.preferredFont(forTextStyle: .body).pointSize)px;color:\(UIColor.label.toHexString());margin:0;padding:0;word-wrap:break-word;-webkit-text-size-adjust:none}h1,h2,h3,h4,h5,h6{margin-top:1em;margin-bottom:0.5em;}p{margin-top:0;margin-bottom:0.8em;line-height:1.6}p > a + button.dialogue-button{margin-left:8px;}p > span.linked-title-container > a{color:inherit;text-decoration:none;}p > span.linked-title-container > a:hover{text-decoration:underline;}span.linked-title-container{/* display:inline-flex; align-items:center; */}ul,ol{padding-left:25px;margin-bottom:0.8em}li{margin-bottom:0.3em}code{font-family:"Menlo","Courier New",monospace;background-color:rgba(128,128,128,0.15);padding:2px 5px;border-radius:4px;font-size:0.9em}pre{background-color:rgba(128,128,128,0.1);padding:12px;border-radius:6px;overflow-x:auto;margin-bottom:0.8em}pre code{padding:0;background-color:transparent;font-size:0.85em}a{color:\(UIColor.systemBlue.toHexString());text-decoration:none}a:hover{text-decoration:underline}.dialogue-button{background-color:\(UIColor.systemBlue.toHexString());color:white;border:none;padding:5px 10px;border-radius:5px;font-size:0.8em;cursor:pointer;margin-left:8px;white-space:nowrap;vertical-align:middle;}.dialogue-button:hover{background-color:\(UIColor.systemBlue.withAlphaComponent(0.8).toHexString())}img{max-width:100%;height:auto;border-radius:6px}</style></head><body>\(currentHtml)<script type="text/javascript">
        function \(JS_GET_CONTENT_HEIGHT_FUNCTION)(){
            var height=Math.max(document.body.scrollHeight,document.documentElement.scrollHeight,document.body.offsetHeight,document.documentElement.offsetHeight,document.body.clientHeight,document.documentElement.clientHeight);
            if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.\(JAVASCRIPT_MESSAGE_HANDLER_NAME)){
                window.webkit.messageHandlers.\(JAVASCRIPT_MESSAGE_HANDLER_NAME).postMessage({type:"contentHeight",height:height});
            }
            return height;
        }
        function \(JS_BUTTON_CLICK_FUNCTION)(context){
            alert("JS: onDialogueButtonClick called with context: " + context); // DEBUG: 确认函数调用和参数
            try {
                var decodedContext=decodeURIComponent(context);
                alert("JS: Decoded context: " + decodedContext); // DEBUG: 确认解码结果
                if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.\(JAVASCRIPT_MESSAGE_HANDLER_NAME)){
                    var messagePayload = {type:"dialogueAction",context:decodedContext};
                    alert("JS: Attempting to postMessage: " + JSON.stringify(messagePayload)); // DEBUG: 确认发送的消息
                    window.webkit.messageHandlers.\(JAVASCRIPT_MESSAGE_HANDLER_NAME).postMessage(messagePayload);
                    alert("JS: postMessage sent."); // DEBUG: 确认 postMessage 已执行
                } else {
                    alert("JS Error: iOSNative message handler (window.webkit.messageHandlers.\(JAVASCRIPT_MESSAGE_HANDLER_NAME)) not found!"); // DEBUG: 处理器未找到
                }
            } catch (e) {
                alert("JS Error in onDialogueButtonClick: " + e.toString()); // DEBUG: 捕获并报告错误
            }
        }
        const observer=new MutationObserver(function(mutationsList,observer){\(JS_GET_CONTENT_HEIGHT_FUNCTION)()});
        observer.observe(document.body,{childList:true,subtree:true,attributes:true,characterData:true});
        window.onload=function(){\(JS_GET_CONTENT_HEIGHT_FUNCTION)()};
        document.addEventListener('readystatechange',event=>{if(event.target.readyState==='complete'){\(JS_GET_CONTENT_HEIGHT_FUNCTION)()}});
        </script></body></html>
        """
        return finalHtml
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: MarkdownWebView
        var lastLoadedHTML: String?

        init(_ parent: MarkdownWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("\(JS_GET_CONTENT_HEIGHT_FUNCTION)();") { (result, error) in
                if let error = error { print("[MarkdownWebView] Error evaluating JS for height on didFinish: \(error.localizedDescription)") }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[MarkdownWebView] Web content failed to load: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[MarkdownWebView] Provisional navigation failed: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    if parent.articlesToLink.contains(where: { $0.link == url.absoluteString }) {
                        UIApplication.shared.open(url)
                        decisionHandler(.cancel)
                        return
                    }
                }
            }
            decisionHandler(.allow)
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == JAVASCRIPT_MESSAGE_HANDLER_NAME else { return }
            // DEBUG: 打印接收到的原始消息
            // print("[MarkdownWebView Coordinator] Received message from JS. Name: \(message.name). Body: \(message.body)")
            if let body = message.body as? [String: Any] {
                 print("[MarkdownWebView Coordinator] Parsed message body: \(body)") // DEBUG: 打印解析后的消息体
                if let type = body["type"] as? String {
                    switch type {
                    case "contentHeight":
                        if let height = body["height"] as? CGFloat {
                            if abs(self.parent.dynamicHeight - height) > 0.5 && height > 0 {
                                self.parent.dynamicHeight = height
                            }
                        }
                    case "dialogueAction":
                        if let context = body["context"] as? String {
                            print("[MarkdownWebView Coordinator] Dialogue action received for context: \(context)") // DEBUG: 确认接收到对话动作
                            self.parent.onDialogueButtonTapped?(context)
                        } else {
                             print("[MarkdownWebView Coordinator] Error: 'context' not found or not a string in dialogueAction.")
                        }
                    default:
                        print("[MarkdownWebView Coordinator] Unknown message type from JS: \(type)")
                    }
                } else {
                     print("[MarkdownWebView Coordinator] Error: 'type' not found or not a string in message body.")
                }
            } else {
                 print("[MarkdownWebView Coordinator] Error: Could not parse message.body as [String: Any]. Actual type: \(type(of: message.body))")
            }
        }
        
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            // 将JS的alert内容打印到Xcode控制台，方便调试
            print("[MarkdownWebView JS Alert] \(message)")
            // 你也可以在这里触发一个SwiftUI的弹窗来显示这个消息给用户，如果需要的话。
            // 例如: parent.showAlert(title: "网页提示", message: message)
            completionHandler() // 必须调用，否则网页会卡住
        }
    }
}

extension UIColor {
    func toHexString() -> String {
        var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0; var a: CGFloat = 0
        let dynamicColor = self.resolvedColor(with: UITraitCollection.current)
        dynamicColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let rgb: Int = (Int)(r * 255) << 16 | (Int)(g * 255) << 8 | (Int)(b * 255) << 0
        return String(format: "#%06x", rgb)
    }
}
