import SwiftUI

// MARK: - Navigation Destinations
enum PetDashboardDestination: Hashable {
    case preview(String) // pet name
    case prompt(String?)
    case jsonEditor
}

// MARK: - Pet Dashboard (Popover)
struct PetDashboardView: View {
    @ObservedObject var petState: PetState
    @ObservedObject var providerManager: ProviderManager
    @StateObject private var petManager = PetManager.shared

    @State private var selectedTab: DashboardTab = .home

    enum DashboardTab: String, CaseIterable {
        case home = "house.fill"
        case settings = "gearshape.fill"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Content
                    Group {
                        switch selectedTab {
                        case .home:
                            HomeTab(petState: petState, providerManager: providerManager, petManager: petManager)
                        case .settings:
                            SettingsTab(providerManager: providerManager, petState: petState)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Tab bar
                    tabBar
                }
            }
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
        .frame(width: 340, height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Background
    var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.purple.opacity(0.25),
                Color.black.opacity(0.92),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
                            .foregroundColor(
                                selectedTab == tab
                                    ? Color.purple
                                    : .white.opacity(0.4))
                        if selectedTab == tab {
                            Circle()
                                .fill(Color.purple)
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
    @ObservedObject var petManager: PetManager

    private var antigravity: AntigravityProvider? {
        providerManager.available.first(where: { $0.id == "antigravity" }) as? AntigravityProvider
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Pet Carousel Header
                petCarousel
                
                // Live activity — mode + tool + steps consolidated into one card
                liveActivityCard

                // Model stamina (only relevant when the bridge is connected)
                if let agy = antigravity, agy.isConnected {
                    StaminaCard(provider: agy)
                }
            }
            .padding(16)
        }
    }
    
    // MARK: - Pet Carousel
    private var petCarousel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your Pets")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                // Provider badge moved here since headerBar is gone
                HStack(spacing: 4) {
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Create New Button
                    NavigationLink(value: PetDashboardDestination.prompt(nil)) {
                        VStack {
                            ZStack {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4]))
                                    .frame(width: 50, height: 50)
                                Image(systemName: "plus")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            Text("New Pet")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .frame(width: 60)
                    }
                    .buttonStyle(.plain)
                    
                    // Available Pets
                    ForEach(petManager.availablePets, id: \.name) { pet in
                        let isActive = petManager.activePet.name == pet.name
                        
                                                Group {
                            if isActive {
                                NavigationLink(value: PetDashboardDestination.preview(pet.name)) {
                                    petCard(pet: pet, isActive: isActive)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    petManager.activePet = pet
                                } label: {
                                    petCard(pet: pet, isActive: isActive)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Live Activity
    // Consolidates the old "Agent Status" card and "Step Counter" card so the
    // current tool name and step count each appear exactly once.
    private var liveActivityCard: some View {
        let mode = petState.mode
        let accent = modeColor(mode)
        let steps = antigravity?.stepCount ?? 0
        let sColor = stepColor(steps)
        let tool = antigravity?.currentTool

        return statCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: mode.sfSymbol)
                            .foregroundColor(accent)
                            .font(.system(size: 18))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(modeLabel(mode, subMode: petState.busySubMode))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        if let tool = tool {
                            Text(tool)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                        } else {
                            Text(steps == 0 ? "No active tool" : "Turn complete")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    Spacer()
                    if mode == .busy {
                        ThinkingDots()
                    }
                }

                // Step progress footer (only once there's activity to show)
                if steps > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 9))
                            .foregroundColor(sColor.opacity(0.7))
                        Text("\(steps) steps")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.3), value: steps)
                        Spacer()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [sColor.opacity(0.6), sColor],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: geo.size.width * min(1.0, Double(steps) / 100), height: 4
                                )
                                .animation(.spring(duration: 0.4), value: steps)
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
    }

    // MARK: - Helpers
        @ViewBuilder
    private func petCard(pet: PetFile, isActive: Bool) -> some View {
        VStack {
            ZStack {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 50, height: 50)
                if isActive {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: 54, height: 54)
                }
                
                // Mini preview
                TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 1.0 / 24.0)) { context in
                    Image(
                        nsImage: OffscreenPetRenderer.renderFrame(
                            clipID: pet.toAnimationClips(forContext: "pet").first?.id ?? "",
                            pet: pet,
                            time: context.date.timeIntervalSince1970,
                            contextName: "pet",
                            targetSize: NSSize(width: 64, height: 64)
                        )
                    )
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                }
            }
            
            Text(pet.name)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(isActive ? .white : .white.opacity(0.6))
                .lineLimit(1)
        }
        .frame(width: 60)
        .opacity(isActive ? 1.0 : 0.7)
    }

    func statCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    func modeColor(_ mode: PetMode) -> Color {
        Color(NSColor(hex: mode.accentColorHex) ?? .gray)
    }

    func modeLabel(_ mode: PetMode, subMode: BusySubMode?) -> String {
        switch mode {
        case .idle: return "Idle"
        case .busy: return subMode.map { $0.displayName + "…" } ?? "Working…"
        case .waiting: return "Waiting for you…"
        case .completed: return "Task complete! 🎉"
        case .error: return "Error!"
        }
    }

    func stepColor(_ count: Int) -> Color {
        switch count {
        case 0: return .gray
        case 1..<10: return .teal
        case 10..<30: return .cyan
        case 30..<60: return .yellow
        default: return .orange
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

// MARK: - Stamina Card
struct StaminaCard: View {
    @ObservedObject var provider: AntigravityProvider
    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var stamina: Double { provider.currentStamina ?? 1.0 }

    private var staminaColor: Color {
        if stamina >= 0.6 { return Color(hue: 0.35, saturation: 0.8, brightness: 0.85) }  // green
        if stamina >= 0.3 { return Color(hue: 0.09, saturation: 0.9, brightness: 0.95) }  // orange
        return Color(hue: 0.0, saturation: 0.85, brightness: 0.9)  // red
    }

    private var staminaIcon: String {
        if stamina >= 0.8 { return "bolt.fill" }
        if stamina >= 0.6 { return "bolt.fill" }
        if stamina >= 0.4 { return "bolt.badge.clock.fill" }
        if stamina > 0.0 { return "bolt.slash.fill" }
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
                        .fill(
                            LinearGradient(
                                colors: [staminaColor.opacity(0.6), staminaColor],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
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
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(staminaColor.opacity(0.25), lineWidth: 1)
        )
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
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
