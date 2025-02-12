import Foundation
import AppKit
import SwiftUI
import ImageIO

class GridManager: ObservableObject, @unchecked Sendable {
    static let shared = GridManager()
    
    @Published var selectedItemIndexes: Set<Int> = []
    @Published var gridItemSize: CGFloat = UserDefaults.standard.float(forKey: "GridItemSize") == 0 ? 200 : CGFloat(UserDefaults.standard.float(forKey: "GridItemSize"))
    @Published private(set) var progress: (current: Int, total: Int)?
    
    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private let cacheFolderName = "ImageCache"
    private let maxThumbnailSize: CGFloat = 512  // Maximum dimension for cached thumbnails
    private var imageCache: [Int: NSImage] = [:]  // Separate image cache
    private let maxCacheSize = 100 // Maximum number of images to keep in memory
    private var imageCacheQueue = DispatchQueue(label: "com.studiarchive.imagecache")
    private var imageAccessTimes: [Int: Date] = [:] // Track when each image was last accessed
    
    // Maximum possible batch size based on CPU cores
    private var maxBatchSize: Int {
        let activeProcessorCount = ProcessInfo.processInfo.activeProcessorCount
        return max(4, activeProcessorCount * 3)
    }
    
    // Get batch size from UserDefaults or use default
    private var batchSize: Int {
        let size = defaults.integer(forKey: "ImageBatchSize")
        return size == 0 ? 4 : min(max(4, size), maxBatchSize)
    }
    
    struct GridItem: Identifiable, Equatable, Sendable {
        let id: Int
        let originalPath: String
        let cachePath: String?
        var order: Int
        
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
        guard let cachePath = getCacheDirectoryPath() else {
            LogManager.shared.log("Cache directory path is nil", type: .error)
            return
        }
        
        if !fileManager.fileExists(atPath: cachePath) {
            do {
                try fileManager.createDirectory(atPath: cachePath, withIntermediateDirectories: true)
                LogManager.shared.log("Created cache directory at: \(cachePath)", type: .info)
            } catch {
                LogManager.shared.log("Failed to create cache directory: \(error)", type: .error)
            }
        } else {
            LogManager.shared.log("Cache directory already exists at: \(cachePath)", type: .debug)
        }
    }
    
    func updateGridItemSize(_ size: CGFloat) {
        gridItemSize = size
        defaults.set(Float(size), forKey: "GridItemSize")
    }
    
    func loadImages(forWorkPath workPath: String, files: [(id: Int, path: String, order: Int)]) {
        guard let rootPath = defaults.string(forKey: "RootFolderPath") else {
            LogManager.shared.log("GridManager: Root path not found in UserDefaults", type: .warning)
            return
        }
        
        // Clear the cache before loading new work
        clearCache()
        
        guard let bookmarkData = defaults.data(forKey: "RootFolderBookmark") else {
            LogManager.shared.log("GridManager: Root folder bookmark not found", type: .warning)
            return
        }
        
        guard let cachePath = getCacheDirectoryPath() else {
            LogManager.shared.log("Could not determine cache directory path", type: .error)
            return
        }
        
        LogManager.shared.log("GridManager: Loading images", type: .info)
        LogManager.shared.log("Root path: \(rootPath)", type: .debug)
        LogManager.shared.log("Work path: \(workPath)", type: .debug)
        LogManager.shared.log("Cache path: \(cachePath)", type: .debug)
        LogManager.shared.log("Files count: \(files.count)", type: .debug)
        
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
                order: file.2
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
                    LogManager.shared.log("Bookmark is stale, needs to be recreated", type: .warning)
                    return
                }
                
                // Start accessing the security-scoped resource
                if rootURL!.startAccessingSecurityScopedResource() {
                    isAccessingResource = true
                    LogManager.shared.log("Successfully started accessing security-scoped resource", type: .info)
                } else {
                    LogManager.shared.log("Failed to access security-scoped resource", type: .error)
                    return
                }
                
                // Process images in batches
                let batches = stride(from: 0, to: files.count, by: self.batchSize).map {
                    Array(files[$0..<min($0 + self.batchSize, files.count)])
                }
                
                LogManager.shared.log("Processing images in \(batches.count) batches of up to \(self.batchSize) images each", type: .info)
                LogManager.shared.log("Total images: \(files.count)", type: .debug)
                LogManager.shared.log("Active CPU cores: \(ProcessInfo.processInfo.activeProcessorCount)", type: .debug)
                LogManager.shared.log("Batch size: \(self.batchSize)", type: .debug)
                
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
                            
                            LogManager.shared.log("Processing image for ID: \(file.0)", type: .debug)
                            LogManager.shared.log("Original path: \(originalPath)", type: .debug)
                            LogManager.shared.log("Cache path: \(cachePath)", type: .debug)
                            
                            var imageData: Data? = nil
                            
                            // Try to load from cache first
                            if self.fileManager.fileExists(atPath: cachePath) {
                                LogManager.shared.log("Loading from cache", type: .debug)
                                imageData = try? Data(contentsOf: URL(fileURLWithPath: cachePath))
                                if imageData != nil {
                                    LogManager.shared.log("Successfully loaded from cache", type: .debug)
                                } else {
                                    LogManager.shared.log("Failed to load from cache", type: .warning)
                                }
                            }
                            
                            // If not in cache or failed to load from cache, generate it
                            if imageData == nil && self.fileManager.fileExists(atPath: originalPath) {
                                LogManager.shared.log("Attempting to load thumbnail for: \(originalPath)", type: .debug)
                                do {
                                    // First try to get embedded thumbnail
                                    if let embeddedThumbnail = self.extractEmbeddedThumbnail(from: originalPath) {
                                        if let tiffData = embeddedThumbnail.tiffRepresentation,
                                           let bitmapRep = NSBitmapImageRep(data: tiffData),
                                           let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                                            imageData = jpegData
                                            try imageData?.write(to: URL(fileURLWithPath: cachePath))
                                            LogManager.shared.log("Successfully saved embedded thumbnail to cache: \(cachePath)", type: .debug)
                                        } else {
                                            LogManager.shared.log("Failed to convert embedded thumbnail to JPEG", type: .warning)
                                        }
                                    } else {
                                        LogManager.shared.log("No embedded thumbnail found, falling back to full image", type: .debug)
                                    }
                                    
                                    // If no embedded thumbnail, fall back to generating one
                                    if imageData == nil, let image = NSImage(contentsOfFile: originalPath) {
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
                                        
                                        LogManager.shared.log("Original size: \(originalSize), Target size: \(targetSize)", type: .debug)
                                        
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
                                            LogManager.shared.log("Successfully wrote cache file: \(targetSize)", type: .debug)
                                            imageData = jpegData
                                        }
                                    }
                                } catch {
                                    LogManager.shared.log("Failed to process image: \(error)", type: .error)
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
                            if self.items.contains(where: { $0.id == result.id }),
                               let imageData = result.imageData,
                               let image = NSImage(data: imageData) {
                                self.setImage(for: result.id, image: image)
                            }
                        }
                        self.objectWillChange.send()
                    }
                }
                
            } catch {
                LogManager.shared.log("Failed to resolve bookmark: \(error)", type: .error)
            }
            
            // Stop accessing the security-scoped resource
            if isAccessingResource {
                rootURL?.stopAccessingSecurityScopedResource()
                LogManager.shared.log("Stopped accessing security-scoped resource", type: .debug)
            }
            
            DispatchQueue.main.async {
                self.progress = nil
                LogManager.shared.log("GridManager: Finished loading all images", type: .info)
            }
        }
    }
    
    private func extractEmbeddedThumbnail(from path: String) -> NSImage? {
        LogManager.shared.log("Attempting to extract thumbnail from: \(path)", type: .debug)
        
        guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true
        ] as CFDictionary) else {
            LogManager.shared.log("Failed to create image source for: \(path)", type: .warning)
            return nil
        }
        
        // Create thumbnail with optimized options
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 800,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceShouldAllowFloat: false,
            kCGImageSourceSubsampleFactor: 4
        ]
        
        guard let thumbnailImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            LogManager.shared.log("Failed to create thumbnail", type: .warning)
            return nil
        }
        
        return autoreleasepool { () -> NSImage in
            let nsImage = NSImage(cgImage: thumbnailImage, size: NSSize.zero)
            LogManager.shared.log("Created thumbnail with size: \(nsImage.size)", type: .debug)
            return nsImage
        }
    }
    
    // Helper methods for image access
    private func cleanupCache() {
        imageCacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            // If cache size is under limit, no cleanup needed
            if self.imageCache.count <= self.maxCacheSize {
                return
            }
            
            // Sort by access time, oldest first
            let sortedItems = self.imageAccessTimes.sorted { $0.value < $1.value }
            
            // Remove oldest items until we're under the limit
            let itemsToRemove = self.imageCache.count - self.maxCacheSize
            for i in 0..<itemsToRemove {
                let itemId = sortedItems[i].key
                self.imageCache.removeValue(forKey: itemId)
                self.imageAccessTimes.removeValue(forKey: itemId)
            }
            
            LogManager.shared.log("Cleaned up \(itemsToRemove) items from image cache", type: .debug)
        }
    }
    
    func getImage(for itemId: Int) -> NSImage? {
        imageCacheQueue.sync {
            imageAccessTimes[itemId] = Date()
        }
        return imageCache[itemId]
    }
    
    private func setImage(for itemId: Int, image: NSImage?) {
        imageCacheQueue.sync {
            if let image = image {
                imageCache[itemId] = image
                imageAccessTimes[itemId] = Date()
                cleanupCache()
            } else {
                imageCache.removeValue(forKey: itemId)
                imageAccessTimes.removeValue(forKey: itemId)
            }
        }
    }
    
    // Add a method to clear the cache when switching works
    func clearCache() {
        imageCacheQueue.sync {
            imageCache.removeAll()
            imageAccessTimes.removeAll()
            LogManager.shared.log("Cleared image cache", type: .debug)
        }
    }
    
    func updateOrder(fromIndex: Int, toIndex: Int) {
        guard fromIndex != toIndex,
              fromIndex >= 0, fromIndex < items.count,
              toIndex >= 0, toIndex < items.count else { return }
        
        // Update local order immediately
        let item = items.remove(at: fromIndex)
        items.insert(item, at: toIndex)
        
        // Calculate new order values but don't update items yet
        var updatedItems: [(index: Int, item: GridItem)] = []
        for (index, item) in items.enumerated() {
            let newOrder = items.count - index // Reverse the order to match DESC in SQL
            if item.order != newOrder {
                let newItem = GridItem(
                    id: item.id,
                    originalPath: item.originalPath,
                    cachePath: item.cachePath,
                    order: newOrder
                )
                updatedItems.append((index, newItem))
            }
        }
        
        // Batch update database
        Task {
            for (index, newItem) in updatedItems {
                do {
                    let itemId = newItem.id
                    let newOrder = newItem.order
                    if try await DatabaseManager.shared.updateFileOrder(fileId: itemId, newOrder: newOrder) {
                        DispatchQueue.main.async { [weak self] in
                            self?.items[index] = newItem
                        }
                    }
                } catch {
                    LogManager.shared.log("Failed to update order for item \(newItem.id): \(error)", type: .error)
                }
            }
        }
        
        // Notify UI of the initial reorder
        objectWillChange.send()
    }
    
    private var cacheDirPath: String? {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(cacheFolderName)
            .path
    }
    
    private func getCacheDirectoryPath() -> String? {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(cacheFolderName)
            .path
    }
    
    func deleteCache() {
        guard let cachePath = getCacheDirectoryPath() else {
            LogManager.shared.log("Cache directory path is nil", type: .error)
            return
        }
        
        do {
            if fileManager.fileExists(atPath: cachePath) {
                try fileManager.removeItem(atPath: cachePath)
                LogManager.shared.log("Successfully deleted cache directory", type: .info)
                // Clear the in-memory cache
                imageCache.removeAll()
                // Recreate the cache directory
                setupCacheDirectory()
            } else {
                LogManager.shared.log("Cache directory doesn't exist", type: .info)
            }
        } catch {
            LogManager.shared.log("Error deleting cache: \(error)", type: .error)
        }
    }
}
