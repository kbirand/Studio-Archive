import Foundation
import SQLite3

class DetailsManager: ObservableObject {
    static let shared = DetailsManager()
    
    struct File: Identifiable {
        let id: Int
        let workId: Int
        let file: String
        let ordered: Int
    }
    
    @Published var files: [File] = []
    @Published var showError = false
    @Published var errorMessage = ""
    
    private var db: OpaquePointer? {
        DatabaseManager.shared.db
    }
    
    private init() {}
    
    func fetchFiles(forWorkId workId: Int, completion: @escaping () -> Void = {}) {
        guard let db = db else {
            LogManager.shared.log("Database connection is not initialized", type: .error)
            return
        }
        
        LogManager.shared.log("DetailsManager: Fetching files for work ID: \(workId)", type: .info)
        
        let queryString = """
            SELECT id, workid, file, ordered
            FROM files
            WHERE workid = ?
            ORDER BY ordered DESC
        """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, queryString, -1, &statement, nil) == SQLITE_OK else {
            LogManager.shared.log("Error preparing statement: \(String(cString: sqlite3_errmsg(db)))", type: .error)
            return
        }
        
        sqlite3_bind_int(statement, 1, Int32(workId))
        
        var tempFiles: [File] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let workId = sqlite3_column_int64(statement, 1)
            
            var file: String = ""
            if let fileText = sqlite3_column_text(statement, 2) {
                file = String(cString: fileText)
            }
            
            let ordered = sqlite3_column_int64(statement, 3)
            
            let fileRecord = File(
                id: Int(id),
                workId: Int(workId),
                file: file,
                ordered: Int(ordered)
            )
            
            tempFiles.append(fileRecord)
            LogManager.shared.log("Found file: \(file) (ID: \(id), Work ID: \(workId), Order: \(ordered))", type: .debug)
        }
        
        sqlite3_finalize(statement)
        
        LogManager.shared.log("Total files found: \(tempFiles.count)", type: .info)
        
        DispatchQueue.main.async {
            self.files = tempFiles
            LogManager.shared.log("Updated files array on main thread", type: .debug)
            completion()
        }
    }
    
    func refreshFiles() {
        if let currentWorkId = files.first?.workId {
            fetchFiles(forWorkId: currentWorkId)
        }
    }
}
