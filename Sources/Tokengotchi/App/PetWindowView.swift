import SwiftUI

// MARK: - Pet Window View
/// Root view for the pet window with tabbed navigation.
struct PetWindowView: View {
    @ObservedObject var petState: PetState
    @ObservedObject var providerManager: ProviderManager
    @StateObject private var petManager = PetManager.shared

    @State private var selectedTab: Tab = .status

    enum Tab: String, CaseIterable {
        case status = "Status"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .status: return "pawprint.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    private var antigravity: AntigravityProvider? {
        providerManager.available.first(where: { $0.id == "antigravity" }) as? AntigravityProvider
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                headerBar

                // Content area
                Group {
                    switch selectedTab {
                    case .status:
                        HomeTab(petState: petState, providerManager: providerManager, petManager: petManager)
                    case .settings:
                        SettingsTab(providerManager: providerManager, petState: petState)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.94))

                // Bottom tab bar
                tabBar
            }
            .background(
                LinearGradient(
                    colors: [
                        Color.purple.opacity(0.12),
                        Color.black.opacity(0.97),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .navigationDestination(for: PetDashboardDestination.self) { dest in
                switch dest {
                case .preview:
                    PetPreviewView(petState: petState, petManager: petManager)
                case .prompt:
                    AIPromptGeneratorView(petState: petState, petManager: petManager)
                case .jsonEditor:
                    JSONEditorView(petManager: petManager)
                }
            }
        }
    }

    // MARK: - Header Bar
    var headerBar: some View {
        HStack(spacing: 14) {
            // Pet avatar preview (live animated)
            TimelineView(.animation) { context in
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
                .frame(width: 40, height: 40)
            }
            .frame(width: 52, height: 52)
            .background(
                Circle()
                    .fill(
                        Color.purple.opacity(0.15))
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(petState.config.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                HStack(spacing: 4) {
                    Circle()
                        .fill(modeColor)
                        .frame(width: 6, height: 6)
                    Text(modeLabel)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()

            // Provider badge
            HStack(spacing: 5) {
                Circle()
                    .fill(
                        providerManager.available.first(where: {
                            $0.id == providerManager.activeProviderId
                        })?.isConnected == true ? .green : .gray
                    )
                    .frame(width: 6, height: 6)
                Text(providerManager.activeProviderName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())

            // Quit button
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Quit Tokengotchi")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.03))
        .overlay(
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Tab Bar
    var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(duration: 0.25)) { selectedTab = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .medium))
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(
                        selectedTab == tab
                            ? Color.purple
                            : .white.opacity(0.35)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        selectedTab == tab ? Color.white.opacity(0.06) : Color.clear
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white.opacity(0.02))
        .overlay(
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Helpers
    private var modeLabel: String {
        switch petState.mode {
        case .idle: return "Idle"
        case .busy: return petState.busySubstate.map { $0.displayName + "…" } ?? "Working…"
        case .waiting: return "Waiting for you…"
        case .completed: return "Task complete! 🎉"
        case .error: return "Error!"
        }
    }

    private var modeColor: Color {
        Color(NSColor(hex: petState.mode.accentColorHex) ?? .gray)
    }
}


