import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var databaseManager = DatabaseManager.shared
    @State private var isFilePickerPresented = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Database") {
                    VStack(alignment: .leading) {
                        if let path = databaseManager.currentDatabasePath {
                            Text("Current Database:")
                                .bold()
                            Text(path)
                                .textSelection(.enabled)
                        } else {
                            Text("No database selected")
                                .foregroundColor(.secondary)
                        }
                        
                        Button {
                            isFilePickerPresented.toggle()
                        } label: {
                            Text("Select Database")
                        }
                        .padding(.top, 5)
                    }
                }
                
                Section("Logs") {
                    Button {
                        NSWorkspace.shared.selectFile(
                            nil,
                            inFileViewerRootedAtPath: LogManager.shared.logsDirectoryPath.path
                        )
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text("Open Logs Folder")
                        }
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
                    LogManager.shared.info("Selected database URL: \(url)")
                    databaseManager.setNewDatabase(sourceURL: url)
                }
            case .failure(let error):
                print("Error selecting database: \(error.localizedDescription)")
                LogManager.shared.error("Error selecting database: \(error.localizedDescription)")
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
}

#Preview {
    SettingsView()
}
