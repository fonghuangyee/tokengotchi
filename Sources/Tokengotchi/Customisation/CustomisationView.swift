import SwiftUI

// MARK: - Settings Tab
struct SettingsTab: View {
    @ObservedObject var providerManager: ProviderManager
    @ObservedObject var screenManager: ScreenManager = ScreenManager.shared
    @ObservedObject var petState: PetState

    @State private var editingKey: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {



                // --- Agent Status ---
                AgentStatusView(petState: petState)

                Divider().background(Color.white.opacity(0.1))

                // --- LLM Provider ---
                sectionHeader("LLM Provider")

                ForEach(providerManager.available, id: \.id) { provider in
                    providerRow(provider)
                }

                Divider().background(Color.white.opacity(0.1))

                // --- API Key ---
                sectionHeader("API Key")

                if let provider = providerManager.available.first(where: { $0.id == providerManager.activeProviderId }) {
                    if provider.id != "antigravity" && provider.id != "ollama" {
                        SecureField("API Key for \(provider.name)", text: $editingKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button("Save Key") {
                            var cfg = providerManager.configs[provider.id] ?? ProviderConfig()
                            cfg.apiKey = editingKey
                            providerManager.configs[provider.id] = cfg
                            providerManager.switchProvider(to: provider.id)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.purple)
                    } else {
                        Text(provider.id == "antigravity"
                             ? "Bridge auto-connects to localhost:7432"
                             : "Connects to Ollama at localhost:11434")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }

                Divider().background(Color.white.opacity(0.1))

                // --- About ---
                sectionHeader("About")
                Text("Tokengotchi v1.0\nYour AI agent's virtual companion 🐾")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))

                Divider().background(Color.white.opacity(0.1))

                // --- Quit Button ---
                Button {
                    NSApp.terminate(nil)
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .bold))
                        Text("Quit Tokengotchi")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .foregroundColor(.red)
                    .padding(10)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.red.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .onAppear {
            petState.isSimulating = true // Allows manual status overrides to stick
        }
        .onDisappear {
            petState.isSimulating = false
            petState.setMode(.idle)
        }
    }

    // MARK: - Row Helpers
    func providerRow(_ provider: any LLMProviderProtocol) -> some View {
        Button {
            providerManager.activeProviderId = provider.id
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(provider.isConnected ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(provider.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                if providerManager.activeProviderId == provider.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.purple)
                        .font(.system(size: 14))
                }
            }
            .padding(12)
            .background(providerManager.activeProviderId == provider.id
                        ? Color.purple.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(providerManager.activeProviderId == provider.id
                        ? Color.purple.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.white.opacity(0.8))
    }
}

// MARK: - Agent Status Chooser
struct AgentStatusView: View {
    @ObservedObject var petState: PetState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent Status")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))

            Text("Manually override the pet's animation state. Transient states automatically return to Idle after a short delay.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .padding(.bottom, 4)

            ForEach(PetMode.allCases, id: \.self) { mode in
                Button {
                    petState.setMode(mode, substate: mode == .busy ? .thinking : nil)
                } label: {
                    HStack(spacing: 12) {
                        TimelineView(.animation) { context in
                            let clipID = petState.assignments.clips(for: mode, substate: mode == .busy ? .thinking : nil).first?.id ?? AnimationLibrary.defaultClip(for: mode).id
                            let image = OffscreenPetRenderer.renderFrame(
                                clipID: clipID,
                                config: petState.config,
                                time: context.date.timeIntervalSince1970
                            )

                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(mode.displayName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)

                                if mode.isTransient {
                                    Text("Transient")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white.opacity(0.4))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.white.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }

                            Text(simulatorDescription(mode))
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                        }

                        Spacer()

                        if petState.mode == mode {
                            Text("Active")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .padding(10)
                    .background(petState.mode == mode ? Color.purple.opacity(0.1) : Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(petState.mode == mode ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func simulatorDescription(_ mode: PetMode) -> String {
        switch mode {
        case .idle:      return "Resting — rotates through idle clips"
        case .busy:      return "Working — clips may reflect the tool phase"
        case .waiting:   return "Needs attention from the user"
        case .completed: return "Task succeeded — brief celebration"
        case .error:     return "Something went wrong"
        }
    }
}
