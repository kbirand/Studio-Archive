import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 128, height: 128)
            }
            
            Text("Copyright 2025 Art&Ist - Koray Birand")
                .font(.system(size: 13))
            Text("info@koraybirand.com")
                .font(.system(size: 10))
        }
        .padding(40)
        .frame(width: 350, height: 250)
    }
}

class AboutWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Studio Archive"
        window.center()
        
        let hostingView = NSHostingView(rootView: AboutView())
        window.contentView = hostingView
        
        self.init(window: window)
    }
}

#Preview {
    AboutView()
}
