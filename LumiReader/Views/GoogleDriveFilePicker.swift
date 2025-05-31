import SwiftUI

struct GoogleDriveFilePicker: View {
    @StateObject private var driveService = GoogleDriveService.shared
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFiles: Set<String> = []
    let onFilesSelected: ([GTLRDrive_File]) -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                // 渐变背景
                LinearGradient(gradient: Gradient(colors: [Color(red: 0.95, green: 0.91, blue: 1.0), Color(red: 0.91, green: 0.84, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 标题栏
                    HStack {
                        Button(action: { /* 关闭操作 */ }) {
                            Image(systemName: "xmark")
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Text("选择文件")
                            .font(.system(size: 22, weight: .semibold))
                        Spacer()
                        Button(action: {
                            let selected = driveService.files.filter { selectedFiles.contains($0.identifier!) }
                            onFilesSelected(selected)
                        }) {
                            Text("导入")
                                .foregroundColor(selectedFiles.isEmpty ? .gray : .blue)
                        }
                        .disabled(selectedFiles.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    
                    if !driveService.isSignedIn {
                        VStack(spacing: 16) {
                            Text("请先登录 Google 账户")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                            Button(action: {
                                Task {
                                    do {
                                        try await driveService.signIn()
                                        try await driveService.fetchFiles()
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            }) {
                                Text("登录 Google")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List {
                                ForEach(driveService.files, id: \.identifier) { file in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(file.name ?? "未命名文件")
                                                .font(.system(size: 16))
                                            Text(formatDate(file.createdTime?.date))
                                                .font(.system(size: 12))
                                                .foregroundColor(.gray)
                                        }
                                        Spacer()
                                        if selectedFiles.contains(file.identifier!) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if selectedFiles.contains(file.identifier!) {
                                            selectedFiles.remove(file.identifier!)
                                        } else {
                                            selectedFiles.insert(file.identifier!)
                                        }
                                    }
                                }
                            }
                            .listStyle(PlainListStyle())
                        }
                    }
                }
            }
        }
        .alert("错误", isPresented: .constant(errorMessage != nil)) {
            Button("确定") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            if driveService.isSignedIn {
                isLoading = true
                do {
                    try await driveService.fetchFiles()
                } catch {
                    errorMessage = error.localizedDescription
                }
                isLoading = false
            }
        }
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "未知日期" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
} 