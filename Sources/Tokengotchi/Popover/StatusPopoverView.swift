import SwiftUI

// MARK: - Status Popover View
/// Simple native popover shown when clicking the menu bar icon.
/// Shows agent status, an "Open App" button, and a Quit button.

struct StatusPopoverView: View {
    @ObservedObject var petState: PetState
    @ObservedObject var providerManager: ProviderManager

    /// Called when the user clicks "Open App".
    var onOpenApp: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header — pet name + mode
            header

            Divider()
                .overlay(Color.white.opacity(0.1))

            // Status
            statusSection

            Divider()
                .overlay(Color.white.opacity(0.1))

            // Actions
            actionsSection
        }
        .frame(width: 260)
        .fixedSize()
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(petState.config.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(petState.mode.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Mode indicator dot
            Circle()
                .fill(modeColor)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Status
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: petState.mode.sfSymbol)
                    .foregroundColor(modeColor)
                    .font(.system(size: 12))
                Text(modeLabel)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if petState.mode == .busy {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 14, height: 14)
                }
            }

            if let sub = petState.busySubstate {
                Text(sub.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            }

            // Provider + connection
            HStack(spacing: 6) {
                Circle()
                    .fill(
                        providerManager.available.first(where: {
                            $0.id == providerManager.activeProviderId
                        })?.isConnected == true ? .green : .gray
                    )
                    .frame(width: 6, height: 6)
                Text(providerManager.activeProviderName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Actions
    private var actionsSection: some View {
        HStack(spacing: 10) {
            Button {
                onOpenApp?()
            } label: {
                Label("Open App", systemImage: "rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private var modeColor: Color {
        Color(NSColor(hex: petState.mode.accentColorHex) ?? .secondaryLabelColor)
    }

    private var modeLabel: String {
        switch petState.mode {
        case .idle: return "Idle"
        case .busy: return "Working"
        case .waiting: return "Waiting"
        case .completed: return "Task Complete"
        case .error: return "Error"
        }
    }
}
