import Foundation

class LogManager {
    static let shared = LogManager()
    private let dateFormatter: DateFormatter
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.studioarchive.logmanager", qos: .utility)
    private var logsDirectory: URL
    
    var currentLogPath: URL? {
        getCurrentLogFile()
    }
    
    var logsDirectoryPath: URL {
        logsDirectory
    }
    
    private init() {
        // Set up date formatter for timestamps
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        // Get the app's documents directory
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Create a logs directory if it doesn't exist
        logsDirectory = documentsPath.appendingPathComponent("Logs", isDirectory: true)
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }
    
    private func getCurrentLogFile() -> URL {
        let today = Date()
        let dateString = today.formatted(.iso8601.year().month().day())
        let logFileURL = logsDirectory.appendingPathComponent("\(dateString).log")
        
        // Create the log file if it doesn't exist
        if !fileManager.fileExists(atPath: logFileURL.path) {
            fileManager.createFile(atPath: logFileURL.path, contents: nil)
            
            // Add header to new log file
            let header = "=== Log started on \(dateFormatter.string(from: today)) ===\n"
            try? header.write(to: logFileURL, atomically: true, encoding: .utf8)
        }
        
        return logFileURL
    }
    
    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }
    
    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let timestamp = self.dateFormatter.string(from: Date())
            let fileName = (file as NSString).lastPathComponent
            let logMessage = "\(timestamp) [\(level.rawValue)] [\(fileName):\(line)] \(function): \(message)\n"
            
            let logFileURL = self.getCurrentLogFile()
            
            do {
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(logMessage.data(using: .utf8)!)
                    handle.closeFile()
                }
            }
            
            // Also print to console in debug builds
            #if DEBUG
            print(logMessage, terminator: "")
            #endif
        }
    }
    
    func getLogFileContents() -> String? {
        guard let logFileURL = currentLogPath else { return nil }
        return try? String(contentsOf: logFileURL, encoding: .utf8)
    }
    
    func clearCurrentLogFile() {
        queue.async { [weak self] in
            guard let self = self,
                  let logFileURL = self.currentLogPath else { return }
            try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        }
    }
    
    func getLogFiles() -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        
        return files.filter { $0.pathExtension == "log" }
    }
}

// Extension to make logging more convenient
extension LogManager {
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
}
