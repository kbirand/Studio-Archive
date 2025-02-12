import SwiftUI
import AppKit

struct ImageCollectionView: NSViewRepresentable {
    @ObservedObject var gridManager: GridManager
    let onSelectionChanged: (Set<Int>) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let collectionView = NSCollectionView()
        
        // Configure collection view
        collectionView.collectionViewLayout = createGridLayout()
        collectionView.delegate = context.coordinator
        collectionView.dataSource = context.coordinator
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]  // Make background transparent
        
        // Register cell class
        collectionView.register(ImageCollectionViewItem.self, 
                              forItemWithIdentifier: NSUserInterfaceItemIdentifier("ImageCell"))
        
        // Enable drag and drop
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: false) // Allow copy to Finder
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        collectionView.registerForDraggedTypes([.fileURL])
        
        // Configure scroll view
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false  // Make scroll view background transparent
        
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
                    imageItem.setImage(gridManager.getImage(for: gridItem.id))
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
    
    class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {
        var parent: ImageCollectionView
        var lastItemCount: Int = 0
        var lastGridSize: CGFloat = 0
        
        init(_ parent: ImageCollectionView) {
            self.parent = parent
        }
        
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
            LogManager.shared.log("Loading image for id: \(gridItem.id)", type: .debug)
            item.setImage(parent.gridManager.getImage(for: gridItem.id))
            return item
        }
        
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            updateSelection(collectionView)
        }
        
        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            updateSelection(collectionView)
        }
        
        private func updateSelection(_ collectionView: NSCollectionView) {
            let selectedIndexes = collectionView.selectionIndexPaths.map { $0.item }
            parent.onSelectionChanged(Set(selectedIndexes))
        }
        
        // Drag and Drop support
        func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
            return true
        }
        
        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            LogManager.shared.log("Attempting to create pasteboard writer for item at index \(indexPath.item)", type: .debug)
            let gridItem = parent.gridManager.items[indexPath.item]
            let originalPath = gridItem.originalPath
            let fileURL = URL(fileURLWithPath: originalPath)
            LogManager.shared.log("Created file URL for drag: \(fileURL)", type: .debug)
            return fileURL as NSURL
        }
        
        func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            proposedDropOperation.pointee = .on
            return .move
        }
        
        func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
            LogManager.shared.log("Accepting drop at index \(indexPath.item)", type: .debug)
            guard let draggedItem = draggingInfo.draggingPasteboard.string(forType: .string),
                  let fromIndex = Int(draggedItem) else {
                LogManager.shared.log("Failed to get dragged item", type: .warning)
                return false
            }
            
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
    }
}

class ImageCollectionViewItem: NSCollectionViewItem {
    private var containerView: NSView?
    private var imageLayer: CALayer?
    private var progressIndicator: NSProgressIndicator?
    
    override func loadView() {
        // Create container view with rounded corners
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        // Remove background color to make it transparent
        
        // Create progress indicator
        let progress = NSProgressIndicator(frame: .zero)
        progress.style = .spinning
        progress.controlSize = .regular
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        container.addSubview(progress)
        
        // Create image layer
        let layer = CALayer()
        layer.masksToBounds = true
        layer.contentsGravity = .resizeAspectFill  // Use aspect fill
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 1.0
        container.layer?.addSublayer(layer)
        
        containerView = container
        imageLayer = layer
        progressIndicator = progress
        self.view = container
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
            containerView?.layer?.borderWidth = isSelected ? 2 : 0
            containerView?.layer?.borderColor = isSelected ? NSColor.selectedControlColor.cgColor : nil
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
}
