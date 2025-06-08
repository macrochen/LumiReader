import SwiftUI
import WebKit
import Down
import CoreData

let JAVASCRIPT_MESSAGE_HANDLER_NAME = "iOSNative"
let JS_GET_CONTENT_HEIGHT_FUNCTION = "getContentHeight"
let JS_BUTTON_CLICK_FUNCTION = "onDialogueButtonClick"
let JS_HIGHLIGHT_SENTENCE_FUNCTION = "highlightSentence" // 高亮函数
let JS_CLEAR_HIGHLIGHT_FUNCTION = "clearHighlight" // 清除高亮函数

struct MarkdownWebView: UIViewRepresentable {
    let markdownText: String
    let articlesToLink: [Article]
    let fontSize: CGFloat
    
    @Binding var dynamicHeight: CGFloat
    var onDialogueButtonTapped: ((String) -> Void)?
    var onAutoCopy: (() -> Void)?

    let segmentedSentencesForHTML: [(text: String, originalRange: NSRange)]
    @Binding var highlightedSentenceIndex: Int?

    // MARK: - 新增回调闭包
    var onScrollToSentence: ((CGFloat) -> Void)? // 传递句子相对于WebView内容顶部的偏移量

    func makeUIView(context: Context) -> WKWebView {
        let preferences = WKPreferences()
        let configuration = WKWebViewConfiguration()
        configuration.preferences = preferences
        configuration.userContentController.add(context.coordinator, name: JAVASCRIPT_MESSAGE_HANDLER_NAME)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.clear
        
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let processedHtml = htmlForMarkdown(markdownText, articles: articlesToLink, context: context, fontSize: fontSize, segmentedSentences: segmentedSentencesForHTML)
        
        if context.coordinator.lastLoadedHTML != processedHtml {
            webView.loadHTMLString(processedHtml, baseURL: nil)
            context.coordinator.lastLoadedHTML = processedHtml
            context.coordinator.currentHighlightedSentenceIndex = highlightedSentenceIndex
        } else {
            context.coordinator.updateHighlight(with: highlightedSentenceIndex, in: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func htmlForMarkdown(_ markdown: String, articles: [Article], context: Context, fontSize: CGFloat, segmentedSentences: [(text: String, originalRange: NSRange)]) -> String {
        var markdownWithSentenceSpans = ""
        if segmentedSentences.isEmpty {
            markdownWithSentenceSpans = markdown
        } else {
            let nsMarkdown = markdown as NSString
            var lastLocation = 0
            for (index, sentenceData) in segmentedSentences.enumerated() {
                if sentenceData.originalRange.location > lastLocation {
                    let prefixRange = NSRange(location: lastLocation, length: sentenceData.originalRange.location - lastLocation)
                    markdownWithSentenceSpans += nsMarkdown.substring(with: prefixRange)
                }
                
                let sentenceText = nsMarkdown.substring(with: sentenceData.originalRange)
                markdownWithSentenceSpans += "<span id=\"sentence-\(index)\" class=\"tts-sentence\">" + sentenceText + "</span>"
                
                lastLocation = sentenceData.originalRange.location + sentenceData.originalRange.length
            }
            if lastLocation < nsMarkdown.length {
                markdownWithSentenceSpans += nsMarkdown.substring(with: NSRange(location: lastLocation, length: nsMarkdown.length - lastLocation))
            }
        }
        
        var currentHtml: String
        do {
            currentHtml = try Down(markdownString: markdownWithSentenceSpans).toHTML([.hardBreaks, .unsafe])
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
            let escapedTitle = NSRegularExpression.escapedPattern(for: articleTitle)
            let searchPattern = "(?:\\[\\d+\\]\\s*)?《\(escapedTitle)》"
            
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
        
        let autoCopyScript = """
        let lastSelectedText = '';
        document.addEventListener('selectionchange', function() {
            const selection = window.getSelection();
            if (!selection.isCollapsed) {
                lastSelectedText = selection.toString();
            }
        });
        document.addEventListener('touchend', function() {
            const textToCopy = lastSelectedText.trim();
            if (textToCopy.length > 0) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.iOSNative) {
                    window.webkit.messageHandlers.iOSNative.postMessage({ 
                        type: 'copyToClipboard',
                        text: textToCopy 
                    });
                }
            }
            lastSelectedText = '';
        });
        """
        
        let highlightScript = """
        let currentHighlightedElement = null;

        function \(JS_HIGHLIGHT_SENTENCE_FUNCTION)(index) {
            if (currentHighlightedElement) {
                currentHighlightedElement.classList.remove('highlight');
            }
            if (index !== null && index !== undefined) {
                const element = document.getElementById('sentence-' + index);
                if (element) {
                    element.classList.add('highlight');
                    currentHighlightedElement = element;
                    // MARK: - 修改：不再调用 element.scrollIntoView()，而是发送消息给 Swift
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.iOSNative) {
                        // 发送元素相对于其 offsetParent（通常是文档body）的顶部偏移量
                        window.webkit.messageHandlers.iOSNative.postMessage({ 
                            type: 'scrollToHighlight',
                            offsetTop: element.offsetTop 
                        });
                    }
                }
            } else {
                currentHighlightedElement = null;
            }
        }

        function \(JS_CLEAR_HIGHLIGHT_FUNCTION)() {
            if (currentHighlightedElement) {
                currentHighlightedElement.classList.remove('highlight');
                currentHighlightedElement = null;
            }
        }
        """

        let finalHtml = """
        <!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, shrink-to-fit=no"><style>body{font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue","system-ui",sans-serif;font-size:\(fontSize)px;color:\(UIColor.label.toHexString());margin:0;padding:0;word-wrap:break-word;-webkit-text-size-adjust:none;-webkit-user-select:text;-webkit-touch-callout: none;}h1,h2,h3,h4,h5,h6{margin-top:1em;margin-bottom:0.5em;}p{margin-top:0;margin-bottom:0.8em;line-height:1.6}p > a + button.dialogue-button{margin-left:8px;}p > span.linked-title-container > a{color:inherit;text-decoration:none;}p > span.linked-title-container > a:hover{text-decoration:underline;}span.linked-title-container{/* display:inline-flex; align-items:center; */}ul,ol{padding-left:25px;margin-bottom:0.8em}li{margin-bottom:0.3em}code{font-family:"Menlo","Courier New",monospace;background-color:rgba(128,128,128,0.15);padding:2px 5px;border-radius:4px;font-size:0.9em}pre{background-color:rgba(128,128,128,0.1);padding:12px;border-radius:6px;overflow-x:auto;margin-bottom:0.8em}pre code{padding:0;background-color:transparent;font-size:0.85em}a{color:\(UIColor.systemBlue.toHexString());text-decoration:none}a:hover{text-decoration:underline}.dialogue-button{background-color:\(UIColor.systemBlue.toHexString());color:white;border:none;padding:5px 10px;border-radius:5px;font-size:0.8em;cursor:pointer;margin-left:8px;white-space:nowrap;vertical-align:middle;}.dialogue-button:hover{background-color:\(UIColor.systemBlue.withAlphaComponent(0.8).toHexString())}img{max-width:100%;height:auto;border-radius:6px}
        .tts-sentence {
            transition: background-color 0.1s ease-in-out;
            border-radius: 4px;
            padding: 1px 2px;
            box-decoration-break: clone;
            -webkit-box-decoration-break: clone;
        }
        .tts-sentence.highlight {
            background-color: rgba(255, 255, 0, 0.3);
        }
        </style></head><body>\(currentHtml)<script type="text/javascript">\(autoCopyScript)\(highlightScript)
        function \(JS_GET_CONTENT_HEIGHT_FUNCTION)(){
            var height=Math.max(document.body.scrollHeight,document.documentElement.scrollHeight,document.body.offsetHeight,document.documentElement.offsetHeight,document.body.clientHeight,document.documentElement.clientHeight);
            if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.\(JAVASCRIPT_MESSAGE_HANDLER_NAME)){
                window.webkit.messageHandlers.\(JAVASCRIPT_MESSAGE_HANDLER_NAME).postMessage({type:"contentHeight",height:height});
            }
            return height;
        }
        function \(JS_BUTTON_CLICK_FUNCTION)(context){
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
        let pendingHeightUpdate = false;
        const observer=new MutationObserver(function(mutationsList,observer){
            if (!pendingHeightUpdate) {
                requestAnimationFrame(() => {
                    \(JS_GET_CONTENT_HEIGHT_FUNCTION)();
                    pendingHeightUpdate = false;
                });
                pendingHeightUpdate = true;
            }
        });
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
        var currentHighlightedSentenceIndex: Int?

        init(_ parent: MarkdownWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("\(JS_GET_CONTENT_HEIGHT_FUNCTION)();") { (result, error) in
                if let error = error { print("[MarkdownWebView] Error evaluating JS for height on didFinish: \(error.localizedDescription)") }
            }
            updateHighlight(with: parent.highlightedSentenceIndex, in: webView)
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
                    case "copyToClipboard":
                        if let textToCopy = body["text"] as? String {
                            UIPasteboard.general.string = textToCopy
                            
                            DispatchQueue.main.async {
                                self.parent.onAutoCopy?()
                                webView.evaluateJavaScript("window.getSelection().removeAllRanges();", completionHandler: nil)
                            }
                        }
                    // MARK: - 新增：处理来自JS的滚动请求
                    case "scrollToHighlight":
                        if let offsetTop = body["offsetTop"] as? CGFloat {
                            self.parent.onScrollToSentence?(offsetTop)
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
        
        func updateHighlight(with newIndex: Int?, in webView: WKWebView) {
            guard newIndex != currentHighlightedSentenceIndex else { return } 
            
            DispatchQueue.main.async {
                if let index = newIndex {
                    webView.evaluateJavaScript("\(JS_HIGHLIGHT_SENTENCE_FUNCTION)(\(index));") { (result, error) in
                        if let error = error {
                            print("[MarkdownWebView Coordinator] JS highlight error: \(error.localizedDescription)")
                        }
                    }
                } else {
                    webView.evaluateJavaScript("\(JS_CLEAR_HIGHLIGHT_FUNCTION)();") { (result, error) in
                        if let error = error {
                            print("[MarkdownWebView Coordinator] JS clear highlight error: \(error.localizedDescription)")
                        }
                    }
                }
                self.currentHighlightedSentenceIndex = newIndex
            }
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