//
//  ContentView.swift
//  Studio Archive
//
//  Created by Koray Birand on 11.02.2025.
//

import SwiftUI
import SQLite3
import UniformTypeIdentifiers
import Foundation
import AppKit

struct ContentView: View {
    @StateObject private var databaseManager = DatabaseManager.shared
    @StateObject private var detailsManager = DetailsManager.shared
    @State private var works: [DatabaseManager.Work] = []
    @State private var showSettings = false
    @State private var showAddWork = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var selectedWorkId: Int?
    @State private var searchText = ""
    @State private var showAddPhotosDialog = false
    @State private var showDeleteAlert = false
    @State private var showVisibilityCheckboxes = UserDefaults.standard.bool(forKey: "ShowVisibilityCheckboxes")
    @State private var hideInvisibleWorks = UserDefaults.standard.bool(forKey: "HideInvisibleWorks")
    
    // Editing states
    @State private var editedWorkPeriod: String = ""
    @State private var editedTalent: String = ""
    @State private var editedStylist: String = ""
    @State private var editedHair: String = ""
    @State private var editedMakeup: String = ""
    @State private var isEdited: Bool = false
    @State private var showUnsavedChangesAlert = false
    @State private var pendingWorkId: Int?
    @State private var currentEditingId: Int?
    
    // Original values for comparison
    @State private var originalWorkPeriod: String = ""
    @State private var originalTalent: String = ""
    @State private var originalStylist: String = ""
    @State private var originalHair: String = ""
    @State private var originalMakeup: String = ""
    
    private let addManager = AddManager()
    
    private func loadSelectedWork(id: Int) {
        if let selectedWork = works.first(where: { $0.id == id }) {
            // Initialize editing states first
            initializeEditingStates(with: selectedWork)
            
            // Always fetch files for initial load
            detailsManager.fetchFiles(forWorkId: id) {
                // Load images only after files are fetched
                GridManager.shared.loadImages(
                    forWorkPath: selectedWork.path ?? "",
                    files: self.detailsManager.files.map { 
                        (id: $0.id, path: $0.file, order: $0.ordered, visible: $0.visible ?? true)
                    }
                )
            }
        }
    }
    
    private func loadWorksAndSelectFirst() {
        works = databaseManager.fetchWorks()
        if let firstWork = works.first {
            currentEditingId = nil  // Reset this to ensure initial load works
            selectedWorkId = firstWork.id
            loadSelectedWork(id: firstWork.id)
        }
    }
    
    private func initializeEditingStates(with work: DatabaseManager.Work) {
        // Set both edited and original values
        editedWorkPeriod = work.workPeriod ?? ""
        editedTalent = work.talent ?? ""
        editedStylist = work.stylist ?? ""
        editedHair = work.hair ?? ""
        editedMakeup = work.makeup ?? ""
        
        originalWorkPeriod = work.workPeriod ?? ""
        originalTalent = work.talent ?? ""
        originalStylist = work.stylist ?? ""
        originalHair = work.hair ?? ""
        originalMakeup = work.makeup ?? ""
        
        currentEditingId = work.id
        isEdited = false
    }
    
    private func hasChanges() -> Bool {
        return editedWorkPeriod != originalWorkPeriod ||
               editedTalent != originalTalent ||
               editedStylist != originalStylist ||
               editedHair != originalHair ||
               editedMakeup != originalMakeup
    }
    
    private func saveChanges() {
        guard let id = currentEditingId else { return }
        
        if databaseManager.updateWork(
            id: id,
            workPeriod: editedWorkPeriod,
            talent: editedTalent,
            stylist: editedStylist,
            hair: editedHair,
            makeup: editedMakeup,
            visible: works.first(where: { $0.id == id })?.visible ?? true
        ) {
            works = databaseManager.fetchWorks()
            isEdited = false
            
            if let pendingId = pendingWorkId {
                selectedWorkId = pendingId
                if let selectedWork = works.first(where: { $0.id == pendingId }) {
                    initializeEditingStates(with: selectedWork)
                }
                pendingWorkId = nil
            } else {
                // Update original values after successful save
                originalWorkPeriod = editedWorkPeriod
                originalTalent = editedTalent
                originalStylist = editedStylist
                originalHair = editedHair
                originalMakeup = editedMakeup
            }
        }
    }
    
    private func toggleVisibility(for workId: Int) {
        if let index = works.firstIndex(where: { $0.id == workId }) {
            let work = works[index]
            if databaseManager.updateWork(
                id: workId,
                workPeriod: work.workPeriod,
                talent: work.talent,
                stylist: work.stylist,
                hair: work.hair,
                makeup: work.makeup,
                visible: !work.visible
            ) {
                // Refresh the works list after successful update
                works = databaseManager.fetchWorks()
            }
        }
    }
    
    var filteredWorks: [DatabaseManager.Work] {
        var filtered = works
        if hideInvisibleWorks {
            filtered = filtered.filter { $0.visible }
        }
        if searchText.isEmpty {
            return filtered
        } else {
            return filtered.filter { work in
                (work.workPeriod ?? "").localizedCaseInsensitiveContains(searchText) ||
                (work.stylist ?? "").localizedCaseInsensitiveContains(searchText) ||
                (work.hair ?? "").localizedCaseInsensitiveContains(searchText) ||
                (work.makeup ?? "").localizedCaseInsensitiveContains(searchText) ||
                (work.talent ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // Header view for the works list
    private var worksHeaderView: some View {
        HStack {
            Spacer()
            VStack(spacing: 16) {
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
                .padding([.bottom], -10)
            }
            .frame(width: 300)
            .padding([.leading], -128)
            .padding([.bottom], 20)
            Spacer()
        }
    }
    
    // Work list row view
    private func workRowView(work: DatabaseManager.Work) -> some View {
        HStack {
            Text(work.workPeriod ?? "Unknown Work")
                .font(.system(size: 16, weight: .light))
                .tag(work.id)
            Spacer()
            if showVisibilityCheckboxes {
                Image(systemName: work.visible ? "checkmark.square" : "square")
                    .foregroundColor(.gray)
                    .onTapGesture {
                        toggleVisibility(for: work.id)
                    }
            }
        }
    }
    
    // Search field view
    private var searchFieldView: some View {
        HStack {
            Spacer()
            TextField("Search works...", text: $searchText)
                .textFieldStyle(.plain)
                .frame(width: 262, height: 28)
                .padding(.horizontal, 8)
                .font(.system(size: 13))
                .background(Color(NSColor.gray))
                .cornerRadius(5)
               
            Spacer()
        }
        .padding(.top, 20)
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(alignment: .leading) {
                VStack {
                    worksHeaderView
                    
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            List(filteredWorks, id: \.id, selection: $selectedWorkId) { work in
                                workRowView(work: work)
                            }
                            .frame(width: 300)
                            .listStyle(.sidebar)
                            Spacer()
                        }
                        
                        searchFieldView
                    }
                }
            }
            .padding([.top,.bottom],50)
            .navigationSplitViewColumnWidth(min: 300, ideal: 300)
            .toolbar {

                
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        showVisibilityCheckboxes.toggle()
                        UserDefaults.standard.set(showVisibilityCheckboxes, forKey: "ShowVisibilityCheckboxes")
                        NotificationCenter.default.post(name: Notification.Name("VisibilitySettingsChanged"), object: nil)
                    }) {
                        EmptyView()
                    }
                    .keyboardShortcut("h", modifiers: .command)
                }
                
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        hideInvisibleWorks.toggle()
                        UserDefaults.standard.set(hideInvisibleWorks, forKey: "HideInvisibleWorks")
                        NotificationCenter.default.post(name: Notification.Name("VisibilitySettingsChanged"), object: nil)
                    }) {
                        EmptyView()
                    }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                }
            }
        } detail: {
            if works.first(where: { $0.id == selectedWorkId }) != nil {
                GeometryReader { geometry in
                    VStack(alignment: .leading, spacing: 1) {
                        TextField("Work Period", text: $editedWorkPeriod)
                            .font(.system(size: 38, weight: .light))
                            .textFieldStyle(.plain)
                            .onChange(of: editedWorkPeriod) { _, _ in
                                isEdited = hasChanges()
                            }
                            .padding([.top],48)
                        
                        ImageCollectionViewWithDialog(gridManager: GridManager.shared) { selectedIndexes in
                            GridManager.shared.selectedItemIndexes = selectedIndexes
                        }
                        .padding([.top],20)
                        .padding([.bottom],-30)
                        .frame(height: geometry.size.height - 265) // Increased space for form
                        
                        HStack(alignment: .bottom, spacing: 40) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Talent:")
                                        .foregroundColor(.gray)
                                        .frame(width: 80, alignment: .trailing)
                                    TextField("Enter talent", text: $editedTalent)
                                        .textFieldStyle(.plain)
                                        .onChange(of: editedTalent) { _, _ in
                                            isEdited = hasChanges()
                                        }
                                }
                                
                                HStack {
                                    Text("Stylist:")
                                        .foregroundColor(.gray)
                                        .frame(width: 80, alignment: .trailing)
                                    TextField("Enter stylist", text: $editedStylist)
                                        .textFieldStyle(.plain)
                                        .onChange(of: editedStylist) { _, _ in
                                            isEdited = hasChanges()
                                        }
                                }
                                
                                HStack {
                                    Text("Hair:")
                                        .foregroundColor(.gray)
                                        .frame(width: 80, alignment: .trailing)
                                    TextField("Enter hair", text: $editedHair)
                                        .textFieldStyle(.plain)
                                        .onChange(of: editedHair) { _, _ in
                                            isEdited = hasChanges()
                                        }
                                }
                                
                                HStack {
                                    Text("Makeup:")
                                        .foregroundColor(.gray)
                                        .frame(width: 80, alignment: .trailing)
                                    TextField("Enter makeup", text: $editedMakeup)
                                        .textFieldStyle(.plain)
                                        .onChange(of: editedMakeup) { _, _ in
                                            isEdited = hasChanges()
                                        }
                                }
                            }
                            .font(.system(size: 16))
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Spacer()
                                HStack(spacing: 12) {
                                    Button("Add Photos") {
                                        if let selectedWork = works.first(where: { $0.id == selectedWorkId }),
                                           let workPath = selectedWork.path {
                                            addManager.showOpenPanel(workId: selectedWork.id, workPath: workPath)
                                        }
                                    }
                                
                                    Button("Remove Work") {
                                        showDeleteAlert = true
                                    }
                                    .foregroundColor(.red)
                                
                                    Button(action: {
                                        saveChanges()
                                    }) {
                                        Text("Save")
                                            .foregroundColor(isEdited ? .blue : .gray)
                                    }
                                    .disabled(!isEdited)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: 120)
                        .padding(.bottom, 0)
                    }
                }
                .padding([.trailing,.leading],50)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
        }
        .onChange(of: selectedWorkId) { _, newId in
            if hasChanges() {
                pendingWorkId = newId
                showUnsavedChangesAlert = true
            } else if let newId = newId {
                // Only load if we're not already showing this work
                if currentEditingId != newId {
                    loadSelectedWork(id: newId)
                    currentEditingId = newId
                }
            }
        }
        .alert("Unsaved Changes", isPresented: $showUnsavedChangesAlert) {
            Button("Save Changes", role: .none) {
                saveChanges()
            }
            Button("Discard Changes", role: .destructive) {
                if let pendingId = pendingWorkId {
                    // Set the ID first
                    selectedWorkId = pendingId
                    
                    // Then load the work (this will handle both state initialization and file loading)
                    loadSelectedWork(id: pendingId)
                }
                pendingWorkId = nil
            }
            Button("Cancel", role: .cancel) {
                selectedWorkId = currentEditingId
                pendingWorkId = nil
            }
        } message: {
            Text("Do you want to save your changes before switching to another work?")
        }
        .alert("Delete Work", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let id = selectedWorkId {
                    LogManager.shared.log("ContentView: Starting deletion of work with ID: \(id)", type: .delete)
                    if databaseManager.deleteWork(id: id) {
                        LogManager.shared.log("ContentView: Successfully removed work from UI", type: .delete)
                        // Remove from works array
                        works.removeAll { $0.id == id }
                        // Clear selection
                        selectedWorkId = works.first?.id
                        // Clear grid items but keep cache
                        GridManager.shared.items.removeAll()
                    } else {
                        LogManager.shared.log("ContentView: Failed to delete work with ID: \(id)", type: .error)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this work? This action cannot be undone.")
        }
        .onAppear {
            if databaseManager.isDatabaseSelected {
                loadWorksAndSelectFirst()
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
            
            // Add observer for visibility settings changes
            NotificationCenter.default.addObserver(
                forName: Notification.Name("VisibilitySettingsChanged"),
                object: nil,
                queue: .main
            ) { _ in
                showVisibilityCheckboxes = UserDefaults.standard.bool(forKey: "ShowVisibilityCheckboxes")
                hideInvisibleWorks = UserDefaults.standard.bool(forKey: "HideInvisibleWorks")
                works = databaseManager.fetchWorks()
            }
        }
        .onChange(of: databaseManager.isDatabaseSelected) { _, isSelected in
            if isSelected {
                loadWorksAndSelectFirst()
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
        .frame(width: 1200, height: 1000)
}
