//
//  Studio_ArchiveApp.swift
//  Studio Archive
//
//  Created by Koray Birand on 11.02.2025.
//

import SwiftUI

@main
struct Studio_ArchiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var aboutWindowState = AboutWindowState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 600)
        .commands {
            // Hide the sidebar command
            CommandGroup(replacing: .sidebar) { }
            
            CommandGroup(replacing: .appSettings) {
                Button("Preferences...") {
                    NotificationCenter.default.post(name: Notification.Name("ShowPreferences"), object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Studio Archive") {
                    aboutWindowState.showAboutWindow()
                }
            }
        }
    }
}

class AboutWindowState: ObservableObject {
    private var aboutWindowController: AboutWindowController?
    
    func showAboutWindow() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }
        aboutWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
