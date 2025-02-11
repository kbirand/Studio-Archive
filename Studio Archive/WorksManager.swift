import Foundation
import SQLite3

class WorksManager: ObservableObject {
    static let shared = WorksManager()
    private let databaseManager = DatabaseManager.shared
    
    @Published var errorMessage: String = ""
    @Published var showError: Bool = false
    
    private init() {}
    
    func addNewWork(workPeriod: String) -> Bool {
        guard let db = databaseManager.getDatabase() else {
            errorMessage = "Database is not available"
            showError = true
            return false
        }
        
        var statement: OpaquePointer?
        let insertSQL = "INSERT INTO works (work_period) VALUES (?)"
        
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            errorMessage = "Failed to prepare insert statement"
            showError = true
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        // Bind the work period
        sqlite3_bind_text(statement, 1, (workPeriod as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_DONE {
            print("Successfully added new work")
            LogManager.shared.info("Successfully added new work")
            return true
        } else {
            errorMessage = "Failed to add new work"
            showError = true
            return false
        }
    }
}
