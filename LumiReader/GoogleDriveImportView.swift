import SwiftUI

struct GoogleDriveImportView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        NavigationView {
            VStack {
                if isConnecting {
                    ProgressView("正在连接Google Drive...")
                } else {
                    List {
                        Section {
                            Button(action: connectGoogleDrive) {
                                HStack {
                                    Image(systemName: "link")
                                    Text("连接Google Drive")
                                }
                            }
                        }
                        
                        Section(header: Text("选择要导入的JSON文件")) {
                            // TODO: 实现文件列表
                            Text("连接Google Drive后，这里将显示可导入的JSON文件")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .navigationTitle("从Google Drive导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .alert("错误", isPresented: $showingError, presenting: errorMessage) { _ in
                Button("确定", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }
    
    private func connectGoogleDrive() {
        isConnecting = true
        // TODO: 实现Google Drive连接逻辑
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isConnecting = false
            errorMessage = "Google Drive连接功能尚未实现"
            showingError = true
        }
    }
}

struct GoogleDriveImportView_Previews: PreviewProvider {
    static var previews: some View {
        GoogleDriveImportView()
    }
} 