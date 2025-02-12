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
                    files: self.detailsManager.files.map { ($0.id, $0.file, $0.ordered) }
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
            makeup: editedMakeup
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
    
    var filteredWorks: [DatabaseManager.Work] {
        if searchText.isEmpty {
            return works
        } else {
            return works.filter { work in
                (work.workPeriod ?? "").localizedCaseInsensitiveContains(searchText) ||
                (work.stylist ?? "").localizedCaseInsensitiveContains(searchText) ||
                (work.hair ?? "").localizedCaseInsensitiveContains(searchText) ||
                (work.makeup ?? "").localizedCaseInsensitiveContains(searchText) ||
                (work.talent ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(alignment: .leading) {
                VStack {
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
                
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        List(filteredWorks, id: \.id, selection: $selectedWorkId) { work in
                            Text(work.workPeriod ?? "Unknown Work")
                                .font(.system(size: 16, weight: .light))
                                .tag(work.id)
                        }
                        .frame(width: 300)
                        .listStyle(.sidebar)
                        Spacer()
                    }
                    
                    HStack {
                        Spacer()
                        TextField("Search works...", text: $searchText)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .frame(width: 270, height: 32)
                            .background(Color(.darkGray))
                            .cornerRadius(6)
                        Spacer()
                    }
                    .padding(.top, 10)
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
            if works.first(where: { $0.id == selectedWorkId }) != nil {
                GeometryReader { geometry in
                    VStack(alignment: .leading, spacing: 20) {
                        TextField("Work Period", text: $editedWorkPeriod)
                            .font(.system(size: 38, weight: .light))
                            .textFieldStyle(.plain)
                            .onChange(of: editedWorkPeriod) { _, _ in
                                isEdited = hasChanges()
                            }
                        
                        ImageCollectionViewWithDialog(gridManager: GridManager.shared) { selectedIndexes in
                            GridManager.shared.selectedItemIndexes = selectedIndexes
                        }
                        .frame(height: geometry.size.height - 235) // Increased space for form
                        
                        HStack(alignment: .bottom, spacing: 20) {
                            VStack(alignment: .leading, spacing: 16) {
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
                        .padding(.bottom, 12)
                    }
                }
                .padding(40)
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
                        // Clear grid
                        GridManager.shared.clearCache()
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
}
