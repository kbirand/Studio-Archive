import Foundation
import SQLite3

class DetailsManager: ObservableObject {
    static let shared = DetailsManager()
    
    struct File: Identifiable {
        let id: Int
        let workId: Int
        let file: String
        let ordered: Int
        let visible: Bool?
    }
    
    @Published var files: [File] = []
    @Published var showError = false
    @Published var errorMessage = ""
    
    private var db: OpaquePointer? {
        DatabaseManager.shared.db
    }
    
    private var currentWorkId: Int?
    
    private init() {}
    
    func fetchFiles(forWorkId workId: Int, completion: @escaping () -> Void = {}) {
        // Skip if we're already showing files for this work
        if currentWorkId == workId && !files.isEmpty {
            LogManager.shared.log("DetailsManager: Files for work ID \(workId) already loaded", type: .debug)
            return
        }
        
        currentWorkId = workId
        
        guard let db = db else {
            LogManager.shared.log("Database connection is not initialized", type: .error)
            return
        }
        
        LogManager.shared.log("DetailsManager: Fetching files for work ID: \(workId)", type: .info)
        
        let queryString = """
            SELECT id, workid, file, ordered, visible
            FROM files
            WHERE workid = ?
            ORDER BY ordered DESC
        """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, queryString, -1, &statement, nil) == SQLITE_OK else {
            LogManager.shared.log("Failed to prepare statement: \(String(cString: sqlite3_errmsg(db)!))", type: .error)
            return
        }
        
        sqlite3_bind_int(statement, 1, Int32(workId))
        
        var newFiles: [File] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(statement, 0))
            let workId = Int(sqlite3_column_int(statement, 1))
            let file = String(cString: sqlite3_column_text(statement, 2))
            let ordered = Int(sqlite3_column_int(statement, 3))
            let visible = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : sqlite3_column_int(statement, 4) != 0
            
            newFiles.append(File(id: id, workId: workId, file: file, ordered: ordered, visible: visible))
        }
        
        sqlite3_finalize(statement)
        
        LogManager.shared.log("Total files found: \(newFiles.count)", type: .info)
        
        DispatchQueue.main.async {
            self.files = newFiles
            completion()
        }
    }
    
    func refreshFiles() {
        if let currentWorkId = files.first?.workId {
            fetchFiles(forWorkId: currentWorkId)
        }
    }
}
