import SwiftUI
import Foundation
import SQLite3

class AddManager: ObservableObject {
    private let databaseManager = DatabaseManager.shared
    private let logManager = LogManager.shared
    private var progressWindowController: ImportProgressWindowController?
    
    init() {
        // Initialize progress window controller
        progressWindowController = ImportProgressWindowController()
    }
    
    func showOpenPanel(workId: Int, workPath: String) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.allowedContentTypes = [.jpeg, .png]

        openPanel.begin { [weak self] (result) in
            if result == .OK {
                let urls = openPanel.urls
                // Start import on background thread
                DispatchQueue.global(qos: .userInitiated).async {
                    self?.processSelectedItems(urls: urls, workId: workId, workPath: workPath)
                }
            }
        }
    }

    private func processSelectedItems(urls: [URL], workId: Int, workPath: String) {
        // Count total files including those in directories
        var totalFiles = 0
        for url in urls {
            if url.hasDirectoryPath {
                do {
                    let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                    totalFiles += contents.filter { url in
                        let fileExtension = url.pathExtension.lowercased()
                        return ["jpg", "jpeg", "png"].contains(fileExtension)
                    }.count
                } catch {
                    logManager.log("Error counting files in directory: \(error)", type: .error)
                }
            } else {
                totalFiles += 1
            }
        }
        
        logManager.log("Starting import of \(totalFiles) files", type: .add)
        
        // Show progress window on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.progressWindowController == nil {
                self.progressWindowController = ImportProgressWindowController()
            }
            self.progressWindowController?.showWindow(nil)
            if let window = self.progressWindowController?.window {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.center()
            }
            ImportProgress.shared.show(totalFiles: totalFiles)
        }
        
        var currentFileNumber = 0
        
        for url in urls {
            if url.hasDirectoryPath {
                self.importImagesFromDirectory(url: url, workId: workId, workPath: workPath) { fileName in
                    currentFileNumber += 1
                    DispatchQueue.main.async {
                        ImportProgress.shared.updateProgress(fileName: fileName, fileNumber: currentFileNumber)
                    }
                }
            } else {
                self.importImage(url: url, workId: workId, workPath: workPath)
                currentFileNumber += 1
                DispatchQueue.main.async {
                    ImportProgress.shared.updateProgress(fileName: url.lastPathComponent, fileNumber: currentFileNumber)
                }
            }
        }
        
        logManager.log("Finished importing files", type: .add)
        
        // Fetch updated files from database and refresh grid
        if let db = databaseManager.getDatabase() {
            var statement: OpaquePointer?
            let query = "SELECT id, file, ordered FROM files WHERE workid = ? ORDER BY ordered"
            
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(workId))
                
                var files: [(id: Int, path: String, order: Int)] = []
                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(statement, 0))
                    let file = String(cString: sqlite3_column_text(statement, 1))
                    let order = Int(sqlite3_column_int(statement, 2))
                    files.append((id: id, path: file, order: order))
                }
                
                sqlite3_finalize(statement)
                
                // Update grid and hide progress window on main thread
                DispatchQueue.main.async { [weak self] in
                    GridManager.shared.loadImages(forWorkPath: workPath, files: files)
                    ImportProgress.shared.hide()
                    self?.progressWindowController?.close()
                    self?.progressWindowController = nil
                }
            }
        }
        
        NotificationCenter.default.post(name: NSNotification.Name("RefreshGridView"), object: nil)
    }

    private func importImagesFromDirectory(url: URL, workId: Int, workPath: String, progress: @escaping (String) -> Void) {
        do {
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            let imageFiles = contents.filter { url in
                let fileExtension = url.pathExtension.lowercased()
                return ["jpg", "jpeg", "png"].contains(fileExtension)
            }
            
            for imageUrl in imageFiles {
                importImage(url: imageUrl, workId: workId, workPath: workPath)
                progress(imageUrl.lastPathComponent)
            }
        } catch {
            logManager.log("Error importing images from directory: \(error)", type: .error)
        }
    }

    private func importImage(url: URL, workId: Int, workPath: String) {
        do {
            let fileManager = FileManager.default
            
            // Get root folder path from UserDefaults
            guard let rootPath = UserDefaults.standard.string(forKey: "RootFolderPath") else {
                logManager.log("Root folder path not found", type: .error)
                return
            }
            
            // Create full destination path by combining root path and work path
            let fullPath = (rootPath as NSString).appendingPathComponent(workPath)
            let destinationDirUrl = URL(fileURLWithPath: fullPath, isDirectory: true)
            
            // Create destination directory if it doesn't exist
            if !fileManager.fileExists(atPath: destinationDirUrl.path) {
                try fileManager.createDirectory(at: destinationDirUrl, withIntermediateDirectories: true)
            }
            
            // Generate destination URL with full path
            let destinationUrl = destinationDirUrl.appendingPathComponent(url.lastPathComponent)
            
            // Copy file to destination
            if fileManager.fileExists(atPath: destinationUrl.path) {
                try fileManager.removeItem(at: destinationUrl)
            }
            try fileManager.copyItem(at: url, to: destinationUrl)
            
            logManager.log("Adding file: \(url.lastPathComponent)", type: .add)
            
            // Add entry to database - only store filename, not path
            let filename = url.lastPathComponent
            let stmt = "INSERT INTO files (workid, file, ordered) VALUES (?, ?, (SELECT COALESCE(MAX(ordered), 0) + 1 FROM files WHERE workid = ?))"
            
            guard let db = databaseManager.getDatabase() else {
                logManager.log("Database not available", type: .error)
                return
            }
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, stmt, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(workId))
                sqlite3_bind_text(statement, 2, (filename as NSString).utf8String, -1, nil)
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
