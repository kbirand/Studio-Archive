import SwiftUI
import Foundation

class AddManager {
    func showOpenPanel() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.allowedFileTypes = ["png", "jpg", "jpeg"]

        openPanel.begin { (result) in
            if result == .OK {
                let urls = openPanel.urls
                self.processSelectedItems(urls: urls)
            }
        }
    }

    private func processSelectedItems(urls: [URL]) {
        for url in urls {
            if url.hasDirectoryPath {
                self.importImagesFromDirectory(url: url)
            } else {
                self.importImage(url: url)
            }
        }
        // Refresh grid and update database here
    }

    private func importImagesFromDirectory(url: URL) {
        // Logic to import images from a directory
    }

    private func importImage(url: URL) {
        // Logic to import a single image
    }
}

