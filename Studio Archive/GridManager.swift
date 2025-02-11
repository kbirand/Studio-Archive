import Foundation
import AppKit
import SwiftUI

class GridManager: ObservableObject {
    static let shared = GridManager()
    
    @Published var selectedItemIndexes: Set<Int> = []
    @Published var gridItemSize: CGFloat = UserDefaults.standard.float(forKey: "GridItemSize") == 0 ? 200 : CGFloat(UserDefaults.standard.float(forKey: "GridItemSize"))
    @Published private(set) var progress: (current: Int, total: Int)?
    
    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private let cacheFolderName = "ImageCache"
    private let maxThumbnailSize: CGFloat = 512  // Maximum dimension for cached thumbnails
    
    struct GridItem: Identifiable, Equatable {
        let id: Int
        let originalPath: String
        let cachePath: String?
        var order: Int
        var image: NSImage?
        
        static func == (lhs: GridItem, rhs: GridItem) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    @Published var items: [GridItem] = []
    
    private struct BatchResult: Sendable {
        let id: Int
        let imageData: Data?
    }
    
    init() {
        // Initialize with stored grid size or default
        if defaults.float(forKey: "GridItemSize") == 0 {
            defaults.set(Float(200), forKey: "GridItemSize")
        }
        setupCacheDirectory()
    }
    
    private func setupCacheDirectory() {
        guard let cachePath = cacheDirPath else {
            print("❌ Could not determine cache directory path")
            return
        }
        
        // Create cache directory if it doesn't exist
        if !fileManager.fileExists(atPath: cachePath) {
            do {
                try fileManager.createDirectory(atPath: cachePath, withIntermediateDirectories: true)
                print("✅ Created cache directory at: \(cachePath)")
            } catch {
                print("❌ Failed to create cache directory: \(error)")
            }
        }
    }
    
    func updateGridItemSize(_ size: CGFloat) {
        gridItemSize = size
        defaults.set(Float(size), forKey: "GridItemSize")
    }
    
    func loadImages(forWorkPath workPath: String, files: [(id: Int, path: String, order: Int)]) {
        guard let rootPath = defaults.string(forKey: "RootFolderPath") else {
            print("⚠️ GridManager: Root path not found in UserDefaults")
            return
        }
        
        guard let bookmarkData = defaults.data(forKey: "RootFolderBookmark") else {
            print("⚠️ GridManager: Root folder bookmark not found")
            return
        }
        
        guard let cachePath = cacheDirPath else {
            print("❌ Could not determine cache directory path")
            return
        }
        
        print("📂 GridManager: Loading images")
        print("- Root path: \(rootPath)")
        print("- Work path: \(workPath)")
        print("- Cache path: \(cachePath)")
        print("- Files count: \(files.count)")
        
        // Reset progress
        progress = (0, files.count)
        
        // First create items with placeholder images
        items = files.map { file in
            let originalPath = (rootPath as NSString).appendingPathComponent((workPath as NSString).appendingPathComponent(file.1))
            let fileName = (file.1 as NSString).lastPathComponent
            let cacheFileName = "\(workPath.replacingOccurrences(of: "/", with: "_"))_\(fileName)"
            let cachePath = (cachePath as NSString).appendingPathComponent(cacheFileName)
            
            return GridItem(
                id: file.0,
                originalPath: originalPath,
                cachePath: cachePath,
                order: file.2,
                image: nil
            )
        }.sorted { $0.order > $1.order }
        
        // Then load images asynchronously
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var rootURL: URL?
            var isAccessingResource = false
            var processedCount = 0
            
            do {
                var isStale = false
                rootURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                if isStale {
                    print("⚠️ Bookmark is stale, needs to be recreated")
                    return
                }
                
                // Start accessing the security-scoped resource
                if rootURL!.startAccessingSecurityScopedResource() {
                    isAccessingResource = true
                    print("✅ Successfully started accessing security-scoped resource")
                } else {
                    print("❌ Failed to access security-scoped resource")
                    return
                }
                
                // Process images concurrently in batches
                let batchSize = 4 // Process 4 images at a time
                let batches = stride(from: 0, to: files.count, by: batchSize).map {
                    Array(files[$0..<min($0 + batchSize, files.count)])
                }
                
                for batch in batches {
                    let group = DispatchGroup()
                    let batchQueue = DispatchQueue(label: "com.studiarchive.imagebatch", attributes: .concurrent)
                    var results: [BatchResult] = []
                    let lock = NSLock()
                    
                    for file in batch {
                        group.enter()
                        batchQueue.async {
                            let originalPath = (rootPath as NSString).appendingPathComponent((workPath as NSString).appendingPathComponent(file.1))
                            let fileName = (file.1 as NSString).lastPathComponent
                            let cacheFileName = "\(workPath.replacingOccurrences(of: "/", with: "_"))_\(fileName)"
                            let cachePath = (cachePath as NSString).appendingPathComponent(cacheFileName)
                            
                            print("\n📸 Processing image for ID: \(file.0)")
                            print("- Original path: \(originalPath)")
                            print("- Cache path: \(cachePath)")
                            
                            var imageData: Data? = nil
                            
                            // Try to load from cache first
                            if self.fileManager.fileExists(atPath: cachePath) {
                                print("- Loading from cache")
                                imageData = try? Data(contentsOf: URL(fileURLWithPath: cachePath))
                                if imageData != nil {
                                    print("✅ Successfully loaded from cache")
                                } else {
                                    print("❌ Failed to load from cache")
                                }
                            }
                            
                            // If not in cache or failed to load from cache, generate it
                            if imageData == nil && self.fileManager.fileExists(atPath: originalPath) {
                                print("- Generating cache")
                                do {
                                    if let image = NSImage(contentsOfFile: originalPath) {
                                        // Calculate target size maintaining aspect ratio
                                        let originalSize = image.size
                                        var targetSize = originalSize
                                        
                                        // Only resize if image is larger than maxThumbnailSize
                                        if originalSize.width > self.maxThumbnailSize || originalSize.height > self.maxThumbnailSize {
                                            let widthRatio = self.maxThumbnailSize / originalSize.width
                                            let heightRatio = self.maxThumbnailSize / originalSize.height
                                            let scale = min(widthRatio, heightRatio)
                                            
                                            targetSize = NSSize(
                                                width: ceil(originalSize.width * scale),
                                                height: ceil(originalSize.height * scale)
                                            )
                                        }
                                        
                                        print("Original size: \(originalSize), Target size: \(targetSize)")
                                        
                                        // Create thumbnail representation
                                        let thumbnailImage = NSImage(size: targetSize)
                                        thumbnailImage.lockFocus()
                                        
                                        NSGraphicsContext.current?.imageInterpolation = .high
                                        image.draw(in: NSRect(origin: .zero, size: targetSize),
                                                 from: NSRect(origin: .zero, size: originalSize),
                                                 operation: .copy,
                                                 fraction: 1.0)
                                        
                                        thumbnailImage.unlockFocus()
                                        
                                        // Convert to JPEG and save to cache
                                        if let tiffData = thumbnailImage.tiffRepresentation,
                                           let bitmap = NSBitmapImageRep(data: tiffData),
                                           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                                            
                                            try jpegData.write(to: URL(fileURLWithPath: cachePath))
                                            print("✅ Successfully wrote cache file: \(targetSize)")
                                            
                                            lock.lock()
                                            results.append(BatchResult(id: file.0, imageData: jpegData))
                                            lock.unlock()
                                        }
                                    }
                                } catch {
                                    print("❌ Failed to process image: \(error)")
                                }
                            }
                            
                            // Thread-safe append to results
                            lock.lock()
                            results.append(BatchResult(id: file.0, imageData: imageData))
                            lock.unlock()
                            
                            group.leave()
                        }
                    }
                    
                    group.wait()
                    
                    // Update all items in the batch at once
                    DispatchQueue.main.async { [results] in
                        processedCount += batch.count
                        self.progress = (processedCount, files.count)
                        
                        // Update loaded images
                        for result in results {
                            if let itemIndex = self.items.firstIndex(where: { $0.id == result.id }) {
                                if let imageData = result.imageData,
                                   let image = NSImage(data: imageData) {
                                    self.items[itemIndex].image = image
                                }
                            }
                        }
                        self.objectWillChange.send()
                    }
                }
                
            } catch {
                print("❌ Failed to resolve bookmark: \(error)")
            }
            
            // Stop accessing the security-scoped resource
            if isAccessingResource {
                rootURL?.stopAccessingSecurityScopedResource()
                print("✅ Stopped accessing security-scoped resource")
            }
            
            DispatchQueue.main.async {
                self.progress = nil
                print("\n✅ GridManager: Finished loading all images")
            }
        }
    }
    
    func updateOrder(fromIndex: Int, toIndex: Int) {
        guard fromIndex != toIndex,
              fromIndex >= 0, fromIndex < items.count,
              toIndex >= 0, toIndex < items.count else { return }
        
        // Update local order
        let item = items.remove(at: fromIndex)
        items.insert(item, at: toIndex)
        
        // Update order values
        for (index, item) in items.enumerated() {
            let newOrder = items.count - index // Reverse the order to match DESC in SQL
            if item.order != newOrder {
                // Update database
                Task {
                    do {
                        if try await DatabaseManager.shared.updateFileOrder(fileId: item.id, newOrder: newOrder) {
                            // Update local items array with new item
                            DispatchQueue.main.async {
                                self.items[index] = GridItem(
                                    id: item.id,
                                    originalPath: item.originalPath,
                                    cachePath: item.cachePath,
                                    order: newOrder,
                                    image: item.image
                                )
                            }
                        }
                    } catch {
                        print("❌ Failed to update file order in database: \(error)")
                    }
                }
            }
        }
    }
    
    private var cacheDirPath: String? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("Studio Archive").appendingPathComponent(cacheFolderName).path
    }
}
