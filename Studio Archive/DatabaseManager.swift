import Foundation
import SQLite3

class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?
    @Published var isDatabaseSelected: Bool
    @Published var currentDatabasePath: String?
    @Published var errorMessage: String = ""
    @Published var showError: Bool = false
    
    private let defaults = UserDefaults.standard
    private let databasePathKey = "LastDatabasePath"
    
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
        self.isDatabaseSelected = false
        setupInitialDatabaseIfNeeded()
    }
    
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private func setupInitialDatabaseIfNeeded() {
        // First check if we have a saved database path
        if let savedPath = defaults.string(forKey: databasePathKey),
           FileManager.default.fileExists(atPath: savedPath) {
            print("Found existing database at: \(savedPath)")
            LogManager.shared.info("Found existing database at: \(savedPath)")
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
                print("Successfully copied initial database to: \(destinationURL.path)")
                LogManager.shared.info("Successfully copied initial database to: \(destinationURL.path)")
                
                // Open the copied database
                openDatabase(at: destinationURL.path)
            } catch {
                print("Error setting up initial database: \(error)")
                LogManager.shared.error("Error setting up initial database: \(error)")
                errorMessage = "Failed to setup initial database: \(error.localizedDescription)"
                showError = true
            }
        } else {
            print("No initial database found in bundle")
            LogManager.shared.warning("No initial database found in bundle")
        }
    }
    
    func setNewDatabase(sourceURL: URL) {
        closeDatabase()
        
        // Start accessing the security-scoped resource
        guard sourceURL.startAccessingSecurityScopedResource() else {
            print("Failed to access security-scoped resource")
            LogManager.shared.error("Failed to access security-scoped resource")
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
            print("Successfully copied database to: \(destinationURL.path)")
            LogManager.shared.info("Successfully copied database to: \(destinationURL.path)")
            
            // Open the copied database
            openDatabase(at: destinationURL.path)
        } catch {
            print("Error copying database: \(error)")
            LogManager.shared.error("Error copying database: \(error)")
            errorMessage = "Failed to copy database: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func closeDatabase() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
        isDatabaseSelected = false
        currentDatabasePath = nil
    }
    
    deinit {
        closeDatabase()
    }
    
    func openDatabase(at path: String) {
        print("Attempting to open database at: \(path)")
        LogManager.shared.info("Attempting to open database at: \(path)")
        
        // Verify the file exists
        guard FileManager.default.fileExists(atPath: path) else {
            print("Database file does not exist at path: \(path)")
            LogManager.shared.error("Database file does not exist at path: \(path)")
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
                    self.isDatabaseSelected = true
                    self.currentDatabasePath = path
                    defaults.set(path, forKey: databasePathKey)
                    print("Successfully opened database")
                    LogManager.shared.info("Successfully opened database")
                    
                    // Count the works
                    if let count = try? getWorkCount() {
                        print("Database contains \(count) works")
                        LogManager.shared.info("Database contains \(count) works")
                    }
                } else {
                    print("Database does not contain required 'works' table")
                    LogManager.shared.error("Database does not contain required 'works' table")
                    sqlite3_close(database)
                    errorMessage = "The selected file is not a valid works database"
                    showError = true
                }
            } else {
                print("Could not verify database structure")
                LogManager.shared.error("Could not verify database structure")
                sqlite3_close(database)
                errorMessage = "Could not verify database structure"
                showError = true
            }
        } else {
            if let database = db {
                let errorMsg = String(cString: sqlite3_errmsg(database))
                print("Error opening database: \(errorMsg)")
                LogManager.shared.error("Error opening database: \(errorMsg)")
                sqlite3_close(database)
                errorMessage = "Error opening database: \(errorMsg)"
            } else {
                print("Error opening database")
                LogManager.shared.error("Error opening database")
                errorMessage = "Error opening database"
            }
            showError = true
        }
        
        if !isDatabaseSelected {
            defaults.removeObject(forKey: databasePathKey)
        }
    }
    
    private func getWorkCount() throws -> Int {
        guard let db = db else { return 0 }
        
        var statement: OpaquePointer?
        let query = "SELECT COUNT(*) FROM works"
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "DatabaseError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare count query"])
        }
        
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NSError(domain: "DatabaseError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to execute count query"])
        }
        
        return Int(sqlite3_column_int(statement, 0))
    }
    
    func fetchWorks() -> [Work] {
        var works: [Work] = []
        guard let db = db else {
            print("Database connection is not initialized")
            LogManager.shared.error("Database connection is not initialized")
            return works
        }
        
        let queryString = "SELECT id, path, stylist, hair, makeup, talent, work_period FROM works ORDER BY id DESC"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, queryString, -1, &statement, nil) == SQLITE_OK else {
            print("Error preparing statement: \(String(cString: sqlite3_errmsg(db)))")
            LogManager.shared.error("Error preparing statement: \(String(cString: sqlite3_errmsg(db)))")
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
        
        print("Fetched \(works.count) works from database")
        LogManager.shared.info("Fetched \(works.count) works from database")
        return works
    }
    
    func getDatabase() -> OpaquePointer? {
        return db
    }
}
