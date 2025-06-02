import SwiftUI
import CoreData

struct SummaryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    // ... (FetchRequest remains the same)
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BatchSummary.timestamp, ascending: false)],
        animation: .default)
    private var batchSummaries: FetchedResults<BatchSummary>
    
    @State private var markdownViewHeight: CGFloat = 20 // Start with a small non-zero height to avoid initial layout issues

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color(red: 0.91, green: 0.84, blue: 1.0), Color(red: 0.95, green: 0.91, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea() // Keep this if you want the gradient to fill the whole screen

            VStack(spacing: 0) {
                // If you have a custom title bar or want space at the top, add it here.
                // For example, to respect the top safe area for content:
                // Spacer().frame(height: UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0)
                // Or simply add padding to the ScrollView or its content.

                ScrollView {
                    // This VStack is the direct content of the ScrollView
                    VStack(alignment: .leading, spacing: 20) {
                        if batchSummaries.isEmpty {
                            Text("暂无总结内容，请在文章列表中选择文章进行批量总结。")
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40) // Padding for empty state
                        } else {
                            if let latestSummary = batchSummaries.first {
                                let markdownContent = latestSummary.content ?? ""
                                if !markdownContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    MarkdownView(markdownText: markdownContent, dynamicHeight: $markdownViewHeight)
                                        .frame(height: markdownViewHeight)
                                        // Ensure MarkdownView itself doesn't get unnecessary horizontal padding
                                        // The parent VStack already has horizontal padding.
                                } else {
                                    Text("总结内容为空。") // Handle empty content string
                                        .foregroundColor(.gray)
                                        .padding(.top, 20)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16) // Horizontal padding for the content block
                    .padding(.vertical, 20)   // Vertical padding for the content block (increased for better spacing)
                    // The .padding(.top) you had here might be redundant or could be merged into .padding(.vertical)
                    // Ensure this VStack takes the full available width for its content
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.clear)
                // If you want the ScrollView content to start below the status bar:
                // .padding(.top, UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0)
                // Or, if not using ignoresSafeArea() on the ZStack, this might not be needed.
            }
            // If your content is still too high, and you are using .navigationBarHidden(true)
            // you might need to explicitly push the entire VStack down.
            // .padding(.top, (UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0) + (UINavigationController().navigationBar.frame.height ?? 0) ) // Approximate if nav bar was visible
        }
        .navigationBarHidden(true)
        // .edgesIgnoringSafeArea(.all) // Alternative to ZStack's ignoresSafeArea, apply with caution
    }
    // ... (itemFormatter and PreviewProvider remain the same)
}