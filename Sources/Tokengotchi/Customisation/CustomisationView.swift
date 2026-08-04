import SwiftUI
import AppKit

// MARK: - Settings Tab
struct SettingsTab: View {
    @ObservedObject var providerManager: ProviderManager
    @ObservedObject var screenManager: ScreenManager = ScreenManager.shared
    @ObservedObject var sleepManager: SleepManager = SleepManager.shared
    @ObservedObject var petState: PetState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // --- LLM Provider (auto-detected, zero-config) ---
                sectionHeader("LLM Provider")

                let installed = providerManager.available.filter { $0.isInstalledLocally }
                if installed.isEmpty {
                    Text("No supported agent CLI detected.\nInstall Claude Code or Antigravity to begin.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.vertical, 4)
                } else {
                    ForEach(installed, id: \.id) { provider in
                        providerRow(provider)
                    }
                    Text("Auto-detected · no API key required · the pet follows the active agent")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.top, 2)
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

                // --- System ---
                sectionHeader("System")
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $sleepManager.preventSleep) {
                        Text("Prevent Mac from Sleeping")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .purple))

                    Text("Keeps the display awake while your agent is working.")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.leading, 2)
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
        let isActive = providerManager.activeProviderId == provider.id
        return HStack(spacing: 10) {
            Circle()
                .fill(provider.isConnected ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(provider.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            if isActive {
                Image(systemName: "pawprint.fill")
                    .foregroundColor(.purple)
                    .font(.system(size: 13))
            }
        }
        .padding(12)
        .background(isActive ? Color.purple.opacity(0.15) : Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.purple.opacity(0.4) : Color.clear, lineWidth: 1))
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.white.opacity(0.8))
    }
}
