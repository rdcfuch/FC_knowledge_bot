import SwiftUI
import SwiftData
import UniformTypeIdentifiers


struct DocumentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var manualTexts: [ManualText]
    @State private var showManualInput = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Manual Input")) {
                    Button(action: { showManualInput.toggle() }) {
                        Label("Add Text", systemImage: "square.and.pencil")
                    }
                }
                
                Section(header: Text("Manual Texts")) {
                    ForEach(manualTexts) { text in
                        NavigationLink(destination: ManualInputView(editingText: text)) {
                            VStack(alignment: .leading) {
                                Text(text.title)
                                    .lineLimit(1)
                                Text(text.content.prefix(50))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(text.lastModifiedAt, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .onDelete(perform: deleteManualTexts)
                }
            }
            .navigationTitle("Add Knowledge")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .sheet(isPresented: $showManualInput) {
                NavigationView {
                    ManualInputView()
                }
            }
        }
    }
    
    private func deleteManualTexts(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(manualTexts[index])
            try? modelContext.save()
        }
    }
}

#Preview {
    DocumentPickerView()
        .modelContainer(for: [Document.self, ManualText.self], inMemory: true)
}