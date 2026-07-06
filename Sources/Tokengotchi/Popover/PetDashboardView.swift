import SwiftUI

// MARK: - Pet Dashboard (Popover)
struct PetDashboardView: View {
    @ObservedObject var petState: PetState
    @ObservedObject var providerManager: ProviderManager

    @State private var selectedTab: DashboardTab = .home

    enum DashboardTab: String, CaseIterable {
        case home = "house.fill"
        case petBuilder = "wand.and.stars.inverse"
        case settings = "gearshape.fill"
    }

    var body: some View {
        ZStack {
            // Background gradient
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerBar

                // Content
                Group {
                    switch selectedTab {
                    case .home:         HomeTab(petState: petState, providerManager: providerManager)
                    case .petBuilder:   PetBuilderTab(petState: petState)
                    case .settings:     SettingsTab(providerManager: providerManager, petState: petState)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Tab bar
                tabBar
            }
        }
        .frame(width: 340, height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Background
    var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(hex: petState.config.auraColor)?.opacity(0.25) ?? Color.purple.opacity(0.25),
                Color.black.opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: Header Bar
    var headerBar: some View {
        HStack(spacing: 12) {
            // Pet mini preview
            Circle()
                .fill(Color(hex: petState.config.baseColor) ?? .purple)
                .frame(width: 36, height: 36)
                .overlay(
                    Text("🐾").font(.system(size: 18))
                )
                .overlay(
                    Circle().stroke(Color(hex: petState.config.auraColor)?.opacity(0.8) ?? .purple, lineWidth: 2)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(petState.config.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(petState.moodLabel)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            // Provider badge
            HStack(spacing: 4) {
                Circle()
                    .fill(providerManager.available.first(where: { $0.id == providerManager.activeProviderId })?.isConnected == true ? .green : .gray)
                    .frame(width: 6, height: 6)
                Text(providerManager.activeProviderName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
    }

    // MARK: Tab Bar
    var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DashboardTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(duration: 0.25)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.rawValue)
                            .font(.system(size: 16))
                            .foregroundColor(selectedTab == tab ? Color(hex: petState.config.auraColor) ?? .purple : .white.opacity(0.4))
                        if selectedTab == tab {
                            Circle()
                                .fill(Color(hex: petState.config.auraColor) ?? .purple)
                                .frame(width: 4, height: 4)
                        } else {
                            Spacer().frame(height: 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white.opacity(0.05))
    }
}

// MARK: - Home Tab
struct HomeTab: View {
    @ObservedObject var petState: PetState
    @ObservedObject var providerManager: ProviderManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Mood stat
                HStack(spacing: 12) {
                    miniStat(icon: "heart.fill", color: petState.moodColor,
                             value: "\(Int(petState.mood))%", label: "Happiness")
                }

                // Animation state card
                statCard {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(modeColor(petState.mode).opacity(0.2))
                                .frame(width: 36, height: 36)
                            Image(systemName: petState.mode.sfSymbol)
                                .foregroundColor(modeColor(petState.mode))
                                .font(.system(size: 16))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Agent Status")
                                .font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                            Text(modeLabel(petState.mode, substate: petState.busySubstate))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            // Live tool name from transcript
                            if let agy = providerManager.available.first(where: { $0.id == "antigravity" }) as? AntigravityProvider,
                               let tool = agy.currentTool {
                                Text(tool)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.4))
                                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                            }
                        }
                        Spacer()
                        // Pulsing indicator while busy
                        if petState.mode == .busy {
                            ThinkingDots()
                        }
                    }
                }

                // Step counter card (replaces token gauge)
                if let agy = providerManager.available.first(where: { $0.id == "antigravity" }) as? AntigravityProvider,
                   agy.isConnected {
                    StepCounterCard(provider: agy)
                    StaminaCard(provider: agy)
                }

                // Mood meter visual
                statCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Happiness", systemImage: "face.smiling")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(petState.moodColor)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(LinearGradient(colors: [petState.moodColor.opacity(0.7), petState.moodColor],
                                                         startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geo.size.width * petState.mood / 100, height: 8)
                                    .animation(.spring, value: petState.mood)
                            }
                        }
                        .frame(height: 8)
                        Text(petState.moodLabel)
                            .font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .padding(16)
        }
    }

    func statCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    func miniStat(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(color).font(.system(size: 18))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white)
            Text(label)
                .font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func modeColor(_ mode: PetMode) -> Color {
        Color(NSColor(hex: mode.accentColorHex) ?? .gray)
    }

    func modeLabel(_ mode: PetMode, substate: BusySubstate?) -> String {
        switch mode {
        case .idle:      return "Idle"
        case .busy:      return substate.map { $0.displayName + "…" } ?? "Working…"
        case .waiting:   return "Waiting for you…"
        case .completed: return "Task complete! 🎉"
        case .error:     return "Error!"
        }
    }
}

// MARK: - Thinking Dots Animation
struct ThinkingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 5, height: 5)
                    .scaleEffect(phase == i ? 1.4 : 0.8)
                    .animation(.easeInOut(duration: 0.4).delay(Double(i) * 0.15).repeatForever(), value: phase)
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

// MARK: - Step Counter Card
struct StepCounterCard: View {
    @ObservedObject var provider: AntigravityProvider

    private var stepColor: Color {
        switch provider.stepCount {
        case 0:       return .gray
        case 1..<10:  return .teal
        case 10..<30: return .cyan
        case 30..<60: return .yellow
        default:      return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Agent Activity", systemImage: "list.bullet.indent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(stepColor)
                Spacer()
                Text("\(provider.stepCount) steps")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.3), value: provider.stepCount)
            }

            // Step progress bar (capped at 100 steps visually)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            colors: [stepColor.opacity(0.7), stepColor],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(
                            width: geo.size.width * min(1.0, Double(provider.stepCount) / 100),
                            height: 8
                        )
                        .animation(.spring(duration: 0.4), value: provider.stepCount)
                }
            }
            .frame(height: 8)

            // Current tool or idle hint
            if let tool = provider.currentTool {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(stepColor.opacity(0.7))
                    Text(tool)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            } else {
                Text(provider.stepCount == 0 ? "Waiting for activity…" : "Turn complete")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(stepColor.opacity(0.3), lineWidth: 1))
    }
}



// MARK: - Stamina Card
struct StaminaCard: View {
    @ObservedObject var provider: AntigravityProvider
    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var stamina: Double { provider.currentStamina ?? 1.0 }

    private var staminaColor: Color {
        if stamina >= 0.6 { return Color(hue: 0.35, saturation: 0.8, brightness: 0.85) } // green
        if stamina >= 0.3 { return Color(hue: 0.09, saturation: 0.9, brightness: 0.95) } // orange
        return Color(hue: 0.0, saturation: 0.85, brightness: 0.9) // red
    }

    private var staminaIcon: String {
        if stamina >= 0.8 { return "bolt.fill" }
        if stamina >= 0.6 { return "bolt.fill" }
        if stamina >= 0.4 { return "bolt.badge.clock.fill" }
        if stamina > 0.0  { return "bolt.slash.fill" }
        return "bolt.slash.fill"
    }

    private var updatedLabel: String {
        guard let updated = provider.staminaLastUpdated else { return "Not yet fetched" }
        let diff = Int(now.timeIntervalSince(updated))
        if diff < 60 { return "Just now" }
        if diff < 3600 { return "\(diff / 60) min ago" }
        return "\(diff / 3600) hr ago"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                Label("Model Stamina", systemImage: staminaIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(staminaColor)
                Spacer()
                Text("\(Int(stamina * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(staminaColor)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.4), value: stamina)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            colors: [staminaColor.opacity(0.6), staminaColor],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * stamina, height: 8)
                        .animation(.spring(duration: 0.5), value: stamina)
                }
            }
            .frame(height: 8)

            // Model name + last updated
            HStack {
                if let model = provider.activeModelName {
                    Text(model)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
                Text(updatedLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(staminaColor.opacity(0.25), lineWidth: 1))
        .onReceive(timer) { now = $0 }
    }
}


// MARK: - Color extension for SwiftUI
extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let rgb = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8)  & 0xFF) / 255,
            blue:  Double(rgb         & 0xFF) / 255
        )
    }
}
