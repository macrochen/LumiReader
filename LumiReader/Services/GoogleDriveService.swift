import Foundation
import GoogleSignIn
import GoogleAPIClientForREST_Drive

class GoogleDriveService: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var currentUser: GIDGoogleUser?
    @Published var files: [GTLRDrive_File] = []
    
    private let driveService = GTLRDriveService()
    private let scopes = [
        "https://www.googleapis.com/auth/drive.readonly",
        "https://www.googleapis.com/auth/drive.file"
    ]
    
    static let shared = GoogleDriveService()
    
    private init() {
        setupDriveService()
    }
    
    private func setupDriveService() {
        driveService.authorizer = GIDSignIn.sharedInstance.currentUser?.authentication.fetcherAuthorizer()
    }
    
    func signIn() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            throw NSError(domain: "GoogleDriveService", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取根视图控制器"])
        }
        
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
        currentUser = result.user
        isSignedIn = true
        setupDriveService()
    }
    
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        currentUser = nil
        isSignedIn = false
        files = []
    }
    
    func fetchFiles() async throws {
        let query = GTLRDriveQuery_FilesList.query()
        query.pageSize = 100
        query.fields = "files(id, name, mimeType, createdTime, modifiedTime, size)"
        query.q = "mimeType='application/pdf' or mimeType='text/plain' or mimeType='application/msword' or mimeType='application/vnd.openxmlformats-officedocument.wordprocessingml.document'"
        
        let result = try await withCheckedThrowingContinuation { continuation in
            driveService.executeQuery(query) { (ticket, result, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let fileList = result as? GTLRDrive_FileList {
                    continuation.resume(returning: fileList)
                } else {
                    continuation.resume(throwing: NSError(domain: "GoogleDriveService", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取文件列表"]))
                }
            }
        }
        
        await MainActor.run {
            self.files = result.files ?? []
        }
    }
    
    func downloadFile(_ file: GTLRDrive_File) async throws -> Data {
        let query = GTLRDriveQuery_FilesGet.queryForMedia(withFileId: file.identifier!)
        
        return try await withCheckedThrowingContinuation { continuation in
            driveService.executeQuery(query) { (ticket, fileData, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let data = fileData as? Data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(domain: "GoogleDriveService", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法下载文件"]))
                }
            }
        }
    }
}