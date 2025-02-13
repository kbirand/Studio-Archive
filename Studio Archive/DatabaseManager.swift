import Foundation
import SQLite3
import SwiftUI

class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    
    @Published var currentDatabasePath: String?
    @Published var showError = false
    @Published var errorMessage = ""
    
    var isDatabaseSelected: Bool {
        currentDatabasePath != nil && db != nil
    }
    
    fileprivate(set) var db: OpaquePointer?
    private let defaults = UserDefaults.standard
    private let databasePathKey = "LastDatabasePath"
    private let logManager = LogManager.shared
    
    struct Work: Identifiable {
        let id: Int
        let path: String?
        let stylist: String?
        let hair: String?
        let makeup: String?
        let talent: String?
        let workPeriod: String?
    }
    
    private init() {
        setupInitialDatabaseIfNeeded()
    }
    
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private func setupInitialDatabaseIfNeeded() {
        // First check if we have a saved database path
        if let savedPath = defaults.string(forKey: databasePathKey),
           FileManager.default.fileExists(atPath: savedPath) {
            logManager.log("Found existing database at: \(savedPath)", type: .info)
            openDatabase(at: savedPath)
            return
        }
        
        // No saved database, let's copy the initial one
        if let bundleURL = Bundle.main.url(forResource: "works", withExtension: "db") {
            let destinationURL = documentsDirectory.appendingPathComponent("works.db")
            
            do {
                // Remove any existing file
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                
                // Copy the initial database
                try FileManager.default.copyItem(at: bundleURL, to: destinationURL)
                logManager.log("Successfully copied initial database to: \(destinationURL.path)", type: .info)
                
                // Open the copied database
                openDatabase(at: destinationURL.path)
            } catch {
                logManager.log("Error setting up initial database: \(error)", type: .error)
                errorMessage = "Failed to setup initial database: \(error.localizedDescription)"
                showError = true
            }
        } else {
            logManager.log("No initial database found in bundle", type: .error)
        }
    }
    
    func setNewDatabase(sourceURL: URL) {
        closeDatabase()
        
        // Start accessing the security-scoped resource
        guard sourceURL.startAccessingSecurityScopedResource() else {
            logManager.log("Failed to access security-scoped resource", type: .error)
            errorMessage = "Failed to access the database file. Please try selecting it again."
            showError = true
            return
        }
        
        // Make sure to stop accessing the resource when we're done
        defer {
            sourceURL.stopAccessingSecurityScopedResource()
        }
        
        let fileName = sourceURL.lastPathComponent
        let destinationURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            // Remove existing file if it exists
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            // Copy the database file to documents directory
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            logManager.log("Successfully copied database to: \(destinationURL.path)", type: .info)
            
            // Open the copied database
            openDatabase(at: destinationURL.path)
        } catch {
            logManager.log("Error copying database: \(error)", type: .error)
            errorMessage = "Failed to copy database: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func closeDatabase() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
        currentDatabasePath = nil
    }
    
    deinit {
        closeDatabase()
    }
    
    func openDatabase(at path: String) {
        logManager.log("Attempting to open database at: \(path)", type: .info)
        
        // Verify the file exists
        guard FileManager.default.fileExists(atPath: path) else {
            logManager.log("Database file does not exist at path: \(path)", type: .error)
            return
        }
        
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        
        if sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let database = db {
            // Test if we can actually read from the database
            var testStatement: OpaquePointer?
            let testSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name='works'"
            
            if sqlite3_prepare_v2(database, testSQL, -1, &testStatement, nil) == SQLITE_OK {
                let result = sqlite3_step(testStatement)
                sqlite3_finalize(testStatement)
                
                if result == SQLITE_ROW {
                    self.db = database
                    self.currentDatabasePath = path
                    defaults.set(path, forKey: databasePathKey)
                    logManager.log("Successfully opened database", type: .info)
                    
                    // Count the works
                    if let count = try? getWorkCount() {
                        logManager.log("Database contains \(count) works", type: .info)
                    }
                } else {
                    logManager.log("Database does not contain required 'works' table", type: .error)
                    sqlite3_close(database)
                    errorMessage = "The selected file is not a valid works database"
                    showError = true
                }
            } else {
                logManager.log("Could not verify database structure", type: .error)
                sqlite3_close(database)
                errorMessage = "Could not verify database structure"
                showError = true
            }
        } else {
            if let database = db {
                let errorMsg = String(cString: sqlite3_errmsg(database))
                logManager.log("Error opening database: \(errorMsg)", type: .error)
                sqlite3_close(database)
                errorMessage = "Error opening database: \(errorMsg)"
            } else {
                logManager.log("Error opening database", type: .error)
                errorMessage = "Error opening database"
            }
            showError = true
        }
        
        if !isDatabaseSelected {
            defaults.removeObject(forKey: databasePathKey)
        }
    }
    
    private func getWorkCount() throws -> Int {
        guard let db = db else { throw DatabaseError.notInitialized }
        
        var statement: OpaquePointer?
        let query = "SELECT COUNT(*) FROM works"
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DatabaseError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
        
        return Int(sqlite3_column_int(statement, 0))
    }
    
    func fetchWorks() -> [Work] {
        var works: [Work] = []
        guard let db = db else {
            logManager.log("Database connection is not initialized", type: .error)
            return works
        }
        
        let queryString = "SELECT id, path, stylist, hair, makeup, talent, work_period FROM works ORDER BY id DESC"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, queryString, -1, &statement, nil) == SQLITE_OK else {
            logManager.log("Error preparing statement: \(String(cString: sqlite3_errmsg(db)))", type: .error)
            return works
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(statement, 0))
            
            func getColumnText(_ index: Int32) -> String? {
                guard let cString = sqlite3_column_text(statement, index) else { return nil }
                return String(cString: cString)
            }
            
            let work = Work(
                id: id,
                path: getColumnText(1),
                stylist: getColumnText(2),
                hair: getColumnText(3),
                makeup: getColumnText(4),
                talent: getColumnText(5),
                workPeriod: getColumnText(6)
            )
            works.append(work)
        }
        
        logManager.log("Fetched \(works.count) works from database", type: .info)
        return works
    }
    
    func getDatabase() -> OpaquePointer? {
        return db
    }
    
    func updateWork(id: Int, workPeriod: String?, talent: String?, stylist: String?, hair: String?, makeup: String?) -> Bool {
        guard let db = db else {
            logManager.log("Database connection is not initialized", type: .error)
            return false
        }
        
        let queryString = """
            UPDATE works 
            SET work_period = ?, talent = ?, stylist = ?, hair = ?, makeup = ?
            WHERE id = ?
        """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, queryString, -1, &statement, nil) == SQLITE_OK else {
            logManager.log("Error preparing statement: \(String(cString: sqlite3_errmsg(db)))", type: .error)
            return false
        }
        
        // Bind parameters
        sqlite3_bind_text(statement, 1, (workPeriod as NSString?)?.utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (talent as NSString?)?.utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (stylist as NSString?)?.utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (hair as NSString?)?.utf8String, -1, nil)
        sqlite3_bind_text(statement, 5, (makeup as NSString?)?.utf8String, -1, nil)
        sqlite3_bind_int(statement, 6, Int32(id))
        
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        
        if result {
            logManager.log("Successfully updated work with id: \(id)", type: .info)
        } else {
            logManager.log("Error updating work: \(String(cString: sqlite3_errmsg(db)))", type: .error)
        }
        
        return result
    }
    
    func updateOrder(id: Int, order: Int) -> Bool {
        guard let db = db else {
            logManager.log("Database connection is not initialized", type: .error)
            return false
        }
        
        var statement: OpaquePointer?
        let query = "UPDATE files SET ordered = ? WHERE id = ?"
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            logManager.log("Failed to prepare update order statement: \(String(cString: sqlite3_errmsg(db)))", type: .error)
            return false
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(order))
        sqlite3_bind_int(statement, 2, Int32(id))
        
        if sqlite3_step(statement) != SQLITE_DONE {
            logManager.log("Failed to update order for file id \(id): \(String(cString: sqlite3_errmsg(db)))", type: .error)
            return false
        }
        
        logManager.log("Successfully updated order for file id \(id) to \(order)", type: .debug)
        return true
    }
    
    func updateFileOrder(fileId: Int, newOrder: Int) async throws -> Bool {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }
        
        let queryString = "UPDATE files SET ordered = ? WHERE id = ?"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, queryString, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_int(statement, 1, Int32(newOrder))
        sqlite3_bind_int(statement, 2, Int32(fileId))
        
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    func deleteFile(id: Int) -> Bool {
        guard let db = db else {
            logManager.log("Database connection is not initialized", type: .error)
            return false
        }
        
        let queryString = "DELETE FROM files WHERE id = ?"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, queryString, -1, &statement, nil) == SQLITE_OK else {
            logManager.log("Error preparing delete statement: \(String(cString: sqlite3_errmsg(db)))", type: .error)
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        sqlite3_bind_int(statement, 1, Int32(id))
        
        let result = sqlite3_step(statement) == SQLITE_DONE
        
        if result {
            logManager.log("Successfully deleted file with id: \(id)", type: .delete)
        } else {
            logManager.log("Error deleting file: \(String(cString: sqlite3_errmsg(db)))", type: .error)
        }
        
        return result
    }
    
    func deleteWork(id: Int) -> Bool {
        guard let db = db else {
            logManager.log("Database connection is not initialized", type: .error)
            return false
        }
        
        logManager.log("Starting deletion of work with ID: \(id)", type: .delete)
        
        // Begin transaction
        if sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil) != SQLITE_OK {
            logManager.log("Failed to begin transaction: \(String(cString: sqlite3_errmsg(db)))", type: .error)
            return false
        }
        
        // Delete from files table first (foreign key)
        let deleteFilesQuery = "DELETE FROM files WHERE workid = ?"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, deleteFilesQuery, -1, &statement, nil) == SQLITE_OK else {
            logManager.log("Error preparing delete files statement: \(String(cString: sqlite3_errmsg(db)))", type: .error)
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        
        sqlite3_bind_int(statement, 1, Int32(id))
        
        if sqlite3_step(statement) != SQLITE_DONE {
            logManager.log("Error deleting files: \(String(cString: sqlite3_errmsg(db)))", type: .error)
            sqlite3_finalize(statement)
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        
        logManager.log("Successfully deleted files for work ID: \(id)", type: .delete)
        sqlite3_finalize(statement)
        
        // Delete from works table
        let deleteWorkQuery = "DELETE FROM works WHERE id = ?"
        
        guard sqlite3_prepare_v2(db, deleteWorkQuery, -1, &statement, nil) == SQLITE_OK else {
            logManager.log("Error preparing delete work statement: \(String(cString: sqlite3_errmsg(db)))", type: .error)
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        
        sqlite3_bind_int(statement, 1, Int32(id))
        
        if sqlite3_step(statement) != SQLITE_DONE {
            logManager.log("Error deleting work: \(String(cString: sqlite3_errmsg(db)))", type: .error)
            sqlite3_finalize(statement)
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        
        sqlite3_finalize(statement)
        
        // Commit transaction
        if sqlite3_exec(db, "COMMIT", nil, nil, nil) != SQLITE_OK {
            logManager.log("Failed to commit transaction: \(String(cString: sqlite3_errmsg(db)))", type: .error)
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        
        logManager.log("Successfully deleted work with ID: \(id)", type: .delete)
        return true
    }
    
    enum DatabaseError: Error {
        case notInitialized
        case prepareFailed(String)
        case executeFailed(String)
    }
}
