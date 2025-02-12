import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var databaseManager = DatabaseManager.shared
    @StateObject private var gridManager = GridManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isFilePickerPresented = false
    @State private var gridItemSize: Double
    @State private var rootFolderPath: String
    @State private var batchSize: Double
    @State private var showLogsFinder = false
    
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
                                gridManager.deleteCache()
                            } label: {
                                Label("Clear Cache", systemImage: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        
                        Text("Deletes all cached thumbnail images to free up space")
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
                                logManager.clearOldLogs(olderThan: 30)
                            } label: {
                                Label("Clear Old Logs", systemImage: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                            .padding(.top, 2)
                        }
                    }
                } header: {
                    Text("Logs")
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
}

#Preview {
    SettingsView()
}
