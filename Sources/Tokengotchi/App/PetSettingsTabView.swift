import SwiftUI
import AppKit

// MARK: - Settings Tab (cleaned up — no API key management)
struct PetSettingsTabView: View {
    @ObservedObject var providerManager: ProviderManager
    @ObservedObject var petState: PetState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // LLM Provider Selection
                secHead("LLM Provider")
                ForEach(providerManager.available, id: \.id) { provider in
                    providerRow(provider)
                }

                Divider().background(Color.white.opacity(0.06))

                // Display Settings
                secHead("Display Settings")
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

                Divider().background(Color.white.opacity(0.06))

                // About
                secHead("About")
                VStack(alignment: .leading, spacing: 5) {
                    Text("Tokengotchi v1.0")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Your AI agent's virtual companion 🐾")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.45))
                    Text("Pet: \(petState.config.name)")
                        .font(.system(size: 10)).foregroundColor(.white.opacity(0.35))
                    Text(
                        "Animations: \(PetManager.shared.activePet.toAnimationClips().count) loaded"
                    )
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.35))
                }

                Divider().background(Color.white.opacity(0.06))

                // Quit
                Button {
                    NSApp.terminate(nil)
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "power").font(.system(size: 12, weight: .bold))
                        Text("Quit Tokengotchi").font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .foregroundColor(.red)
                    .padding(.vertical, 11)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9).stroke(
                            Color.red.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(18)
        }
    }

    private func providerRow(_ provider: any LLMProviderProtocol) -> some View {
        Button {
            providerManager.activeProviderId = provider.id
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(provider.isConnected ? Color.green : Color.gray.opacity(0.35))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                    Text(provider.isConnected ? "Connected" : "Disconnected")
                        .font(.system(size: 9))
                        .foregroundColor(
                            provider.isConnected ? .green.opacity(0.65) : .white.opacity(0.3))
                }
                Spacer()
                if providerManager.activeProviderId == provider.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.purple).font(.system(size: 13))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(
                        providerManager.activeProviderId == provider.id
                            ? Color.purple.opacity(0.12) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(
                        providerManager.activeProviderId == provider.id
                            ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func secHead(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.white.opacity(0.7))
    }
}
