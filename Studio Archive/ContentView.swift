//
//  ContentView.swift
//  Studio Archive
//
//  Created by Koray Birand on 11.02.2025.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @StateObject private var databaseManager = DatabaseManager.shared
    @State private var works: [DatabaseManager.Work] = []
    @State private var showSettings = false
    @State private var showAddWork = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(alignment: .leading) {
                VStack {
                    HStack {
                        Spacer()
                        HStack {
                            Text("Works")
                                .font(.system(size: 38, weight: .light))
                            Button(action: {
                                showAddWork = true
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 30, weight: .light))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(width: 300)
                        .padding([.leading],-128)
                        Spacer()
                    }
                }
                HStack {
                    Spacer()
                    List(works) { work in
                        VStack(alignment: .leading) {
                            Text(work.workPeriod ?? "Unknown Work")
                                .font(.system(size: 16, weight: .light))
                        }
                    }
                    .frame(width: 300)
                    Spacer()
                }
            }
            .padding([.top,.bottom],50)
            .navigationSplitViewColumnWidth(min: 300, ideal: 300)
            .toolbar {
                ToolbarItem(id: "SidebarToggle", placement: .navigation, showsByDefault: false) {
                    EmptyView()
                }
            }
        } detail: {
            Text("Select a work")
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            columnVisibility = columnVisibility == .all ? .detailOnly : .all
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                    }
                }
        }
        .onAppear {
            if databaseManager.isDatabaseSelected {
                works = databaseManager.fetchWorks()
            } else {
                showSettings = true
            }
            
            // Listen for preferences notification
            NotificationCenter.default.addObserver(
                forName: Notification.Name("ShowPreferences"),
                object: nil,
                queue: .main
            ) { _ in
                showSettings = true
            }
            
            // Hide the sidebar button in the window toolbar
            if let window = NSApplication.shared.windows.first {
                window.toolbar?.items.forEach { item in
                    if item.itemIdentifier.rawValue == "com.apple.SwiftUI.navigationSplitView.toggleSidebar" {
                        item.view?.isHidden = true
                    }
                }
            }
        }
        .onChange(of: databaseManager.isDatabaseSelected) { isSelected in
            if isSelected {
                works = databaseManager.fetchWorks()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showAddWork) {
            AddWorkView {
                // Refresh works list after adding new work
                works = databaseManager.fetchWorks()
            }
        }
    }
}

#Preview {
    ContentView()
}
