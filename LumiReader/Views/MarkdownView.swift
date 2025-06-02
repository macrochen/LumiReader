import SwiftUI
import UIKit
import Down // Import Down library

struct MarkdownView: UIViewRepresentable {
    let markdownText: String
    @Binding var dynamicHeight: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false // Crucial for SwiftUI ScrollView to manage scrolling
        textView.backgroundColor = .clear
        
        // Reset insets and padding
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0

        // Default font and color - these might be overridden by HTML styles
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textColor = UIColor.label // Use system label color for adaptability

        // Important for layout: ensure it tries to fit its content
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.required, for: .vertical)
        
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let htmlString: String
        do {
            // Consider Down options if you need to customize HTML output
            htmlString = try Down(markdownString: markdownText).toHTML([.hardBreaks]) // .hardBreaks can be useful if single newlines should also break
        } catch {
            print("Markdown to HTML conversion error: \(error)")
            // Fallback: wrap plain text in a basic HTML structure to maintain some paragraphing
            let escapedMarkdown = markdownText
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n\n", with: "</p><p>") // Basic paragraph
                .replacingOccurrences(of: "\n", with: "<br>")     // Basic line break
            htmlString = "<p>\(escapedMarkdown)</p>"
        }

        let finalHtmlString = """
        <html>
        <head>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", "system-ui", sans-serif; /* Match system font */
                    font-size: \(UIFont.preferredFont(forTextStyle: .body).pointSize)px; /* Match body text size */
                    color: \(UIColor.label.toHexString()); /* Match system label color */
                    margin: 0; /* Remove default body margin */
                    padding: 0; /* Remove default body padding */
                    word-wrap: break-word; /* Ensure long words break */
                }
                p { margin-top: 0; margin-bottom: 0; } /* Adjust paragraph margins if needed */
                /* Add other styles for h1, h2, strong, em etc. if Down doesn't handle them well enough or if you want to override */
            </style>
        </head>
        <body>
            \(htmlString)
        </body>
        </html>
        """

        let nsAttributedString: NSAttributedString
        if let data = finalHtmlString.data(using: .utf8) {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
            do {
                nsAttributedString = try NSAttributedString(data: data, options: options, documentAttributes: nil)
            } catch {
                print("HTML to NSAttributedString conversion error: \(error)")
                nsAttributedString = NSAttributedString(string: markdownText) // Fallback
            }
        } else {
            nsAttributedString = NSAttributedString(string: markdownText) // Fallback
        }

        if uiView.attributedText != nsAttributedString { // More robust comparison
            uiView.attributedText = nsAttributedString
        }
        
        // Calculate height after the next layout pass to ensure bounds are correct
        DispatchQueue.main.async {
            // Ensure the width used for calculation is the one SwiftUI has given it.
            // uiView.bounds.width might be stale if called too early.
            // It's generally safer to rely on the width from the parent SwiftUI view if possible,
            // or ensure this calculation happens after SwiftUI's layout pass.
            let fixedWidth = uiView.frame.width // Use frame.width after layout
            
            guard fixedWidth > 0 else {
                // If width is 0, it means layout hasn't happened yet or view is not in hierarchy.
                // We might need to trigger a recalculation later or rely on SwiftUI's frame.
                return
            }
            
            let newSize = uiView.sizeThatFits(CGSize(width: fixedWidth, height: .greatestFiniteMagnitude))
            let newHeight = newSize.height
            
            if abs(dynamicHeight - newHeight) > 1 && newHeight > 0 { // Use a small tolerance for float comparison
                dynamicHeight = newHeight
            }
        }
    }
}

// Helper to convert UIColor to hex string for HTML CSS
extension UIColor {
    func toHexString() -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let rgb: Int = (Int)(r * 255) << 16 | (Int)(g * 255) << 8 | (Int)(b * 255) << 0
        return String(format: "#%06x", rgb)
    }
}