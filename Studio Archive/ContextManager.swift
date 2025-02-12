import SwiftUI
import AppKit
import UniformTypeIdentifiers

class ContextManager: ObservableObject {
    static let shared = ContextManager()
    @Published var showDeleteConfirmation = false
    @Published var itemToDelete: (id: Int, path: String)? = nil
    
    // Share the selected file using system share sheet
    func shareFile(path: String?) {
        guard let path = path, let url = URL(string: "file://" + path) else { return }
        let sharingPicker = NSSharingServicePicker(items: [url])
        sharingPicker.show(relativeTo: .zero, of: NSApp.keyWindow?.contentView ?? NSView(), preferredEdge: .minY)
    }
    
    // Copy file path to clipboard
    func copyPath(path: String?) {
        guard let path = path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
    
    // Open file in Finder
    func openInFinder(path: String?) {
        guard let path = path else { return }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
    
    // Delete file from cache and database
    func deleteFile(id: Int, cachePath: String?) {
        guard let cachePath = cachePath else { return }
        // Delete from database
        _ = DatabaseManager.shared.deleteFile(id: id)
        
        // Delete cache file
        do {
            try FileManager.default.removeItem(atPath: cachePath)
            LogManager.shared.log("Successfully deleted cache file: \(cachePath)", type: .info)
        } catch {
            LogManager.shared.log("Failed to delete cache file: \(error.localizedDescription)", type: .error)
        }
        
        // Refresh the grid
        DetailsManager.shared.refreshFiles()
    }
}

struct ContextMenuView: View {
    let id: Int
    let originalPath: String
    let cachePath: String
    @StateObject private var contextManager = ContextManager.shared
    
    var body: some View {
        Group {
            Button(action: {
                contextManager.shareFile(path: originalPath)
            }) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            
            Button(action: {
                contextManager.copyPath(path: originalPath)
            }) {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            
            Button(action: {
                contextManager.openInFinder(path: originalPath)
            }) {
                Label("Show in Finder", systemImage: "folder")
            }
            
            Divider()
            
            Button(role: .destructive, action: {
                contextManager.itemToDelete = (id: id, path: cachePath)
                contextManager.showDeleteConfirmation = true
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct DeleteConfirmationDialog: View {
    @StateObject private var contextManager = ContextManager.shared
    
    var body: some View {
        if let itemToDelete = contextManager.itemToDelete {
            EmptyView()
                .alert("Confirm Deletion", isPresented: $contextManager.showDeleteConfirmation) {
                    Button("Delete", role: .destructive) {
                        contextManager.deleteFile(id: itemToDelete.id, cachePath: itemToDelete.path)
                        contextManager.itemToDelete = nil
                        DetailsManager.shared.refreshFiles()
                    }
                    Button("Cancel", role: .cancel) {
                        contextManager.itemToDelete = nil
                    }
                } message: {
                    Text("This will remove the cached thumbnail and database entry, but won't affect the original file.")
                }
        }
    }
}
