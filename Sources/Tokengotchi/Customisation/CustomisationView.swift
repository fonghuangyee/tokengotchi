import SwiftUI
import AppKit

// MARK: - Settings Tab
struct SettingsTab: View {
    @ObservedObject var providerManager: ProviderManager
    @ObservedObject var screenManager: ScreenManager = ScreenManager.shared
    @ObservedObject var petState: PetState

    @State private var editingKey: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // --- LLM Provider ---
                sectionHeader("LLM Provider")

                ForEach(providerManager.available, id: \.id) { provider in
                    providerRow(provider)
                }

                Divider().background(Color.white.opacity(0.1))

                // --- Display Settings ---
                sectionHeader("Display Settings")
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $petState.showMenuBarIcon) {
                        Text("Show Icon in Menu Bar")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                    
                    Toggle(isOn: $petState.showDockPet) {
                        Text("Show Pet in Dock")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                    
                    Toggle(isOn: $petState.showWidgetPet) {
                        Text("Show Pet as Desktop Widget")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                    
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
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.purple)
                        }
                        .padding(.leading, 24)
                    }
                }

                Divider().background(Color.white.opacity(0.1))

                // --- API Key ---
                sectionHeader("API Key")

                if let provider = providerManager.available.first(where: {
                    $0.id == providerManager.activeProviderId
                }) {
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
                        Text(
                            provider.id == "antigravity"
                                ? "Bridge auto-connects to localhost:7432"
                                : "Connects to Ollama at localhost:11434"
                        )
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
            .background(
                providerManager.activeProviderId == provider.id
                    ? Color.purple.opacity(0.15) : Color.white.opacity(0.05)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        providerManager.activeProviderId == provider.id
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
