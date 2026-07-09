import SwiftUI
import AppKit

struct JSONEditorView: View {
    @ObservedObject var petManager: PetManager
    @Environment(\.dismiss) var dismiss

    @State private var jsonText: String = ""
    @State private var saveError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Text("Edit JSON")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                
                Button("Paste") {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        jsonText = text
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
                .buttonStyle(.plain)
                
                Button("Save") {
                    saveJSON()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.white)
                .clipShape(Capsule())
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.black.opacity(0.3))

            if let err = saveError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
            }

            // Editor
            TextEditor(text: $jsonText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.black.opacity(0.5))
        }
        .background(Color.black.opacity(0.4).ignoresSafeArea())
        .onAppear {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            if let data = try? encoder.encode(petManager.activePet),
               let str = String(data: data, encoding: .utf8) {
                jsonText = str
            }
        }
    }

    private func saveJSON() {
        do {
            let pet = try TGPetFile.parse(jsonText)
            try petManager.savePet(pet)
            petManager.setActivePet(pet)
            dismiss()
        } catch {
            saveError = "Invalid JSON: \(error.localizedDescription)"
        }
    }
}
