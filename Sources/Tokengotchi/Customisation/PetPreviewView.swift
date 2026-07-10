import SwiftUI
import AppKit

struct PetPreviewView: View {
    @ObservedObject var petState: PetState
    @ObservedObject var petManager: PetManager
    var previewPetName: String?
    
    var targetPet: TGPetFile {
        if let name = previewPetName, let pet = petManager.availablePets.first(where: { $0.name == name }) {
            return pet
        }
        return petManager.activePet
    }
    
    struct AnimationGroup: Identifiable {
        let id: String
        let animations: [TGAnimationDef]
    }
    
    @State private var previewDockClipID: String = ""
    @State private var previewMenuClipID: String = ""
    
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
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text(targetPet.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal)
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 30) {
                    // --- Dock Icon Section ---
                    VStack(spacing: 16) {
                        Text("Dock Icon Pet")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        TimelineView(.animation) { context in
                            let time = context.date.timeIntervalSince1970 - petState.animationStartTime
                            Image(
                                nsImage: VectorPetRenderer.renderFrame(
                                    clipID: previewDockClipID,
                                    pet: targetPet,
                                    time: time,
                                    context: .main
                                )
                            )
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                        }
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                        
                        AnimationCarouselView(
                            groupedAnimations: dockGroupedAnimations,
                            selectedID: $previewDockClipID,
                            context: .main,
                            petState: petState,
                            activePet: targetPet
                        )
                    }
                    
                    Divider().background(Color.white.opacity(0.2)).padding(.horizontal)
                    
                    // --- Menu Bar Section ---
                    VStack(spacing: 16) {
                        Text("Menu Bar Pet")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        TimelineView(.animation) { context in
                            let time = context.date.timeIntervalSince1970 - petState.animationStartTime
                            let img = VectorPetRenderer.renderFrame(
                                clipID: previewMenuClipID,
                                pet: targetPet,
                                time: time,
                                context: .menuBar
                            )
                            Image(nsImage: img)
                                .resizable()
                                .renderingMode(.template)
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(width: 64, height: 64)
                                .foregroundColor(.white)
                        }
                        .frame(height: 100)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                        
                        AnimationCarouselView(
                            groupedAnimations: menuGroupedAnimations,
                            selectedID: $previewMenuClipID,
                            context: .menuBar,
                            petState: petState,
                            activePet: targetPet
                        )
                    }
                }
                .padding(.vertical)
            }
            
            Spacer()
            
            // Actions
            VStack(spacing: 12) {
                NavigationLink(value: PetDashboardDestination.prompt(targetPet.name)) {
                    actionButton(title: "Modify with AI", icon: "wand.and.stars", color: .purple)
                }
                .buttonStyle(.plain)
                
                NavigationLink(value: PetDashboardDestination.jsonEditor) {
                    actionButton(title: "Edit JSON", icon: "chevron.left.forwardslash.chevron.right", color: .blue)
                }
                .buttonStyle(.plain)
                
                Button {
                    exportJSON()
                } label: {
                    actionButton(title: "Export JSON", icon: "square.and.arrow.up", color: .green)
                }
                .buttonStyle(.plain)
                
                
                if targetPet.name != petManager.activePet.name {
                    Button {
                        petManager.activePet = targetPet
                        // Also trigger a save or update if needed
                    } label: {
                        actionButton(title: "Set Active Pet", icon: "checkmark.circle.fill", color: .blue)
                    }
                    .buttonStyle(.plain)
                }

                if targetPet.name != PetManager.defaultPet().name {
                    Button {
                        petManager.deletePet(targetPet)
                    } label: {
                        actionButton(title: "Delete", icon: "trash", color: .red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .padding(.top, 10)
        .background(Color.black.opacity(0.4).ignoresSafeArea())
        .onAppear {
            previewDockClipID = targetPet.dock.states.first?.animations.first?.id ?? ""
            previewMenuClipID = targetPet.menuBar.states.first?.animations.first?.id ?? ""
        }
    }
    

    
    private func actionButton(title: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 1)
        )
    }
    
    private func exportJSON() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        let safeName = targetPet.name.replacingOccurrences(of: " ", with: "_")
        savePanel.nameFieldStringValue = "\(safeName).json"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            do {
                let data = try encoder.encode(targetPet)
                try data.write(to: url)
            } catch {
                print("Failed to export: \(error)")
            }
        }
    }
}

struct AnimationCarouselView: View {
    let groupedAnimations: [PetPreviewView.AnimationGroup]
    @Binding var selectedID: String
    let context: VectorPetRenderer.RenderingContext
    @ObservedObject var petState: PetState
    let activePet: TGPetFile
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(groupedAnimations) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.id.capitalized)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(group.animations, id: \.id) { anim in
                                Button {
                                    selectedID = anim.id
                                } label: {
                                    TimelineView(.animation) { timelineContext in
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
                                                .interpolation(.none)
                                                .scaledToFit()
                                                .frame(width: 40, height: 40)
                                                .foregroundColor(.white)
                                        } else {
                                            Image(nsImage: img)
                                                .resizable()
                                                .interpolation(.none)
                                                .scaledToFit()
                                                .frame(width: 40, height: 40)
                                        }
                                    }
                                    .frame(width: 50, height: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedID == anim.id ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedID == anim.id ? Color.purple : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("\(anim.name)\n\(anim.description)")
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
    }
}
