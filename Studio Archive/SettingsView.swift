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
    
    private let defaults = UserDefaults.standard
    
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
                Section("Database") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Database File")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button("Change") {
                                isFilePickerPresented = true
                            }
                        }
                        
                        if let path = databaseManager.currentDatabasePath {
                            Button {
                                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                            } label: {
                                HStack {
                                    Text(path)
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    
                                    Image(systemName: "arrow.up.forward.square")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("No database selected")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Section("Root Folder") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Root Folder")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button("Select Folder") {
                                selectRootFolder()
                            }
                        }
                        
                        Text(rootFolderPath)
                            .font(.caption)
                    }
                }
                
                Section("Grid Item Size") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Grid Item Size")
                                .font(.headline)
                            
                            Spacer()
                        }
                        
                        HStack {
                            Text("100")
                            Slider(value: $gridItemSize, in: 100...1000) { _ in
                                defaults.set(Float(gridItemSize), forKey: "GridItemSize")
                                gridManager.updateGridItemSize(CGFloat(gridItemSize))
                            }
                            Text("1000")
                        }
                        Text("\(Int(gridItemSize))px")
                            .foregroundColor(.gray)
                    }
                }
                
                Section("Performance") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Concurrent Image Processing")
                                .font(.headline)
                            Spacer()
                        }
                        
                        HStack {
                            Text("4")
                            Slider(value: $batchSize, in: 4...Double(maxBatchSize)) { _ in
                                defaults.set(Int(batchSize), forKey: "ImageBatchSize")
                            }
                            Text("\(maxBatchSize)")
                        }
                        
                        Text("\(Int(batchSize)) images at once")
                            .foregroundColor(.gray)
                        
                        Text("Higher values may improve performance on machines with more CPU cores, but could cause slowdown if set too high.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.top, 4)
                    }
                }
            }
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
