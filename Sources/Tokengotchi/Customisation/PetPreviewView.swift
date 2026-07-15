import SwiftUI
import AppKit

struct PetPreviewView: View {
    @ObservedObject var petState: PetState
    @ObservedObject var petManager: PetManager
    var previewPetName: String?
    
    enum EditSessionType: String, Codable {
        case localFile
        case embeddedJSON
    }
    @StateObject private var fileWatcher = FileWatcher()
    @State private var activeSessionType: EditSessionType? = nil
    @State private var showModeSelectionPopover = false
    
    var targetPet: TGPetFile {
        if let watchedPet = fileWatcher.parsedPet {
            return watchedPet
        }
        if let name = previewPetName, let pet = petManager.availablePets.first(where: { $0.name == name }) {
            return pet
        }
        return petManager.activePet
    }
    
    struct AnimationGroup: Identifiable {
        let id: String
        let animations: [TGAnimationDef]
    }
    
    var dockGroupedAnimations: [AnimationGroup] {
        return targetPet.dock.states.map { state in
            var allAnims = state.animations
            if let subs = state.subStates {
                allAnims.append(contentsOf: subs.flatMap { $0.animations })
            }
            return AnimationGroup(id: state.id, animations: allAnims)
        }.filter { !$0.animations.isEmpty }
    }
    
    var menuGroupedAnimations: [AnimationGroup] {
        return targetPet.menuBar.states.map { state in
            var allAnims = state.animations
            if let subs = state.subStates {
                allAnims.append(contentsOf: subs.flatMap { $0.animations })
            }
            return AnimationGroup(id: state.id, animations: allAnims)
        }.filter { !$0.animations.isEmpty }
    }
    
    let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 16, alignment: .top)
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(targetPet.name)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    if let url = fileWatcher.presentedItemURL {
                        Text("Watching: \(url.lastPathComponent)")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("Live Builder Mode")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    if let sessionType = activeSessionType {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(sessionType == .localFile ? "Live Session Active: Paste the prompt to your AI agent." : "Remote Session Active: Paste the prompt to ChatGPT/Claude.")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            HStack {
                                Button(action: copyPromptAgain) {
                                    Text("Copy Prompt")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.8))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                
                                if sessionType == .embeddedJSON {
                                    Button(action: pasteFromClipboard) {
                                        Text("Paste JSON")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.purple.opacity(0.8))
                                            .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                Button(action: saveAndEndSession) {
                                    Text("Save & End")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue)
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: cancelSession) {
                                    Text("Cancel")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.red.opacity(0.8))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        Button(action: { showModeSelectionPopover = true }) {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                Text("Edit with AI Agent")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.8))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showModeSelectionPopover, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Choose AI Editing Mode")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Text("Select how you want to interact with your AI agent.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                Divider().background(Color.white.opacity(0.1))
                                
                                // Local Agent Option
                                Button(action: {
                                    showModeSelectionPopover = false
                                    startLocalFileSession()
                                }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Image(systemName: "macbook.and.iphone")
                                                .foregroundColor(.purple)
                                            Text("Local Agent (Auto-Sync)")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                        Text("Creates a temporary file and watches it. Best for local agents (Antigravity/Cline/Roo Code) that edit files directly.")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.5))
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                
                                // Remote Agent Option
                                Button(action: {
                                    showModeSelectionPopover = false
                                    startEmbeddedJSONSession()
                                }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Image(systemName: "doc.on.doc")
                                                .foregroundColor(.purple)
                                            Text("Remote Agent (Embed JSON)")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                        Text("Copies the full JSON inside the prompt. Best for web-based agents (ChatGPT/Claude UI) where you copy and paste back.")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.5))
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(14)
                            .frame(width: 280)
                            .background(Color.black.opacity(0.95))
                        }
                    }
                }
            }
            .padding(.horizontal)
            
            if let error = fileWatcher.error {
                Text("Error parsing JSON: \(error.localizedDescription)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 30) {
                    // --- Dock Icon Section ---
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Dock Animations")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(dockGroupedAnimations) { group in
                                ForEach(group.animations, id: \.id) { anim in
                                    AnimationGridItem(
                                        anim: anim,
                                        context: .main,
                                        petState: petState,
                                        activePet: targetPet
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Divider().background(Color.white.opacity(0.2)).padding(.horizontal)
                    
                    // --- Menu Bar Section ---
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Menu Bar Animations")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(menuGroupedAnimations) { group in
                                ForEach(group.animations, id: \.id) { anim in
                                    AnimationGridItem(
                                        anim: anim,
                                        context: .menuBar,
                                        petState: petState,
                                        activePet: targetPet
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
        .padding(.top, 10)
        .background(Color.black.opacity(0.4).ignoresSafeArea())
    }
    
    private func startLocalFileSession() {
        let pet = targetPet
        let tempDir = FileManager.default.temporaryDirectory
        let safeName = pet.name.replacingOccurrences(of: " ", with: "_")
        let tempURL = tempDir.appendingPathComponent("\(safeName)_\(UUID().uuidString).json")
        
        do {
            let data = try JSONEncoder().encode(pet)
            try data.write(to: tempURL)
            fileWatcher.watch(url: tempURL)
            activeSessionType = .localFile
            copyPrompt(for: .localFile)
        } catch {
            print("Failed to start local live session: \(error)")
        }
    }
    
    private func startEmbeddedJSONSession() {
        activeSessionType = .embeddedJSON
        copyPrompt(for: .embeddedJSON)
    }
    
    private func loadEditPromptTemplate() -> String {
        let templateName = "AI_EDIT_PET_PROMPT_TEMPLATE"
        
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
    
    private func copyPrompt(for type: EditSessionType) {
        let template = loadEditPromptTemplate()
        var prompt = template
        
        switch type {
        case .localFile:
            guard let url = fileWatcher.presentedItemURL else { return }
            prompt += """
            

            ---

            The JSON file to modify is located at: \(url.path)
            Please read the file, follow the rules above, and apply the requested changes directly to this file.
            """
        case .embeddedJSON:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            if let data = try? encoder.encode(targetPet),
               let jsonStr = String(data: data, encoding: .utf8) {
                prompt += """
                

                ---

                USE THIS EXISTING JSON AS A BASE AND MODIFY IT:
                ```json
                \(jsonStr)
                ```
                """
            }
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
    }
    
    private func copyPromptAgain() {
        guard let type = activeSessionType else { return }
        copyPrompt(for: type)
    }
    
    private func pasteFromClipboard() {
        pasteFromClipboard(retryCount: 0)
    }
    
    private func pasteFromClipboard(retryCount: Int) {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            fileWatcher.error = NSError(domain: "Tokengotchi", code: 1, userInfo: [NSLocalizedDescriptionKey: "Clipboard is empty."])
            return
        }
        
        let isStalePrompt = text.contains("You are an expert Pet Designer") || text.contains("USE THIS EXISTING JSON AS A BASE")
        
        if isStalePrompt {
            if retryCount < 5 {
                // Clipboard hasn't synchronized yet, retry in 100ms
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.pasteFromClipboard(retryCount: retryCount + 1)
                }
                return
            } else {
                fileWatcher.error = NSError(domain: "Tokengotchi", code: 2, userInfo: [NSLocalizedDescriptionKey: "Clipboard still contains the copied prompt. Please copy the AI agent's response and try again."])
                return
            }
        }
        
        let jsonStr = extractJSON(from: text)
        do {
            let pet = try TGPetFile.parse(jsonStr)
            fileWatcher.parsedPet = pet
            fileWatcher.error = nil
        } catch {
            fileWatcher.error = error
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
    
    private func saveAndEndSession() {
        if let modifiedPet = fileWatcher.parsedPet {
            do {
                try petManager.savePet(modifiedPet)
            } catch {
                print("Failed to save pet: \(error)")
            }
        }
        cleanupSession()
    }
    
    private func cancelSession() {
        cleanupSession()
    }
    
    private func cleanupSession() {
        if let url = fileWatcher.presentedItemURL {
            try? FileManager.default.removeItem(at: url)
        }
        fileWatcher.stopWatching()
        fileWatcher.parsedPet = nil
        fileWatcher.error = nil
        activeSessionType = nil
    }
}

struct AnimationGridItem: View {
    let anim: TGAnimationDef
    let context: VectorPetRenderer.RenderingContext
    @ObservedObject var petState: PetState
    let activePet: TGPetFile
    
    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 1.0 / 24.0)) { timelineContext in
                let time = timelineContext.date.timeIntervalSince1970 - petState.animationStartTime
                let img = VectorPetRenderer.renderFrame(
                    clipID: anim.id,
                    pet: activePet,
                    time: time,
                    context: context
                )
                
                if context == .menuBar {
                    Image(nsImage: img)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .foregroundColor(.white)
                } else {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                }
            }
            .frame(width: 80, height: 80)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Text(anim.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .help("ID: \(anim.id)\n\(anim.description)")
    }
}
