import Foundation

class LogManager {
    static let shared = LogManager()
    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter
    private var currentLogFile: URL?
    private let logsDirectory: URL
    
    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        // Get the application support directory
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access Application Support directory")
        }
        
        // Create a logs directory within application support
        logsDirectory = appSupportURL.appendingPathComponent("Studio Archive/Logs", isDirectory: true)
        
        // Create logs directory if it doesn't exist
        do {
            try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        } catch {
            // Since we can't log to file yet, use print for initialization errors
            print("Error creating logs directory: \(error)")
        }
        
        // Set up the initial log file
        setupNewLogFile()
    }
    
    private func setupNewLogFile() {
        let today = Calendar.current.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = "log-\(formatter.string(from: today)).log"
        currentLogFile = logsDirectory.appendingPathComponent(fileName)
    }
    
    private func ensureCorrectLogFile() {
        let today = Calendar.current.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = "log-\(formatter.string(from: today)).log"
        let todayLogFile = logsDirectory.appendingPathComponent(fileName)
        
        if currentLogFile != todayLogFile {
            currentLogFile = todayLogFile
        }
    }
    
    func log(_ message: String, type: LogType = .info, file: String = #file, function: String = #function, line: Int = #line) {
        ensureCorrectLogFile()
        
        guard let logFile = currentLogFile else { return }
        
        let timestamp = dateFormatter.string(from: Date())
        let fileURL = URL(fileURLWithPath: file)
        let fileName = fileURL.lastPathComponent
        
        let logMessage = "[\(timestamp)] [\(type.rawValue)] [\(fileName):\(line)] \(function): \(message)"
        
        // Print to standard output
        print(logMessage)
        
        // Add newline for file
        let fileLogMessage = logMessage + "\n"
        
        do {
            if !fileManager.fileExists(atPath: logFile.path) {
                try "".write(to: logFile, atomically: true, encoding: .utf8)
            }
            
            let handle = try FileHandle(forWritingTo: logFile)
            handle.seekToEndOfFile()
            if let data = fileLogMessage.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } catch {
            // If we can't write to the log file, fall back to print
            print("Error writing to log file: \(error)")
        }
    }
    
    func clearOldLogs(olderThan days: Int = 7) -> (deleted: Int, remaining: Int) {
        var deletedCount = 0
        var remainingCount = 0
        do {
            let files = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey])
            let oldDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            
            for file in files {
                if let creationDate = try file.resourceValues(forKeys: [.creationDateKey]).creationDate {
                    if creationDate < oldDate {
                        try fileManager.removeItem(at: file)
                        deletedCount += 1
                    } else {
                        remainingCount += 1
                    }
                }
            }
        } catch {
            print("Error clearing old logs: \(error)")
        }
        return (deletedCount, remainingCount)
    }
    
    func logError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, type: .error, file: file, function: function, line: line)
    }
    
    var logsDirectoryPath: String {
        return logsDirectory.path
    }
    
    var currentLogFilePath: String? {
        return currentLogFile?.path
    }
    
    func getRecentLogs(count: Int = 5) -> [(name: String, date: Date, path: String)] {
        do {
            let files = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey])
            let logFiles = files.compactMap { url -> (name: String, date: Date, path: String)? in
                guard url.pathExtension == "log",
                      let creationDate = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate else {
                    return nil
                }
                return (url.lastPathComponent, creationDate, url.path)
            }
            .sorted(by: { $0.date > $1.date })
            
            return Array(logFiles.prefix(count))
        } catch {
            print("Error getting recent logs: \(error)")
            return []
        }
    }
}

enum LogType: String {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case debug = "DEBUG"
    case add = "ADD"
    case delete = "DELETE"
}
