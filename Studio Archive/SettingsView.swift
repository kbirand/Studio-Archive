import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var databaseManager = DatabaseManager.shared
    @StateObject private var gridManager = GridManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isFilePickerPresented = false
    @State private var showLogClearAlert = false
    @State private var logsClearedCount = 0
    @State private var logsRemainingCount = 0
    @State private var showCacheClearAlert = false
    @State private var gridItemSize: Double
    @State private var rootFolderPath: String
    @State private var batchSize: Double
    @State private var showLogsFinder = false
    @State private var cacheSize: Double
    @State private var showVisibilityCheckboxes: Bool
    @State private var hideInvisibleWorks: Bool
    
    private let defaults = UserDefaults.standard
    private let logManager = LogManager.shared
    
    private var maxBatchSize: Int {
        let activeProcessorCount = ProcessInfo.processInfo.activeProcessorCount
        return max(4, activeProcessorCount * 3)
    }
    
    init() {
        _gridItemSize = State(initialValue: Double(UserDefaults.standard.float(forKey: "GridItemSize")))
        _rootFolderPath = State(initialValue: UserDefaults.standard.string(forKey: "RootFolderPath") ?? "Not Selected")
        _batchSize = State(initialValue: Double(UserDefaults.standard.integer(forKey: "ImageBatchSize")))
        let defaultCacheSize = UserDefaults.standard.integer(forKey: "MaxCacheSize")
        _cacheSize = State(initialValue: Double(defaultCacheSize > 0 ? defaultCacheSize : 500))
        _showVisibilityCheckboxes = State(initialValue: UserDefaults.standard.bool(forKey: "ShowVisibilityCheckboxes"))
        _hideInvisibleWorks = State(initialValue: UserDefaults.standard.bool(forKey: "HideInvisibleWorks"))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Database Location", systemImage: "externaldrive")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button(action: { isFilePickerPresented = true }) {
                                Label("Change", systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(.borderless)
                        }
                        
                        if let path = databaseManager.currentDatabasePath {
                            Button {
                                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                            } label: {
                                HStack {
                                    Text(path)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    Image(systemName: "arrow.up.forward.square")
                                        .foregroundColor(.accentColor)
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            Label("No database selected", systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                    }
                } header: {
                    Text("Database")
                        .textCase(.uppercase)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Root Folder", systemImage: "folder")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button(action: selectRootFolder) {
                                Label("Select", systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(.borderless)
                        }
                        
                        Text(rootFolderPath)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Location")
                        .textCase(.uppercase)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Grid Item Size", systemImage: "square.grid.3x3")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Slider(value: $gridItemSize, in: 100...1000) { _ in
                                defaults.set(Float(gridItemSize), forKey: "GridItemSize")
                                gridManager.updateGridItemSize(CGFloat(gridItemSize))
                            }
                            
                            HStack {
                                Text("100px")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("\(Int(gridItemSize))px")
                                    .font(.subheadline)
                                    .foregroundColor(.accentColor)
                                
                                Spacer()
                                
                                Text("1000px")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        Toggle(isOn: Binding(
                            get: { gridManager.showFilenames },
                            set: { gridManager.updateShowFilenames($0) }
                        )) {
                            Label("Show Filenames", systemImage: "text.below.photo")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Appearance")
                        .textCase(.uppercase)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Image Cache", systemImage: "photo.stack")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button {
                                showCacheClearAlert = true
                            } label: {
                                Label("Clear Cache", systemImage: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                            .alert("Clear Image Cache?", isPresented: $showCacheClearAlert) {
                                Button("Cancel", role: .cancel) { }
                                Button("Clear Cache", role: .destructive) {
                                    gridManager.deleteCache()
                                }
                            } message: {
                                Text("This will delete all cached thumbnail images. The thumbnails will be regenerated when needed.")
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Cache Directory")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Change") {
                                    selectCacheDirectory()
                                }
                                .foregroundColor(.accentColor)
                            }
                            
                            Text(gridManager.getCurrentCachePath())
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        Label("Cache Size", systemImage: "memorychip")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Slider(value: $cacheSize, in: 100...2000, step: 100) { _ in
                                let intValue = Int(cacheSize)
                                defaults.set(intValue, forKey: "MaxCacheSize")
                                gridManager.updateMaxCacheSize(intValue)
                            }
                            
                            HStack {
                                Text("100")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("\(Int(cacheSize)) thumbnails")
                                    .font(.subheadline)
                                    .foregroundColor(.accentColor)
                                
                                Spacer()
                                
                                Text("2000")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text("Number of thumbnails to keep in memory")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Cache Management")
                        .textCase(.uppercase)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Concurrent Processing", systemImage: "cpu")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            
                            Slider(value: $batchSize, in: 4...Double(maxBatchSize)) { _ in
                                defaults.set(Int(batchSize), forKey: "ImageBatchSize")
                            }
                            
                            HStack {
                                Text("4")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("\(Int(batchSize)) images at once")
                                    .font(.subheadline)
                                    .foregroundColor(.accentColor)
                                
                                Spacer()
                                
                                Text("\(maxBatchSize)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text("Higher values may improve performance on machines with more CPU cores, but could cause slowdown if set too high.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                } header: {
                    Text("Performance")
                        .textCase(.uppercase)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Application Logs", systemImage: "doc.text")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logManager.logsDirectoryPath)
                            } label: {
                                Label("Open in Finder", systemImage: "arrow.up.forward.square")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.borderless)
                        }
                        
                        if !logManager.getRecentLogs().isEmpty {
                            Text("Recent Logs:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            ForEach(logManager.getRecentLogs(), id: \.path) { log in
                                Button {
                                    NSWorkspace.shared.selectFile(log.path, inFileViewerRootedAtPath: "")
                                } label: {
                                    HStack {
                                        Text(log.name)
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                        
                                        Spacer()
                                        
                                        Text(log.date, style: .date)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Button(role: .destructive) {
                                let result = logManager.clearOldLogs(olderThan: 7)
                                logsClearedCount = result.deleted
                                logsRemainingCount = result.remaining
                                showLogClearAlert = true
                            } label: {
                                Label("Clear Old Logs (>7 days)", systemImage: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                            .padding(.top, 2)
                            .alert("Logs Cleared", isPresented: $showLogClearAlert) {
                                Button("OK", role: .cancel) { }
                            } message: {
                                if logsClearedCount > 0 {
                                    Text("\(logsClearedCount) log file\(logsClearedCount == 1 ? " was" : "s were") deleted.\nYou have \(logsRemainingCount) recent log file\(logsRemainingCount == 1 ? "" : "s") remaining.")
                                } else {
                                    Text("No log files older than 7 days were found.\nYou have \(logsRemainingCount) recent log file\(logsRemainingCount == 1 ? "" : "s").")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Logs")
                        .textCase(.uppercase)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Work Visibility", systemImage: "eye")
                            .font(.headline)
                        
                        HStack {
                            Toggle("Show Visibility Checkboxes", isOn: Binding(
                                get: { showVisibilityCheckboxes },
                                set: { newValue in
                                    showVisibilityCheckboxes = newValue
                                    UserDefaults.standard.set(newValue, forKey: "ShowVisibilityCheckboxes")
                                    NotificationCenter.default.post(name: Notification.Name("VisibilitySettingsChanged"), object: nil)
                                }
                            ))
                            .toggleStyle(.switch)
                            
                            Spacer()
                            Text("⌘H")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        
                        HStack {
                            Toggle("Hide Invisible Works", isOn: Binding(
                                get: { hideInvisibleWorks },
                                set: { newValue in
                                    hideInvisibleWorks = newValue
                                    UserDefaults.standard.set(newValue, forKey: "HideInvisibleWorks")
                                    NotificationCenter.default.post(name: Notification.Name("VisibilitySettingsChanged"), object: nil)
                                }
                            ))
                            .toggleStyle(.switch)
                            
                            Spacer()
                            Text("⇧⌘H")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Visibility")
                        .textCase(.uppercase)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 500, maxWidth: .infinity, minHeight: 600, maxHeight: 700)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [UTType(filenameExtension: "db")!],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    print("Selected database URL: \(url)")
                    databaseManager.setNewDatabase(sourceURL: url)
                }
            case .failure(let error):
                print("Error selecting database: \(error.localizedDescription)")
                databaseManager.errorMessage = "Error selecting database: \(error.localizedDescription)"
                databaseManager.showError = true
            }
        }
        .alert("Error", isPresented: $databaseManager.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(databaseManager.errorMessage)
        }
    }
    
    private func selectRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                do {
                    // Create a security-scoped bookmark
                    let bookmarkData = try url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    
                    // Save the bookmark data
                    defaults.set(bookmarkData, forKey: "RootFolderBookmark")
                    defaults.set(url.path, forKey: "RootFolderPath")
                    rootFolderPath = url.path
                    
                    print("✅ Created and saved bookmark for: \(url.path)")
                } catch {
                    print("❌ Failed to create bookmark: \(error)")
                }
            }
        }
    }
    
    private func selectCacheDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Select Cache Directory"
        panel.message = "Choose a directory for storing image cache"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                gridManager.setCacheDirPath(url.path)
            }
        }
    }
}

#Preview {
    SettingsView()
}
