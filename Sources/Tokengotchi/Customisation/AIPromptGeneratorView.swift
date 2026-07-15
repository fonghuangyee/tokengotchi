import SwiftUI
import AppKit

struct AIPromptGeneratorView: View {
    @ObservedObject var petState: PetState
    @ObservedObject var petManager: PetManager
    var editPetName: String?
    @Environment(\.dismiss) var dismiss

    @State var showCopied = false
    @State var importError: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                    
                    Text("AI Generator")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                }

                Text("Copy the prompt below to ChatGPT or Claude. The AI will ask you to describe your pet, and then generate a .json file that you can import here.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                // Copy Prompt
                Button {
                    var finalPrompt = loadPromptTemplate()
                    if let editPetName = editPetName, let targetPet = petManager.availablePets.first(where: { $0.name == editPetName }) {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted]
                        if let data = try? encoder.encode(targetPet),
                           let jsonStr = String(data: data, encoding: .utf8) {
                            finalPrompt += "\n\nUSE THIS EXISTING JSON AS A BASE AND MODIFY IT:\n```json\n\(jsonStr)\n```"
                        }
                    }
                    
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(finalPrompt, forType: .string)
                    withAnimation { showCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showCopied = false }
                    }
                } label: {
                    HStack {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        Text(showCopied ? "Prompt Copied!" : "Copy Prompt for AI")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.purple.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Divider().background(Color.white.opacity(0.1))

                // Import
                Text("Got the JSON from your AI?")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                
                HStack(spacing: 12) {
                    Button {
                        importFile()
                    } label: {
                        actionButton(title: "Import .json File", icon: "doc.badge.plus")
                    }
                    .buttonStyle(.plain)

                    Button {
                        importClipboard()
                    } label: {
                        actionButton(title: "Paste from Clipboard", icon: "clipboard")
                    }
                    .buttonStyle(.plain)
                }

                if let err = importError {
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(16)
        }
        .background(Color.black.opacity(0.4).ignoresSafeArea())
    }
    
    private func actionButton(title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.8))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func loadPromptTemplate() -> String {
        let isEditing = (editPetName != nil)
        let templateName = isEditing ? "AI_EDIT_PET_PROMPT_TEMPLATE" : "AI_PROMPT_TEMPLATE"
        
        // Try to load from bundle if bundled
        if let url = Bundle.main.url(forResource: templateName, withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        // Fallback for development if run from Xcode, try to load from project root
        let rootPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Customisation
            .deletingLastPathComponent() // Tokengotchi
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // tokengotchi (root)
            .appendingPathComponent("\(templateName).md")
        
        if let text = try? String(contentsOf: rootPath, encoding: .utf8) {
            return text
        }
        
        return "Error: Could not load \(templateName).md. Ensure it is included in the project bundle."
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { r in
            guard r == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let pet = try PetFile.parse(data)
                try petManager.savePet(pet)
                petManager.setActivePet(pet)
                dismiss()
            } catch {
                importError = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private func importClipboard() {
        importClipboard(retryCount: 0)
    }
    
    private func importClipboard(retryCount: Int) {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            importError = "Clipboard is empty."
            return
        }
        
        let isStalePrompt = text.contains("You are an expert Pet Designer") || text.contains("Before generating any code, you MUST interview the user")
        
        if isStalePrompt {
            if retryCount < 5 {
                // Clipboard hasn't synchronized yet, retry in 100ms
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.importClipboard(retryCount: retryCount + 1)
                }
                return
            } else {
                importError = "Clipboard still contains the copied prompt. Please copy the AI agent's response and try again."
                return
            }
        }
        
        let jsonStr = extractJSON(from: text)
        do {
            let pet = try PetFile.parse(jsonStr)
            try petManager.savePet(pet)
            petManager.setActivePet(pet)
            dismiss()
        } catch {
            importError = "Import failed: \(error.localizedDescription)"
        }
    }
    
    private func extractJSON(from text: String) -> String {
        if let start = text.range(of: "```json\n") {
            let sub = text[start.upperBound...]
            if let end = sub.range(of: "\n```") {
                return String(sub[..<end.lowerBound])
            }
        }
        if let start = text.range(of: "{"), let end = text.range(of: "}", options: .backwards), start.lowerBound < end.upperBound {
            return String(text[start.lowerBound..<end.upperBound])
        }
        return text
    }
}
