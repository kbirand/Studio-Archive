import SwiftUI
import AppKit
import Quartz

// Add this class near the top of the file
class PreviewItem: NSObject, QLPreviewItem {
    let url: URL
    
    init(url: URL) {
        self.url = url
        super.init()
    }
    
    var previewItemURL: URL? {
        return url
    }
    
    var previewItemTitle: String? {
        return url.lastPathComponent
    }
}

struct ImageCollectionView: NSViewRepresentable {
    @ObservedObject var gridManager: GridManager
    @StateObject private var contextManager = ContextManager.shared
    let onSelectionChanged: (Set<Int>) -> Void
    
    // MARK: - KeyHandlingCollectionView
    private class KeyHandlingCollectionView: NSCollectionView {
        override func keyDown(with event: NSEvent) {
            if let delegate = delegate as? ImageCollectionView.Coordinator {
                if !delegate.collectionView(self, keyDown: event) {
                    super.keyDown(with: event)
                }
            } else {
                super.keyDown(with: event)
            }
        }
        
        override var acceptsFirstResponder: Bool { true }
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let collectionView = KeyHandlingCollectionView()
        
        // Configure collection view
        collectionView.collectionViewLayout = createGridLayout()
        collectionView.delegate = context.coordinator
        collectionView.dataSource = context.coordinator
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        
        // Register cell class
        collectionView.register(ImageCollectionViewItem.self, 
                              forItemWithIdentifier: NSUserInterfaceItemIdentifier("ImageCell"))
        
        // Enable drag and drop
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        collectionView.registerForDraggedTypes([.fileURL, .string])
        
        // Configure scroll view
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let collectionView = scrollView.documentView as? NSCollectionView else { 
            LogManager.shared.log("Collection view not found", type: .warning)
            return 
        }
        
        // Only update layout if the grid size has changed
        if context.coordinator.lastGridSize != gridManager.gridItemSize {
            context.coordinator.lastGridSize = gridManager.gridItemSize
            DispatchQueue.main.async {
                collectionView.collectionViewLayout = self.createGridLayout()
            }
        }
        
        // Reload data when items change
        if context.coordinator.lastItemCount != gridManager.items.count {
            context.coordinator.lastItemCount = gridManager.items.count
            
            DispatchQueue.main.async {
                // Save scroll position
                let savedContentOffset = scrollView.contentView.bounds.origin
                
                collectionView.reloadData()
                
                // Restore scroll position
                scrollView.contentView.scroll(savedContentOffset)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        } else {
            // Only reload visible items if count hasn't changed
            collectionView.visibleItems().forEach { item in
                if let indexPath = collectionView.indexPath(for: item),
                   let imageItem = item as? ImageCollectionViewItem {
                    let gridItem = gridManager.items[indexPath.item]
                    imageItem.configure(with: gridItem)
                }
            }
        }
    }
    
    private func createGridLayout() -> NSCollectionViewFlowLayout {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: gridManager.gridItemSize, height: gridManager.gridItemSize)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.scrollDirection = .vertical
        return layout
    }
    
    class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        var parent: ImageCollectionView
        var lastItemCount: Int = 0
        var lastGridSize: CGFloat = 0
        private var quickLookIndex: Int = -1
        private var selectedItem: GridManager.GridItem?
        private var previewItem: PreviewItem?
        
        init(_ parent: ImageCollectionView) {
            self.parent = parent
            super.init()
        }
        
        // MARK: - Selection Handling
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            let indexes = indexPaths.map { $0.item }
            parent.onSelectionChanged(Set(indexes))
            if let firstIndex = indexes.first,
               firstIndex < parent.gridManager.items.count {
                selectedItem = parent.gridManager.items[firstIndex]
                quickLookIndex = firstIndex
                // Clear cached preview item when selection changes
                previewItem = nil
            }
        }
        
        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            let indexes = indexPaths.map { $0.item }
            parent.onSelectionChanged(Set(indexes))
            if indexes.contains(quickLookIndex) {
                selectedItem = nil
                quickLookIndex = -1
                previewItem = nil
            }
        }
        
        // MARK: - QuickLook Panel Support
        
        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
            return parent.gridManager.items.count
        }
        
        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            let item = parent.gridManager.items[index]
            let fullPath = item.originalPath
            
            guard FileManager.default.fileExists(atPath: fullPath),
                  FileManager.default.isReadableFile(atPath: fullPath) else {
                return nil
            }
            
            return URL(fileURLWithPath: fullPath) as QLPreviewItem
        }
        
        // Handle arrow key navigation
        func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
            switch event.keyCode {
            case 123, 124: // Left and Right arrow keys
                return true // Let QuickLook handle navigation
            default:
                return false
            }
        }
        
        // Update selection when QuickLook changes item
        func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor item: QLPreviewItem!, contentRect: UnsafeMutablePointer<NSRect>!) -> Any! {
            // Update collection view selection to match QuickLook
            if let collectionView = panel.windowController?.window?.firstResponder as? NSCollectionView {
                collectionView.deselectAll(nil)
                collectionView.selectItems(at: [IndexPath(item: panel.currentPreviewItemIndex, section: 0)], scrollPosition: .centeredVertically)
            }
            return nil
        }
        
        func collectionView(_ collectionView: NSCollectionView, keyDown event: NSEvent) -> Bool {
            if event.keyCode == 49 { // Spacebar
                if let selectedIndex = collectionView.selectionIndexes.first {
                    quickLookIndex = selectedIndex
                    if let panel = QLPreviewPanel.shared() {
                        if panel.isVisible {
                            panel.orderOut(nil)
                        } else {
                            panel.dataSource = self
                            panel.delegate = self
                            panel.currentPreviewItemIndex = selectedIndex
                            panel.makeKeyAndOrderFront(nil)
                        }
                        return true
                    }
                }
            }
            return false
        }
        
        // MARK: - Collection View Delegate
        
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            let count = parent.gridManager.items.count
            LogManager.shared.log("CollectionView: Number of items = \(count)", type: .debug)
            return count
        }
        
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            LogManager.shared.log("CollectionView: Creating item at index \(indexPath.item)", type: .debug)
            let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("ImageCell"),
                                             for: indexPath) as! ImageCollectionViewItem
            let gridItem = parent.gridManager.items[indexPath.item]
            item.configure(with: gridItem)
            return item
        }
        
        // Drag and Drop support
        func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
            return true
        }
        
        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            let gridItem = parent.gridManager.items[indexPath.item]
            
            // Create a pasteboard item that can contain multiple representations
            let pasteboardItem = NSPasteboardItem()
            
            // Add the index for internal reordering
            pasteboardItem.setString(String(indexPath.item), forType: .string)
            
            // Add the file URL for Finder operations
            let fileURL = URL(fileURLWithPath: gridItem.originalPath)
            
            pasteboardItem.setString(fileURL.absoluteString, forType: .fileURL)
            
            return pasteboardItem
        }
        
        func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            // If dragging to Finder or external target
            if let source = draggingInfo.draggingSource as? NSCollectionView,
               source === collectionView {
                // For internal reordering
                proposedDropOperation.pointee = .on
                return .move
            }
            
            // For external drags (like to Finder)
            return .copy
        }
        
        func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
            LogManager.shared.log("Accepting drop at index \(indexPath.item)", type: .debug)
            
            // Check if this is an internal move
            if let draggedItem = draggingInfo.draggingPasteboard.string(forType: .string),
               let fromIndex = Int(draggedItem) {
                let toIndex = indexPath.item
                parent.gridManager.updateOrder(fromIndex: fromIndex, toIndex: toIndex)
                
                // Animate the reordering
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    context.allowsImplicitAnimation = true
                    collectionView.animator().performBatchUpdates({
                        collectionView.moveItem(at: IndexPath(item: fromIndex, section: 0),
                                             to: IndexPath(item: toIndex, section: 0))
                    }, completionHandler: nil)
                }
                return true
            }
            
            return false
        }
    }
}

// Wrapper view to include the delete confirmation dialog
struct ImageCollectionViewWithDialog: View {
    @ObservedObject var gridManager: GridManager
    let onSelectionChanged: (Set<Int>) -> Void
    
    var body: some View {
        ZStack {
            ImageCollectionView(gridManager: gridManager, onSelectionChanged: onSelectionChanged)
            DeleteConfirmationDialog()
        }
    }
}

class ImageCollectionViewItem: NSCollectionViewItem, NSMenuDelegate {
    fileprivate var containerView: NSView?
    fileprivate var imageLayer: CALayer?
    private var progressIndicator: NSProgressIndicator?
    private var gridItem: GridManager.GridItem?
    
    override func loadView() {
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 8  // Add corner radius
        containerView.layer?.masksToBounds = true  // Ensure corners are clipped
        self.containerView = containerView
        self.view = containerView
        
        // Add menu
        let menu = NSMenu()
        menu.delegate = self
        containerView.menu = menu
        
        setupImageLayer()
    }
    
    func configure(with item: GridManager.GridItem) {
        self.gridItem = item
        setImage(GridManager.shared.getImage(for: item.id))
    }
    
    private func setupImageLayer() {
        // Create progress indicator
        let progress = NSProgressIndicator(frame: .zero)
        progress.style = .spinning
        progress.controlSize = .regular
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        containerView?.addSubview(progress)
        
        // Create image layer
        let layer = CALayer()
        layer.masksToBounds = true
        layer.cornerRadius = 8  // Match container corner radius
        layer.contentsGravity = .resizeAspectFill  // Use aspect fill
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 1.0
        containerView?.layer?.addSublayer(layer)
        
        imageLayer = layer
        progressIndicator = progress
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        imageLayer?.frame = view.bounds
        
        // Center the progress indicator
        if let progress = progressIndicator {
            let progressSize: CGFloat = 32
            progress.frame = NSRect(
                x: (view.bounds.width - progressSize) / 2,
                y: (view.bounds.height - progressSize) / 2,
                width: progressSize,
                height: progressSize
            )
        }
    }
    
    override var isSelected: Bool {
        didSet {
            if isSelected {
                containerView?.layer?.borderWidth = 3
                containerView?.layer?.borderColor = NSColor.controlAccentColor.cgColor
                // Add a subtle shadow when selected
                containerView?.layer?.shadowColor = NSColor.controlAccentColor.cgColor
                containerView?.layer?.shadowOpacity = 0.3
                containerView?.layer?.shadowOffset = .zero
                containerView?.layer?.shadowRadius = 4
            } else {
                containerView?.layer?.borderWidth = 0
                containerView?.layer?.borderColor = nil
                containerView?.layer?.shadowOpacity = 0
            }
        }
    }
    
    func setImage(_ image: NSImage?) {
        if let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            imageLayer?.contents = cgImage
            imageLayer?.contentsGravity = .resizeAspectFill
            progressIndicator?.isHidden = true
        } else {
            imageLayer?.contents = nil
            progressIndicator?.isHidden = false
        }
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        if gridItem == nil { return }
        
        // Copy File
        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyFile), keyEquivalent: "")
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        menu.addItem(copyItem)
        
        // Show in Finder
        let finderItem = NSMenuItem(title: "Show in Finder", action: #selector(openInFinder), keyEquivalent: "")
        finderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(finderItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Delete
        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteFile), keyEquivalent: "")
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(deleteItem)
    }
    
    @objc private func copyFile() {
        guard let gridItem = gridItem else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // Create URL from the original path
        let fileURL = URL(fileURLWithPath: gridItem.originalPath)
        
        // Add both the file URL and the file promise to the pasteboard
        pasteboard.writeObjects([fileURL as NSPasteboardWriting])
        
        LogManager.shared.log("Copied file to pasteboard: \(gridItem.originalPath)", type: .debug)
    }
    
    @objc private func deleteFile() {
        guard let gridItem = gridItem else { return }
        
        let alert = NSAlert()
        alert.messageText = "Delete Item"
        alert.informativeText = "Are you sure you want to delete this item? This will remove it from the database but won't affect the original file."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Delete from database and refresh the view
            let success = DatabaseManager.shared.deleteFile(id: gridItem.id)
            if success {
                // Notify GridManager to refresh
                GridManager.shared.removeItem(id: gridItem.id)
                
                // Delete cache file if it exists
                if let cachePath = gridItem.cachePath {
                    do {
                        try FileManager.default.removeItem(atPath: cachePath)
                        LogManager.shared.log("Deleted cache file: \(cachePath)", type: .debug)
                    } catch {
                        LogManager.shared.log("Failed to delete cache file: \(error.localizedDescription)", type: .error)
                    }
                }
            } else {
                LogManager.shared.log("Failed to delete item from database", type: .error)
            }
        }
    }
    
    @objc private func copyPath() {
        // Removed
    }
    
    @objc private func openInFinder() {
        guard let gridItem = gridItem else { return }
        ContextManager.shared.openInFinder(path: gridItem.originalPath)
    }
}
