import SwiftUI

struct AddWorkView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var worksManager = WorksManager.shared
    @State private var workTitle = ""
    var onWorkAdded: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add New Work")
                .font(.system(size: 20, weight: .medium))
            
            TextField("Work Title", text: $workTitle)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 300)
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                
                Button("Add") {
                    if worksManager.addNewWork(workPeriod: workTitle) {
                        onWorkAdded()
                        dismiss()
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(workTitle.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 150)
        .alert("Error", isPresented: $worksManager.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(worksManager.errorMessage)
        }
    }
}

#Preview {
    AddWorkView(onWorkAdded: {})
}
