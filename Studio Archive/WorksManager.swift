import Foundation
import SQLite3

class WorksManager: ObservableObject {
    static let shared = WorksManager()
    private let databaseManager = DatabaseManager.shared
    
    @Published var errorMessage: String = ""
    @Published var showError: Bool = false
    
    private init() {}
    
    private func getRootFolderURL() -> URL? {
        guard let rootPath = UserDefaults.standard.string(forKey: "RootFolderPath"),
              rootPath != "Not Selected" else {
            errorMessage = "Root folder not selected in settings"
            showError = true
            return nil
        }
        
        return URL(fileURLWithPath: rootPath)
    }

    private func getNextFolderPrefix() -> String {
        let fileManager = FileManager.default
        guard let rootURL = getRootFolderURL() else {
            return "001000"
        }
        
        do {
            // Get all items in the directory
            let items = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
            
            // Filter directories and get their names
            let folderNames = items.filter { url in
                var isDirectory: ObjCBool = false
                fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                return isDirectory.boolValue
            }.map { $0.lastPathComponent }
            
            // Filter folder names that match our pattern (6 digits followed by underscore)
            let prefixes = folderNames.compactMap { name -> Int? in
                guard let match = name.range(of: "^\\d{6}_", options: .regularExpression) else { return nil }
                return Int(name[..<match.upperBound].dropLast())
            }
            
            // Get the highest prefix number
            let highestPrefix = prefixes.max() ?? 1790  // Start from 001790 if no existing folders
            
            // Return the next prefix number formatted as 6 digits
            return String(format: "%06d", highestPrefix + 2)
        } catch {
            LogManager.shared.log("Error getting folder prefix: \(error)", type: .error)
            return "001000"
        }
    }
    
    func addNewWork(workPeriod: String) -> Bool {
        guard let db = databaseManager.getDatabase() else {
            errorMessage = "Database is not available"
            showError = true
            return false
        }
        
        // Get root folder URL
        guard let rootURL = getRootFolderURL() else {
            return false
        }
        
        // Create the new folder name with prefix
        let prefix = getNextFolderPrefix()
        let folderName = "\(prefix)_\(workPeriod)"
        
        let folderURL = rootURL.appendingPathComponent(folderName)
        
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            errorMessage = "Failed to create directory: \(error.localizedDescription)"
            showError = true
            return false
        }
        
        var statement: OpaquePointer?
        let insertSQL = "INSERT INTO works (work_period, path) VALUES (?, ?)"
        
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
        // Bind the path - store only the folder name instead of full path
        sqlite3_bind_text(statement, 2, (folderName as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) != SQLITE_DONE {
            errorMessage = "Failed to insert work"
            showError = true
            return false
        }
        
        LogManager.shared.log("Successfully created work: \(workPeriod) with folder: \(folderName)", type: .info)
        return true
    }
}
