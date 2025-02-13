import Foundation
import AppKit
import SwiftUI
import ImageIO

class GridManager: ObservableObject, @unchecked Sendable {
    static let shared = GridManager()
    
    @Published var selectedItemIndexes: Set<Int> = []
    @Published var gridItemSize: CGFloat = UserDefaults.standard.float(forKey: "GridItemSize") == 0 ? 200 : CGFloat(UserDefaults.standard.float(forKey: "GridItemSize"))
    @Published private(set) var progress: (current: Int, total: Int)?
    @Published var showFilenames: Bool = UserDefaults.standard.bool(forKey: "ShowFilenames")
    
    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private let cacheFolderName = "ImageCache"
    private let cacheDirPathKey = "ImageCachePath"
    private let maxThumbnailSize: CGFloat = 512  // Maximum dimension for cached thumbnails
    private var imageCache: [Int: NSImage] = [:]  // Separate image cache
    private var imageCacheQueue = DispatchQueue(label: "com.studiarchive.imagecache")
    private var imageAccessTimes: [Int: Date] = [:] // Track when each image was last accessed
    
    // Default to 500 items or user preference
    private var maxCacheSize: Int {
        let size = defaults.integer(forKey: "MaxCacheSize")
        return size > 0 ? size : 500
    }
    
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
        var visible: Bool  // Add visible property
        
        static func == (lhs: GridItem, rhs: GridItem) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    @Published var items: [GridItem] = []
    
    // Filtered items based on visibility setting
    var filteredItems: [GridItem] {
        let hideInvisible = defaults.bool(forKey: "HideInvisibleWorks")
        return hideInvisible ? items.filter { $0.visible } : items
    }
    
    private struct BatchResult: Sendable {
        let id: Int
        let imageData: Data?
    }
    
    init() {
        // Initialize with stored grid size or default
        if defaults.float(forKey: "GridItemSize") == 0 {
            defaults.set(Float(200), forKey: "GridItemSize")
        }
        
        // Initialize max cache size if not set
        if defaults.integer(forKey: "MaxCacheSize") == 0 {
            defaults.set(500, forKey: "MaxCacheSize")
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
    
    func updateShowFilenames(_ show: Bool) {
        showFilenames = show
        defaults.set(show, forKey: "ShowFilenames")
    }
    
    func loadImages(forWorkPath workPath: String, files: [(id: Int, path: String, order: Int, visible: Bool)]) {
        // Clear existing items and cache
        items.removeAll()
        imageCacheQueue.async { [weak self] in
            self?.imageCache.removeAll()
            self?.imageAccessTimes.removeAll()
        }
        
        guard let rootPath = defaults.string(forKey: "RootFolderPath") else {
            LogManager.shared.log("GridManager: Root path not found in UserDefaults", type: .warning)
            return
        }
        
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
                order: file.2,
                visible: file.3 // Use the visibility from database
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
                                            
                                            // Save to cache asynchronously while we use the data directly
                                            Task {
                                                try? jpegData.write(to: URL(fileURLWithPath: cachePath))
                                            }
                                            
                                            imageData = jpegData
                                            LogManager.shared.log("Successfully created thumbnail", type: .debug)
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
                                self.setImageInCache(id: result.id, image: image)
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
    
    // Add method to update cache size
    func updateMaxCacheSize(_ size: Int) {
        defaults.set(size, forKey: "MaxCacheSize")
        // If reducing cache size, trim cache to new size
        if size < imageCache.count {
            trimCache()
        }
    }
    
    // Add method to trim cache when it exceeds the limit
    private func trimCache() {
        imageCacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.imageCache.count > self.maxCacheSize {
                // Sort by access time, oldest first
                let sortedItems = self.imageAccessTimes.sorted { $0.value < $1.value }
                
                // Calculate how many items to remove
                let itemsToRemove = self.imageCache.count - self.maxCacheSize
                
                // Remove oldest items
                for i in 0..<itemsToRemove {
                    let itemId = sortedItems[i].key
                    self.imageCache.removeValue(forKey: itemId)
                    self.imageAccessTimes.removeValue(forKey: itemId)
                }
                
                LogManager.shared.log("Trimmed \(itemsToRemove) items from image cache", type: .debug)
            }
        }
    }
    
    func getImage(for id: Int) -> NSImage? {
        var image: NSImage?
        
        imageCacheQueue.sync {
            image = imageCache[id]
            if image != nil {
                // Update access time
                imageAccessTimes[id] = Date()
            }
        }
        
        return image
    }
    
    // Update cache setting method
    func setImageInCache(id: Int, image: NSImage) {
        // Get image data outside the async context
        guard let imageData = image.tiffRepresentation else { return }
        
        // Pass only the Data (which is Sendable) through the async boundary
        imageCacheQueue.async { [weak self, imageData] in
            guard let self = self,
                  let imageCopy = NSImage(data: imageData) else { return }
            
            self.imageCache[id] = imageCopy
            self.imageAccessTimes[id] = Date()
            
            // Trim cache if needed
            if self.imageCache.count > self.maxCacheSize {
                self.trimCache()
            }
        }
    }
    
    // Add method to clear specific items from cache
    func clearCacheForItems(_ ids: Set<Int>) {
        imageCacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            for id in ids {
                self.imageCache.removeValue(forKey: id)
                self.imageAccessTimes.removeValue(forKey: id)
            }
        }
    }
    
    // Add method to clear the cache
    func clearCache() {
        guard let cachePath = getCacheDirectoryPath() else {
            LogManager.shared.log("Cache directory path is nil", type: .error)
            return
        }
        
        do {
            if fileManager.fileExists(atPath: cachePath) {
                try fileManager.removeItem(atPath: cachePath)
                try fileManager.createDirectory(atPath: cachePath, withIntermediateDirectories: true)
                LogManager.shared.log("Cache cleared successfully", type: .info)
            }
            
            // Clear memory cache
            imageCacheQueue.async { [weak self] in
                self?.imageCache.removeAll()
                self?.imageAccessTimes.removeAll()
            }
            
            // Notify observers
            objectWillChange.send()
        } catch {
            LogManager.shared.log("Failed to clear cache: \(error)", type: .error)
        }
    }
    
    private func getCacheDirectoryPath() -> String? {
        // Try to get custom path from UserDefaults
        if let customPath = defaults.string(forKey: cacheDirPathKey),
           fileManager.fileExists(atPath: customPath) {
            return customPath
        }
        
        // Use/create default path under Documents
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(cacheFolderName)
            .path
    }
    
    func getCurrentCachePath() -> String {
        return getCacheDirectoryPath() ?? ""
    }
    
    func setCacheDirPath(_ path: String) {
        do {
            // Create directory if it doesn't exist
            if !fileManager.fileExists(atPath: path) {
                try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
                LogManager.shared.log("Created new cache directory at: \(path)", type: .info)
            }
            
            // Save new path
            defaults.set(path, forKey: cacheDirPathKey)
            LogManager.shared.log("Updated cache directory to: \(path)", type: .info)
            
            // Notify observers
            objectWillChange.send()
        } catch {
            LogManager.shared.log("Failed to set cache directory: \(error)", type: .error)
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
    
    func removeItem(id: Int) {
        items.removeAll { $0.id == id }
        objectWillChange.send()
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
                    order: newOrder,
                    visible: item.visible
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
    
    func updateOrderMultiple(moves: [(from: Int, to: Int)]) {
        LogManager.shared.log("updateOrderMultiple: Starting with moves: \(moves)", type: .debug)
        
        // Validate moves and check for duplicates
        var seenFromIndices = Set<Int>()
        var seenToIndices = Set<Int>()
        
        for move in moves {
            if seenFromIndices.contains(move.from) {
                LogManager.shared.log("updateOrderMultiple: Duplicate from index: \(move.from)", type: .error)
                return
            }
            if seenToIndices.contains(move.to) {
                LogManager.shared.log("updateOrderMultiple: Duplicate to index: \(move.to)", type: .error)
                return
            }
            seenFromIndices.insert(move.from)
            seenToIndices.insert(move.to)
        }
        
        // Create a copy of the items array
        var newItems = items
        
        // First remove all items that are being moved (from highest index to lowest)
        var movingItems: [GridItem] = []
        let sortedMoves = moves.sorted { $0.from > $1.from }
        
        for move in sortedMoves {
            guard move.from < newItems.count else {
                LogManager.shared.log("updateOrderMultiple: Index out of range during removal: \(move.from)", type: .error)
                return
            }
            movingItems.append(newItems.remove(at: move.from))
        }
        
        // Then insert them at their new positions (from lowest to highest)
        // Reverse both arrays to maintain the original relative order of items
        movingItems.reverse()
        for (item, move) in zip(movingItems, moves.sorted { $0.to < $1.to }) {
            let targetIndex = min(move.to, newItems.count)
            newItems.insert(item, at: targetIndex)
        }
        
        // Verify the new array has the correct count
        guard newItems.count == items.count else {
            LogManager.shared.log("updateOrderMultiple: Item count mismatch after reordering. Expected: \(items.count), Got: \(newItems.count)", type: .error)
            return
        }
        
        // Update the items array
        items = newItems
        
        // Update database order
        var updatedItems: [(Int, GridItem)] = []
        for (index, item) in items.enumerated() {
            let newOrder = items.count - index // Reverse the order to match DESC in SQL
            if item.order != newOrder {
                let newItem = GridItem(
                    id: item.id,
                    originalPath: item.originalPath,
                    cachePath: item.cachePath,
                    order: newOrder,
                    visible: item.visible
                )
                updatedItems.append((index, newItem))
            }
        }
        
        LogManager.shared.log("updateOrderMultiple: Updating \(updatedItems.count) items in database", type: .debug)
        
        // Batch update database
        Task {
            for (index, newItem) in updatedItems {
                do {
                    let itemId = newItem.id
                    let newOrder = newItem.order
                    if try await DatabaseManager.shared.updateFileOrder(fileId: itemId, newOrder: newOrder) {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            guard index < self.items.count else {
                                LogManager.shared.log("updateOrderMultiple: Index out of range during database update: \(index)", type: .error)
                                return
                            }
                            self.items[index] = newItem
                        }
                    }
                } catch {
                    LogManager.shared.log("Failed to update order for item \(newItem.id): \(error)", type: .error)
                }
            }
        }
        
        // Notify UI of the reorder
        objectWillChange.send()
    }
    
    func resetItemsOrder() {
        // Sort items by filename
        let sortedItems = items.sorted { item1, item2 in
            let filename1 = (item1.originalPath as NSString).lastPathComponent
            let filename2 = (item2.originalPath as NSString).lastPathComponent
            return filename1.localizedStandardCompare(filename2) == .orderedAscending
        }
        
        // Update order in database and memory
        for (index, item) in sortedItems.enumerated() {
            if DatabaseManager.shared.updateOrder(id: item.id, order: sortedItems.count - index) {
                if let itemIndex = items.firstIndex(where: { $0.id == item.id }) {
                    items[itemIndex].order = sortedItems.count - index
                }
            } else {
                LogManager.shared.log("Failed to update order for item \(item.id)", type: .error)
            }
        }
        
        // Resort items array
        items.sort { $0.order > $1.order }
        
        // Notify observers
        objectWillChange.send()
        LogManager.shared.log("Reset items order by filename", type: .debug)
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
    
    func toggleVisibility(for itemId: Int) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            let item = items[index]
            let newVisibility = !item.visible
            
            // Update database using DatabaseManager
            if DatabaseManager.shared.updateFileVisibility(fileId: itemId, visible: newVisibility) {
                DispatchQueue.main.async {
                    // Update the item in our array
                    self.items[index].visible = newVisibility
                    
                    // Post notification for any observers that need to refresh
                    NotificationCenter.default.post(name: Notification.Name("VisibilitySettingsChanged"), object: nil)
                }
            }
        }
    }
}
