import SwiftUI

class ImportProgress: ObservableObject {
    static let shared = ImportProgress()
    
    @Published var isShowing = false
    @Published var currentFile = ""
    @Published var progress: Double = 0
    @Published var totalFiles = 0
    @Published var currentFileNumber = 0
    
    private init() {}
    
    func show(totalFiles: Int) {
        self.totalFiles = totalFiles
        self.currentFileNumber = 0
        self.progress = 0
        self.currentFile = ""
        self.isShowing = true
    }
    
    func updateProgress(fileName: String, fileNumber: Int) {
        self.currentFile = fileName
        self.currentFileNumber = fileNumber
        self.progress = Double(fileNumber) / Double(totalFiles)
    }
    
    func hide() {
        self.isShowing = false
    }
}

struct ImportProgressView: View {
    @ObservedObject private var progress = ImportProgress.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Importing Photos")
                .font(.headline)
            
            ProgressView(value: progress.progress) {
                Text("\(progress.currentFileNumber) of \(progress.totalFiles)")
                    .font(.system(size: 12))
            }
            .frame(width: 300)
            
            Text(progress.currentFile)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 280)
                .font(.system(size: 12))
            
            Text("\(Int(progress.progress * 100))%")
                .font(.system(size: 14, weight: .bold))
        }
        .padding(20)
        .frame(width: 340)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

class ImportProgressWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Import Progress"
        window.center()
        window.contentView = NSHostingView(rootView: ImportProgressView())
        window.isReleasedWhenClosed = false
        window.level = .floating  // Make window float above others
        window.backgroundColor = NSColor.windowBackgroundColor
        
        self.init(window: window)
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
