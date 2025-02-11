import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var databaseManager = DatabaseManager.shared
    @StateObject private var gridManager = GridManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isFilePickerPresented = false
    @State private var gridItemSize: Double
    @State private var rootFolderPath: String
    
    private let defaults = UserDefaults.standard
    
    init() {
        _gridItemSize = State(initialValue: Double(UserDefaults.standard.float(forKey: "GridItemSize")))
        _rootFolderPath = State(initialValue: UserDefaults.standard.string(forKey: "RootFolderPath") ?? "Not Selected")
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
                                gridManager.updateGridItemSize(CGFloat(gridItemSize))
                            }
                            Text("1000")
                        }
                        Text("\(Int(gridItemSize))px")
                            .foregroundColor(.gray)
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
                    UserDefaults.standard.set(bookmarkData, forKey: "RootFolderBookmark")
                    UserDefaults.standard.set(url.path, forKey: "RootFolderPath")
                    
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
