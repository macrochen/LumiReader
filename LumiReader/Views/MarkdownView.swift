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
    let fontSize: CGFloat
    
    @Binding var dynamicHeight: CGFloat
    var onDialogueButtonTapped: ((String) -> Void)?
    var onAutoCopy: (() -> Void)? // 新增：自动复制回调

    // MARK: - UIViewRepresentable 方法
    func makeUIView(context: Context) -> WKWebView {
        let preferences = WKPreferences()
        let configuration = WKWebViewConfiguration()
        configuration.preferences = preferences
        configuration.userContentController.add(context.coordinator, name: JAVASCRIPT_MESSAGE_HANDLER_NAME)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        // 注释掉此行以允许文字选择
        // webView.scrollView.isScrollEnabled = false
        
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.clear
        
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let processedHtml = htmlForMarkdown(markdownText, articles: articlesToLink, context: context, fontSize: fontSize)
        
        if context.coordinator.lastLoadedHTML != processedHtml {
            webView.loadHTMLString(processedHtml, baseURL: nil)
            context.coordinator.lastLoadedHTML = processedHtml
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - HTML 处理和注入
    private func htmlForMarkdown(_ markdown: String, articles: [Article], context: Context, fontSize: CGFloat) -> String {
        var currentHtml: String
        do {
            currentHtml = try Down(markdownString: markdown).toHTML([.hardBreaks, .unsafe])
        } catch {
            print("[MarkdownWebView] Markdown to HTML conversion error: \(error)")
            currentHtml = "<p>Error rendering markdown.</p>"
        }
        
        for article in articles {
            guard let articleTitle = article.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !articleTitle.isEmpty,
                  let articleLink = article.link, !articleLink.isEmpty else {
                continue
            }
            
            let articleIDForJS = article.objectID.uriRepresentation().absoluteString
            let searchPattern = "(?:\\[\\d+\\]\\s*)?《\(NSRegularExpression.escapedPattern(for: articleTitle))》"
            
            var newHtmlContent = ""
            var searchStartIndex = currentHtml.startIndex
            var modified = false

            while let matchRange = currentHtml.range(of: searchPattern, options: .regularExpression, range: searchStartIndex..<currentHtml.endIndex) {
                modified = true
                
                newHtmlContent.append(String(currentHtml[searchStartIndex..<matchRange.lowerBound]))
                
                let matchedFullTitleString = String(currentHtml[matchRange])
                let numberPrefix = matchedFullTitleString.contains("[") ? matchedFullTitleString.components(separatedBy: "《")[0] : ""
                
                let linkedTitleHTML = "<a href=\"\(articleLink)\" target=\"_blank\">\(articleTitle)</a>"
                let encodedButtonContext = articleIDForJS.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let dialogueButtonHtml = "<button class=\"dialogue-button\" onclick=\"\(JS_BUTTON_CLICK_FUNCTION)('\(encodedButtonContext)')\">对话</button>"

                newHtmlContent.append(numberPrefix)
                newHtmlContent.append("《")
                newHtmlContent.append(linkedTitleHTML)
                newHtmlContent.append("》")
                newHtmlContent.append(dialogueButtonHtml)
                
                searchStartIndex = matchRange.upperBound
            }
            
            if searchStartIndex < currentHtml.endIndex {
                newHtmlContent.append(String(currentHtml[searchStartIndex...]))
            }
            
            if modified {
                 currentHtml = newHtmlContent
            }
        }
        
        // 【最终方案】JS只负责检测选择并发送文本给Swift，由Swift负责复制
        let autoCopyScript = """
        let lastSelectedText = '';
        // 持续地更新最新选择的文本
        document.addEventListener('selectionchange', function() {
            const selection = window.getSelection();
            if (!selection.isCollapsed) {
                lastSelectedText = selection.toString();
            }
        });
        // 当用户手指离开屏幕时，触发发送操作
        document.addEventListener('touchend', function() {
            const textToCopy = lastSelectedText.trim();
            if (textToCopy.length > 0) {
                // 将选中的文本发送给Swift原生代码处理
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.iOSNative) {
                    window.webkit.messageHandlers.iOSNative.postMessage({ 
                        type: 'copyToClipboard',
                        text: textToCopy 
                    });
                }
            }
            // 重置变量，为下一次选择做准备
            lastSelectedText = '';
        });
        """

        // 在body样式中添加 -webkit-touch-callout: none; 来禁用长按菜单
        let finalHtml = """
        <!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, shrink-to-fit=no"><style>body{font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue","system-ui",sans-serif;font-size:\(fontSize)px;color:\(UIColor.label.toHexString());margin:0;padding:0;word-wrap:break-word;-webkit-text-size-adjust:none;-webkit-user-select:text;-webkit-touch-callout: none;}h1,h2,h3,h4,h5,h6{margin-top:1em;margin-bottom:0.5em;}p{margin-top:0;margin-bottom:0.8em;line-height:1.6}p > a + button.dialogue-button{margin-left:8px;}p > span.linked-title-container > a{color:inherit;text-decoration:none;}p > span.linked-title-container > a:hover{text-decoration:underline;}span.linked-title-container{/* display:inline-flex; align-items:center; */}ul,ol{padding-left:25px;margin-bottom:0.8em}li{margin-bottom:0.3em}code{font-family:"Menlo","Courier New",monospace;background-color:rgba(128,128,128,0.15);padding:2px 5px;border-radius:4px;font-size:0.9em}pre{background-color:rgba(128,128,128,0.1);padding:12px;border-radius:6px;overflow-x:auto;margin-bottom:0.8em}pre code{padding:0;background-color:transparent;font-size:0.85em}a{color:\(UIColor.systemBlue.toHexString());text-decoration:none}a:hover{text-decoration:underline}.dialogue-button{background-color:\(UIColor.systemBlue.toHexString());color:white;border:none;padding:5px 10px;border-radius:5px;font-size:0.8em;cursor:pointer;margin-left:8px;white-space:nowrap;vertical-align:middle;}.dialogue-button:hover{background-color:\(UIColor.systemBlue.withAlphaComponent(0.8).toHexString())}img{max-width:100%;height:auto;border-radius:6px}</style></head><body>\(currentHtml)<script type="text/javascript">\(autoCopyScript)
        function \(JS_GET_CONTENT_HEIGHT_FUNCTION)(){
            var height=Math.max(document.body.scrollHeight,document.documentElement.scrollHeight,document.body.offsetHeight,document.documentElement.offsetHeight,document.body.clientHeight,document.documentElement.clientHeight);
            if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.\(JAVASCRIPT_MESSAGE_HANDLER_NAME)){
                window.webkit.messageHandlers.\(JAVASCRIPT_MESSAGE_HANDLER_NAME).postMessage({type:"contentHeight",height:height});
            }
            return height;
        }
        function \(JS_BUTTON_CLICK_FUNCTION)(context){
            // 此处省略了您之前的调试 alert
            try {
                var decodedContext=decodeURIComponent(context);
                if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.\(JAVASCRIPT_MESSAGE_HANDLER_NAME)){
                    var messagePayload = {type:"dialogueAction",context:decodedContext};
                    window.webkit.messageHandlers.\(JAVASCRIPT_MESSAGE_HANDLER_NAME).postMessage(messagePayload);
                }
            } catch (e) {
                console.error("JS Error in onDialogueButtonClick: " + e.toString());
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
        
        // 【最终方案】修改 Coordinator 来处理新的 JS 消息
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == JAVASCRIPT_MESSAGE_HANDLER_NAME, let webView = message.webView else { return }
            
            if let body = message.body as? [String: Any] {
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
                            self.parent.onDialogueButtonTapped?(context)
                        }
                    case "copyToClipboard": // 新增：处理来自JS的复制请求
                        if let textToCopy = body["text"] as? String {
                            // 1. 使用原生API，可靠地复制到系统剪贴板
                            UIPasteboard.general.string = textToCopy
                            
                            // 2. 在主线程上更新UI
                            DispatchQueue.main.async {
                                // 触发 "Copied" 提示
                                self.parent.onAutoCopy?()
                                
                                // 3. 通知网页清除文本选择的高亮
                                webView.evaluateJavaScript("window.getSelection().removeAllRanges();", completionHandler: nil)
                            }
                        }
                    default:
                        print("[MarkdownWebView Coordinator] Unknown message type from JS: \(type)")
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            print("[MarkdownWebView JS Alert] \(message)")
            completionHandler()
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
