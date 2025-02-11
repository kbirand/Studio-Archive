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
        
        // Register cell class
        collectionView.register(ImageCollectionViewItem.self, 
                              forItemWithIdentifier: NSUserInterfaceItemIdentifier("ImageCell"))
        
        // Enable drag and drop
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        collectionView.registerForDraggedTypes([.string])
        
        // Configure scroll view
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let collectionView = scrollView.documentView as? NSCollectionView else { return }
        
        // Update layout if grid size changed
        collectionView.collectionViewLayout = createGridLayout()
        
        // Reload data when items change
        if context.coordinator.lastItemCount != gridManager.items.count {
            // Save scroll position
            let savedContentOffset = scrollView.contentView.bounds.origin
            
            context.coordinator.lastItemCount = gridManager.items.count
            collectionView.reloadData()
            
            // Restore scroll position
            scrollView.contentView.scroll(savedContentOffset)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else {
            // Only reload visible items if count hasn't changed
            collectionView.visibleItems().forEach { item in
                if let indexPath = collectionView.indexPath(for: item),
                   let imageItem = item as? ImageCollectionViewItem {
                    let gridItem = gridManager.items[indexPath.item]
                    imageItem.setImage(gridItem.image)
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
        
        init(_ parent: ImageCollectionView) {
            self.parent = parent
        }
        
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            let count = parent.gridManager.items.count
            print("📊 CollectionView: Number of items = \(count)")
            return count
        }
        
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            print("🔄 CollectionView: Creating item at index \(indexPath.item)")
            let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("ImageCell"),
                                             for: indexPath) as! ImageCollectionViewItem
            let gridItem = parent.gridManager.items[indexPath.item]
            print("- Has image: \(gridItem.image != nil)")
            item.setImage(gridItem.image)
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
            return String(indexPath.item) as NSString
        }
        
        func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            proposedDropOperation.pointee = .on
            return .move
        }
        
        func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
            guard let draggedItem = draggingInfo.draggingPasteboard.string(forType: .string),
                  let fromIndex = Int(draggedItem) else {
                return false
            }
            
            let toIndex = indexPath.item
            parent.gridManager.updateOrder(fromIndex: fromIndex, toIndex: toIndex)
            collectionView.reloadData()
            
            return true
        }
    }
}

class ImageCollectionViewItem: NSCollectionViewItem {
    private var containerView: NSView?
    private var imageLayer: CALayer?
    
    override func loadView() {
        // Create container view with rounded corners
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        // Create image layer
        let layer = CALayer()
        layer.masksToBounds = true
        layer.contentsGravity = .resize
        print("Resize")
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 1.0
        container.layer?.addSublayer(layer)
        
        containerView = container
        imageLayer = layer
        self.view = container
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        imageLayer?.frame = view.bounds
    }
    
    override var isSelected: Bool {
        didSet {
            updateFocusRing()
        }
    }
    
    private func updateFocusRing() {
        containerView?.layer?.borderWidth = isSelected ? 3 : 0
        containerView?.layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : nil
    }
    
    func setImage(_ image: NSImage?) {
        if let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            imageLayer?.contents = cgImage
        } else {
            imageLayer?.contents = nil
        }
    }
}
