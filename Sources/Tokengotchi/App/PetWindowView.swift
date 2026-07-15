import SwiftUI

// MARK: - Pet Window View
/// Root view for the pet window with a native macOS two-pane split layout.
struct PetWindowView: View {
    @ObservedObject var petState: PetState
    @ObservedObject var providerManager: ProviderManager
    @StateObject private var petManager = PetManager.shared

    @State private var isLLMExpanded = false
    @State private var isDisplayExpanded = false
    @State private var isAboutExpanded = false
    @State private var editingKey: String = ""

    private var antigravity: AntigravityProvider? {
        providerManager.available.first(where: { $0.id == "antigravity" }) as? AntigravityProvider
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Left Panel: Sidebar list of pets
                sidebarView
                
                // Vertical pane divider
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
                    .ignoresSafeArea()
                
                // Right Panel: Selected pet detail and settings
                detailView
            }
            .background(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.08),
                        Color.black.opacity(0.96),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .navigationDestination(for: PetDashboardDestination.self) { dest in
                switch dest {
                case .preview(let petName):
                    PetPreviewView(petState: petState, petManager: petManager, previewPetName: petName)
                case .prompt(let petName):
                    AIPromptGeneratorView(petState: petState, petManager: petManager, editPetName: petName)
                case .jsonEditor:
                    JSONEditorView(petManager: petManager)
                }
            }
        }
    }

    // MARK: - Sidebar View
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PETS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 6)
            
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(petManager.availablePets, id: \.name) { pet in
                        let isActive = petManager.activePet.name == pet.name
                        SidebarPetRow(pet: pet, isActive: isActive) {
                            petManager.activePet = pet
                        }
                    }
                }
                .padding(.horizontal, 6)
            }
            
            Spacer()
            
            // Add Pet Button
            NavigationLink(value: PetDashboardDestination.prompt(nil)) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("New Pet")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3]))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .frame(width: 155)
        .background(Color.black.opacity(0.15))
    }

    // MARK: - Detail View
    private var detailView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Active Pet Header Card
                activePetHeaderCard
                
                // Live Activity Card
                liveActivityCard
                
                // Stamina Card (if applicable)
                if let agy = antigravity, agy.isConnected {
                    StaminaCard(provider: agy)
                }
                
                // Settings Accordion Sections
                settingsAccordion
            }
            .padding(16)
        }
    }

    // MARK: - Active Pet Header Card
    private var activePetHeaderCard: some View {
        VStack(spacing: 12) {
            TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 1.0 / 24.0)) { context in
                Image(
                    nsImage: VectorPetRenderer.renderFrame(
                        clipID: petState.currentClipID,
                        pet: PetManager.shared.activePet,
                        time: context.date.timeIntervalSince1970 - petState.animationStartTime,
                        stamina: antigravity?.currentStamina,
                        modelName: antigravity?.activeModelName
                    )
                )
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 72, height: 72)
            }
            .frame(width: 88, height: 88)
            .background(
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay(Circle().stroke(Color.accentColor.opacity(0.15), lineWidth: 1))
            )
            
            VStack(spacing: 2) {
                Text(petState.config.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                HStack(spacing: 5) {
                    Circle()
                        .fill(modeColor)
                        .frame(width: 6, height: 6)
                    Text(modeLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            // Actions
            HStack(spacing: 8) {
                NavigationLink(value: PetDashboardDestination.preview(petManager.activePet.name)) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle")
                        Text("Clips")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                NavigationLink(value: PetDashboardDestination.prompt(petManager.activePet.name)) {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                        Text("AI Edit")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.25))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Live Activity Card
    private var liveActivityCard: some View {
        let mode = petState.mode
        let accent = modeColor
        let steps = antigravity?.stepCount ?? 0
        let sColor = stepColor(steps)
        let tool = antigravity?.currentTool

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: mode.sfSymbol)
                        .foregroundColor(accent)
                        .font(.system(size: 14))
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(modeLabel)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    if let tool = tool {
                        Text(tool)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                    } else {
                        Text(steps == 0 ? "No active tool" : "Turn complete")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
                
                Spacer()
                
                if mode == .busy {
                    LocalThinkingDots()
                }
            }

            if steps > 0 {
                Divider().background(Color.white.opacity(0.06))
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 9))
                            .foregroundColor(sColor.opacity(0.8))
                        Text("\(steps) steps")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: [sColor.opacity(0.6), sColor],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: geo.size.width * min(1.0, Double(steps) / 100), height: 4
                                )
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Settings Accordion
    private var settingsAccordion: some View {
        VStack(spacing: 8) {
            // LLM Provider Group
            DisclosureGroup(isExpanded: $isLLMExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(providerManager.available, id: \.id) { provider in
                        providerRow(provider)
                    }
                    
                    if let provider = providerManager.available.first(where: { $0.id == providerManager.activeProviderId }) {
                        if provider.id != "antigravity" && provider.id != "ollama" {
                            VStack(alignment: .leading, spacing: 6) {
                                SecureField("API Key for \(provider.name)", text: $editingKey)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                
                                Button("Save Key") {
                                    var cfg = providerManager.configs[provider.id] ?? ProviderConfig()
                                    cfg.apiKey = editingKey
                                    providerManager.configs[provider.id] = cfg
                                    providerManager.switchProvider(to: provider.id)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.top, 4)
                        } else {
                            Text(provider.id == "antigravity"
                                 ? "Bridge auto-connects to localhost:7432"
                                 : "Connects to Ollama at localhost:11434")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.vertical, 4)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.leading, 4)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                    Text("LLM Provider")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .disclosureGroupStyle(CustomDisclosureGroupStyle())
            
            // Display Settings Group
            DisclosureGroup(isExpanded: $isDisplayExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $petState.showMenuBarIcon) {
                        Text("Show Icon in Menu Bar")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    
                    Toggle(isOn: $petState.showDockPet) {
                        Text("Show Pet in Dock")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    
                    Toggle(isOn: $petState.showWidgetPet) {
                        Text("Show Pet as Desktop Widget")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    
                    if petState.showWidgetPet {
                        HStack {
                            Text("Screen:")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                            
                            let screenName: String = {
                                if let id = petState.widgetScreenID,
                                   let screen = NSScreen.screens.first(where: { ScreenManager.shared.screenID($0) == id }) {
                                    return screen.localizedName
                                }
                                return NSScreen.main?.localizedName ?? "Main Screen"
                            }()
                            
                            Text(screenName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                        .padding(.leading, 24)
                    }
                }
                .padding(.top, 8)
                .padding(.leading, 4)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                    Text("Display Settings")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .disclosureGroupStyle(CustomDisclosureGroupStyle())
            
            // About Group
            DisclosureGroup(isExpanded: $isAboutExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tokengotchi v1.0")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Your AI agent's virtual companion 🐾")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Divider().background(Color.white.opacity(0.06)).padding(.vertical, 2)
                    
                    HStack {
                        Text("Pet Config:")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                        Text(petState.config.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    HStack {
                        Text("Clips Loaded:")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                        Text("\(PetManager.shared.activePet.toAnimationClips().count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
                .padding(.top, 8)
                .padding(.leading, 4)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                    Text("About")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .disclosureGroupStyle(CustomDisclosureGroupStyle())
            
            Divider().background(Color.white.opacity(0.06)).padding(.vertical, 8)
            
            // Quit Button at the bottom
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .bold))
                    Text("Quit Tokengotchi")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(.red)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            initializeEditingKey()
        }
        .onChange(of: providerManager.activeProviderId) {
            initializeEditingKey()
        }
    }

    private func providerRow(_ provider: any LLMProviderProtocol) -> some View {
        Button {
            providerManager.activeProviderId = provider.id
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(provider.isConnected ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 7, height: 7)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                    Text(provider.isConnected ? "Connected" : "Disconnected")
                        .font(.system(size: 9))
                        .foregroundColor(provider.isConnected ? .green.opacity(0.7) : .white.opacity(0.35))
                }
                
                Spacer()
                
                if providerManager.activeProviderId == provider.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(providerManager.activeProviderId == provider.id
                          ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(providerManager.activeProviderId == provider.id
                            ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func initializeEditingKey() {
        if let provider = providerManager.available.first(where: { $0.id == providerManager.activeProviderId }) {
            editingKey = providerManager.configs[provider.id]?.apiKey ?? ""
        }
    }

    // MARK: - Helpers
    private var modeLabel: String {
        switch petState.mode {
        case .idle: return "Idle"
        case .busy: return petState.busySubMode.map { $0.displayName + "…" } ?? "Working…"
        case .waiting: return "Waiting for you…"
        case .completed: return "Task complete! 🎉"
        case .error: return "Error!"
        }
    }

    private var modeColor: Color {
        Color(NSColor(hex: petState.mode.accentColorHex) ?? .gray)
    }

    private func stepColor(_ count: Int) -> Color {
        switch count {
        case 0: return .gray
        case 1..<10: return .teal
        case 10..<30: return .cyan
        case 30..<60: return .yellow
        default: return .orange
        }
    }
}

// MARK: - Sidebar Row Helper View
struct SidebarPetRow: View {
    let pet: PetFile
    let isActive: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Mini preview animation
                TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 1.0 / 24.0)) { context in
                    Image(
                        nsImage: OffscreenPetRenderer.renderFrame(
                            clipID: pet.toAnimationClips(forContext: "pet").first?.id ?? "",
                            pet: pet,
                            time: context.date.timeIntervalSince1970,
                            contextName: "pet",
                            targetSize: NSSize(width: 48, height: 48)
                        )
                    )
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                }
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor.opacity(isActive ? 0.2 : 0.08)))
                
                Text(pet.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .white : .white.opacity(0.75))
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.accentColor.opacity(0.15) : (isHovered ? Color.white.opacity(0.04) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Custom Disclosure Group Style
struct CustomDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.2)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack {
                    configuration.label
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.02))
            }
            .buttonStyle(.plain)
            
            if configuration.isExpanded {
                configuration.content
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .background(Color.white.opacity(0.01))
            }
        }
        .background(Color.black.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Local Thinking Dots Animation
struct LocalThinkingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 4, height: 4)
                    .scaleEffect(phase == i ? 1.4 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.4).delay(Double(i) * 0.15).repeatForever(),
                        value: phase)
            }
        }
        .onAppear {
            withAnimation { phase = 0 }
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
    }
}
