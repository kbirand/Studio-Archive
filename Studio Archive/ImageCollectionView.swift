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
        let coordinator = Coordinator(self)
        NotificationCenter.default.addObserver(forName: Notification.Name("VisibilitySettingsChanged"), object: nil, queue: .main) { [weak coordinator] _ in
            guard let coordinator = coordinator else { return }
            coordinator.parent.gridManager.objectWillChange.send()
            if let scrollView = coordinator.scrollView,
               let collectionView = scrollView.documentView as? NSCollectionView {
                collectionView.reloadData()
            }
        }
        return coordinator
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
        
        context.coordinator.scrollView = scrollView
        
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
        if context.coordinator.lastItemCount != gridManager.filteredItems.count {
            context.coordinator.lastItemCount = gridManager.filteredItems.count
            
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
                    let gridItem = gridManager.filteredItems[indexPath.item]
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
        weak var scrollView: NSScrollView?
        private var lastValidatedIndices: [Int] = []
        private var lastValidatedIndex: Int = -1
        
        init(_ parent: ImageCollectionView) {
            self.parent = parent
            super.init()
        }
        
        // MARK: - Selection Handling
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            let indexes = indexPaths.map { $0.item }
            parent.onSelectionChanged(Set(indexes))
            if let firstIndex = indexes.first,
               firstIndex < parent.gridManager.filteredItems.count {
                selectedItem = parent.gridManager.filteredItems[firstIndex]
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
            return parent.gridManager.filteredItems.count
        }
        
        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            let item = parent.gridManager.filteredItems[index]
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
            let count = parent.gridManager.filteredItems.count
            //LogManager.shared.log("CollectionView: Number of items = \(count)", type: .debug)
            return count
        }
        
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            //LogManager.shared.log("CollectionView: Creating item at index \(indexPath.item)", type: .debug)
            let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("ImageCell"),
                                             for: indexPath) as! ImageCollectionViewItem
            let gridItem = parent.gridManager.filteredItems[indexPath.item]
            item.configure(with: gridItem)
            return item
        }
        
        // Drag and Drop support
        func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
            return true
        }
        
        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            guard indexPath.item < parent.gridManager.filteredItems.count else {
                LogManager.shared.log("pasteboardWriter: Invalid index: \(indexPath.item)", type: .error)
                return nil
            }
            
            let gridItem = parent.gridManager.filteredItems[indexPath.item]
            
            // Create a pasteboard item that can contain multiple representations
            let pasteboardItem = NSPasteboardItem()
            
            // If we have multiple items selected, include all selected indices
            if collectionView.selectionIndexPaths.count > 1 && collectionView.selectionIndexPaths.contains(indexPath) {
                // Filter and validate selected indices, ensuring uniqueness
                let selectedIndices = Array(Set(collectionView.selectionIndexPaths
                    .map { $0.item }
                    .filter { $0 < parent.gridManager.filteredItems.count }))
                    .sorted()
                
                if selectedIndices.isEmpty {
                    LogManager.shared.log("pasteboardWriter: No valid selected indices", type: .error)
                    return nil
                }
                
                // Store the indices in the pasteboard
                let indicesString = selectedIndices.map(String.init).joined(separator: ",")
                LogManager.shared.log("pasteboardWriter: Multiple selection with indices: \(selectedIndices)", type: .debug)
                pasteboardItem.setString(indicesString, forType: .string)
            } else {
                // Single item drag
                pasteboardItem.setString(String(indexPath.item), forType: .string)
            }
            
            // Add the file URL for Finder operations
            let fileURL = URL(fileURLWithPath: gridItem.originalPath)
            
            // Add the file promise to the pasteboard
            pasteboardItem.setString(fileURL.absoluteString, forType: .fileURL)
            
            return pasteboardItem
        }
        
        func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            // Only process if this is an internal move
            guard draggingInfo.draggingSource as? NSCollectionView === collectionView,
                  let draggedString = draggingInfo.draggingPasteboard.string(forType: .string) else {
                return []
            }
            
            // Parse and deduplicate the dragged indices
            let draggedIndices = Array(Set(draggedString.split(separator: ",").compactMap { Int($0) })).sorted()
            
            guard !draggedIndices.isEmpty else {
                LogManager.shared.log("validateDrop: No valid indices found in pasteboard", type: .error)
                return []
            }
            
            // Get the proposed drop index
            let proposedIndex = proposedDropIndexPath.pointee.item
            
            // Validate that we're not dropping an item onto itself or in between selected items
            if draggedIndices.count == 1 {
                if draggedIndices[0] == proposedIndex {
                    return []
                }
            } else {
                // For multiple items, check if the drop target is within the range of selected items
                let minIndex = draggedIndices[0]
                let maxIndex = draggedIndices.last!
                
                if proposedIndex > minIndex && proposedIndex <= maxIndex {
                    // Trying to drop between selected items - not allowed
                    return []
                }
            }
            
            // Set the drop operation to before
            proposedDropOperation.pointee = .before
            
            // Log the validation less frequently
            if draggedIndices != lastValidatedIndices || proposedIndex != lastValidatedIndex {
                LogManager.shared.log("validateDrop: Valid drop at index \(proposedIndex) for indices \(draggedIndices)", type: .debug)
                lastValidatedIndices = draggedIndices
                lastValidatedIndex = proposedIndex
            }
            
            return .move
        }
        
        func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
            guard let draggedString = draggingInfo.draggingPasteboard.string(forType: .string) else {
                LogManager.shared.log("acceptDrop: No string data in pasteboard", type: .error)
                return false
            }
            
            // Parse and deduplicate the dragged indices
            let draggedIndices = Array(Set(draggedString.split(separator: ",").compactMap { Int($0) })).sorted()
            guard !draggedIndices.isEmpty else {
                LogManager.shared.log("acceptDrop: No valid indices found in pasteboard", type: .error)
                return false
            }
            
            let targetIndex = indexPath.item
            
            // Create move operations for each dragged index
            var moves: [(from: Int, to: Int)] = []
            
            // Calculate the target indices based on whether we're moving up or down
            let isMovingUp = targetIndex < draggedIndices[0]
            let adjustedTargetIndex = isMovingUp ? targetIndex : targetIndex - draggedIndices.count
            
            // Create moves for each dragged index
            for (offset, sourceIndex) in draggedIndices.enumerated() {
                let adjustedIndex = adjustedTargetIndex + offset
                moves.append((from: sourceIndex, to: adjustedIndex))
            }
            
            // Log the move operations
            LogManager.shared.log("acceptDrop: Moving items from \(draggedIndices) to positions starting at \(adjustedTargetIndex)", type: .debug)
            
            // Update the grid manager with the new order
            Task { @MainActor in
                parent.gridManager.updateOrderMultiple(moves: moves)
            }
            
            return true
        }
    }
}

// Wrapper view to include the delete confirmation dialog
struct ImageCollectionViewWithDialog: View {
    @ObservedObject var gridManager: GridManager
    let onSelectionChanged: (Set<Int>) -> Void
    @State private var showResetOrderAlert = false
    
    var body: some View {
        ZStack {
            VStack {
                ImageCollectionView(gridManager: gridManager, onSelectionChanged: onSelectionChanged)
                
                HStack {
                    Spacer()
                    Button(action: {
                        showResetOrderAlert = true
                    }) {
                        Label("Reset Order", systemImage: "arrow.clockwise")
                            .foregroundColor(.red.opacity(0.45))
                    }
                    .buttonStyle(.borderless)
                    .alert("Reset Items Order", isPresented: $showResetOrderAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Reset", role: .destructive) {
                            gridManager.resetItemsOrder()
                        }
                    } message: {
                        Text("This will reset the order of all items to be sorted by filename in ascending order. This action cannot be undone.")
                    }
                    .padding([.trailing, .bottom], 16)
                }
            }
            
            DeleteConfirmationDialog()
        }
    }
}



class ImageCollectionViewItem: NSCollectionViewItem, NSMenuDelegate {
    fileprivate var containerView: NSView?
    fileprivate var imageLayer: CALayer?
    private var progressIndicator: NSProgressIndicator?
    private var filenameLabel: NSTextField?
    private var filenameBgView: NSView?
    private var gridItem: GridManager.GridItem?
    private var visibilityCheckbox: NSButton?
    
    override func loadView() {
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 8
        containerView.layer?.masksToBounds = true
        self.containerView = containerView
        self.view = containerView
        
        // Add menu
        let menu = NSMenu()
        menu.delegate = self
        containerView.menu = menu
        
        setupImageLayer()
        setupFilenameLabel()
        setupVisibilityCheckbox()
    }
    
    private func setupFilenameLabel() {
        // Create background view for the label
        let backgroundView = NSView()
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.65).cgColor
        backgroundView.layer?.cornerRadius = 4
        containerView?.addSubview(backgroundView)
        filenameBgView = backgroundView
        
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.font = .systemFont(ofSize: 11)
        label.textColor = .white
        label.isHidden = !GridManager.shared.showFilenames
        backgroundView.addSubview(label)
        
        // Setup constraints for background view
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: containerView!.leadingAnchor, constant: 4),
            backgroundView.trailingAnchor.constraint(equalTo: containerView!.trailingAnchor, constant: -4),
            backgroundView.bottomAnchor.constraint(equalTo: containerView!.bottomAnchor, constant: -4)
        ])
        
        // Setup constraints for label
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -2)
        ])
        
        filenameLabel = label
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
    
    func configure(with item: GridManager.GridItem) {
        self.gridItem = item
        
        // Update visibility checkbox state
        visibilityCheckbox?.state = item.visible ? .on : .off
        let showCheckboxes = UserDefaults.standard.bool(forKey: "ShowVisibilityCheckboxes")
        visibilityCheckbox?.isEnabled = showCheckboxes
        visibilityCheckbox?.isHidden = !showCheckboxes
        
        // Configure filename label if showing filenames
        if GridManager.shared.showFilenames {
            filenameLabel?.stringValue = (item.originalPath as NSString).lastPathComponent
            filenameLabel?.isHidden = false
            filenameBgView?.isHidden = false
        } else {
            filenameLabel?.isHidden = true
            filenameBgView?.isHidden = true
        }
        
        setImage(GridManager.shared.getImage(for: item.id))
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
        
        // Get all selected items
        if let collectionView = self.view.superview as? NSCollectionView,
           collectionView.selectionIndexes.count > 1 {
            // Multiple items selected
            let alert = NSAlert()
            alert.messageText = "Delete Multiple Items"
            alert.informativeText = "Are you sure you want to delete \(collectionView.selectionIndexes.count) items? This will remove them from the database but won't affect the original files."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Get all selected items
                let selectedItems = collectionView.selectionIndexes.map { index in
                    GridManager.shared.items[index]
                }
                
                // Delete all selected items
                for item in selectedItems {
                    let success = DatabaseManager.shared.deleteFile(id: item.id)
                    if success {
                        // Delete cache file if it exists
                        if let cachePath = item.cachePath {
                            do {
                                try FileManager.default.removeItem(atPath: cachePath)
                                LogManager.shared.log("Deleted cache file: \(cachePath)", type: .debug)
                            } catch {
                                LogManager.shared.log("Failed to delete cache file: \(error.localizedDescription)", type: .error)
                            }
                        }
                        // Remove from GridManager
                        GridManager.shared.removeItem(id: item.id)
                    } else {
                        LogManager.shared.log("Failed to delete item from database: \(item.id)", type: .error)
                    }
                }
            }
        } else {
            // Single item delete
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
    }
    
    @objc private func copyPath() {
        // Removed
    }
    
    @objc private func openInFinder() {
        guard let gridItem = gridItem else { return }
        ContextManager.shared.openInFinder(path: gridItem.originalPath)
    }
    
    private func setupVisibilityCheckbox() {
        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleVisibility))
        checkbox.state = .off
        let showCheckboxes = UserDefaults.standard.bool(forKey: "ShowVisibilityCheckboxes")
        checkbox.isEnabled = showCheckboxes
        checkbox.isHidden = !showCheckboxes
        containerView?.addSubview(checkbox)
        
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            checkbox.topAnchor.constraint(equalTo: containerView!.topAnchor, constant: 8),
            checkbox.trailingAnchor.constraint(equalTo: containerView!.trailingAnchor, constant: -8),
            checkbox.widthAnchor.constraint(equalToConstant: 20),
            checkbox.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        visibilityCheckbox = checkbox
        
        // Listen for visibility settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVisibilitySettingsChanged),
            name: Notification.Name("VisibilitySettingsChanged"),
            object: nil
        )
    }
    
    @objc private func handleVisibilitySettingsChanged() {
        // Update checkbox enabled state based on UserDefaults
        visibilityCheckbox?.isEnabled = UserDefaults.standard.bool(forKey: "ShowVisibilityCheckboxes")
        // Update checkbox visibility
        visibilityCheckbox?.isHidden = !UserDefaults.standard.bool(forKey: "ShowVisibilityCheckboxes")
    }
    
    @objc private func toggleVisibility() {
        guard let gridItem = gridItem else { return }
        GridManager.shared.toggleVisibility(for: gridItem.id)
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
    
    @objc private func updateBackgroundColor() {
        // No longer needed since we're using fixed colors
    }
    
    deinit {
        // No longer need to remove observer since we're not using it anymore
    }
}
