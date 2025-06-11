// CustomWKWebView.swift
import WebKit
import UIKit // 导入 UIKit 获取 UIResponderStandardEditActions

class CustomWKWebView: WKWebView { // 【修改】移除 WKUIDelegate 协议遵守
    // 覆盖此方法以控制哪些 UIResponderAction 可以被执行
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        print("CustomWKWebView canPerformAction called for action: \(action)")

        // 明确允许 copy 操作，因为你需要自动复制功能
        if action == #selector(UIResponderStandardEditActions.copy(_:)) {
            print("Allowing copy action.")
            return true
        }

        // 屏蔽常见的文本选择、编辑和系统级操作相关的菜单项
        // 使用 Selector("methodName:") 字符串形式，避免协议方法问题
        if action == #selector(UIResponderStandardEditActions.select(_:)) ||
           action == #selector(UIResponderStandardEditActions.selectAll(_:)) ||
           action == #selector(UIResponderStandardEditActions.cut(_:)) ||
           action == #selector(UIResponderStandardEditActions.paste(_:)) ||
           action == #selector(UIResponderStandardEditActions.delete(_:)) ||
           action == Selector(("lookUp:")) ||      // 查找
           action == Selector(("define:")) ||      // 定义
           action == Selector(("_define:")) ||      // 定义
            
           action == Selector(("share:")) ||       // 分享
           action == Selector(("_share:")) ||      // 分享 (私有选择器，为了鲁棒性)
           
            action == Selector(("translate:")) ||  // 翻译
           action == Selector(("_translate:")) ||  // 翻译
            
            action == Selector(("findSelected:")) || //
            action == Selector(("_findSelected:")) || //
            
            action == Selector(("toggleUnderline:")) || //
            
            action == Selector(("toggleItalics:")) || //
            
            action == Selector(("toggleBoldface:")) || //
            
            action == Selector(("_openInNewCanvas:")) || //
            action == Selector(("captureTextFromCamera:")) ||
            
            action == Selector(("selectAll:")) || //
            action == Selector(("select:")) || //
            
            action == Selector(("delete:")) ||
            action == Selector(("paste:")) || //
            action == Selector(("copy:")) || //
            action == Selector(("addShortcut:")) || //
            action == Selector(("_accessibilitySpeak:")) || //
            action == Selector(("makeTextWritingDirectionLeftToRight:")) || //
            action == Selector(("_showTextFormattingOptions:")) || //
            action == Selector(("makeTextWritingDirectionRightToLeft:")) || //
            action == Selector(("_openInNewCanvas:")) || //
            action == Selector(("captureTextFromCamera:")) || //
            action == Selector(("showWritingTools:")) || //
            action == Selector(("_insertDrawing:")) || //
            action == Selector(("_transliterateChinese:")) || //
            action == Selector(("_promptForReplace:")) || //
            
            action == Selector(("findSelected:")) || //
            action == Selector(("_findSelected:")) || //
            
           
           action == Selector(("_searchWeb:")) ||  // 搜索网页
           action == Selector(("_learnMore:")) ||  // 学习 (如添加到词典)
           action == Selector(("_addShortcut:")) { // 添加快捷方式
            
            print("CustomWKWebView Blocking action: \(action)")
            return false // 返回 false 阻止此动作的菜单项显示
        }
        
        // 允许其他非文本编辑相关的动作，例如成为第一响应者等
        return super.canPerformAction(action, withSender: sender)
    }
    
    // 【重要】这里不再实现任何 WKUIDelegate 方法。这些方法由 Coordinator 处理。
    // 所以，删除你之前在这里添加的 `webView(_:contextMenuConfigurationForElement:completionHandler:)` 方法。
}
