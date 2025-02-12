import SwiftUI
import Foundation
import SQLite3

class AddManager: ObservableObject {
    private let databaseManager = DatabaseManager.shared
    private let logManager = LogManager.shared
    
    func showOpenPanel(workId: Int, workPath: String) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.allowedFileTypes = ["png", "jpg", "jpeg"]

        openPanel.begin { (result) in
            if result == .OK {
                let urls = openPanel.urls
                self.processSelectedItems(urls: urls, workId: workId, workPath: workPath)
            }
        }
    }

    private func processSelectedItems(urls: [URL], workId: Int, workPath: String) {
        for url in urls {
            if url.hasDirectoryPath {
                self.importImagesFromDirectory(url: url, workId: workId, workPath: workPath)
            } else {
                self.importImage(url: url, workId: workId, workPath: workPath)
            }
        }
        NotificationCenter.default.post(name: NSNotification.Name("RefreshGridView"), object: nil)
    }

    private func importImagesFromDirectory(url: URL, workId: Int, workPath: String) {
        do {
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            let imageFiles = contents.filter { url in
                let fileExtension = url.pathExtension.lowercased()
                return ["jpg", "jpeg", "png"].contains(fileExtension)
            }
            
            for imageUrl in imageFiles {
                importImage(url: imageUrl, workId: workId, workPath: workPath)
            }
        } catch {
            logManager.log("Error importing images from directory: \(error)", type: .error)
        }
    }

    private func importImage(url: URL, workId: Int, workPath: String) {
        do {
            let fileManager = FileManager.default
            
            // Create destination directory if it doesn't exist
            let destinationDirUrl = URL(fileURLWithPath: workPath)
            if !fileManager.fileExists(atPath: workPath) {
                try fileManager.createDirectory(at: destinationDirUrl, withIntermediateDirectories: true)
            }
            
            // Generate destination URL
            let destinationUrl = destinationDirUrl.appendingPathComponent(url.lastPathComponent)
            
            // Copy file to destination
            if fileManager.fileExists(atPath: destinationUrl.path) {
                try fileManager.removeItem(at: destinationUrl)
            }
            try fileManager.copyItem(at: url, to: destinationUrl)
            
            // Add entry to database
            let relativePath = destinationUrl.lastPathComponent
            let stmt = "INSERT INTO files (work_id, path, file_order) SELECT ?, ?, COALESCE(MAX(file_order), 0) + 1 FROM files WHERE work_id = ?"
            
            guard let db = databaseManager.getDatabase() else {
                logManager.log("Database not available", type: .error)
                return
            }
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, stmt, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(workId))
                sqlite3_bind_text(statement, 2, (relativePath as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 3, Int32(workId))
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    logManager.log("Error inserting file into database: \(String(cString: sqlite3_errmsg(db)))", type: .error)
                }
                
                sqlite3_finalize(statement)
            }
            
            logManager.log("Successfully imported image: \(url.lastPathComponent)", type: .info)
        } catch {
            logManager.log("Error importing image: \(error)", type: .error)
        }
    }
}
