import Foundation
import Combine

// MARK: - Provider Manager
// Zero-config multi-provider monitor.
//
// There is no manual provider selection and no API key. On launch the manager
// connects to every provider whose CLI / data directory is present on this
// machine (`isInstalledLocally`), merges their event streams, and surfaces
// whichever agent is actively working as `activeProvider`. When agents are
// idle it falls back to the most-recently-active one.
@MainActor
final class ProviderManager: ObservableObject {

    // All candidate providers. Only those with `isInstalledLocally == true`
    // are actually connected and monitored.
    let available: [any LLMProviderProtocol] = [
        AntigravityProvider(),
        ClaudeProvider(),
        ZedProvider(),
        OpenAIProvider(),
        AnthropicProvider(),
        OllamaProvider()
    ]

    /// The provider currently driving the pet (the one most recently active).
    @Published private(set) var activeProviderId: String = ""

    /// Retained for API compatibility; zero-config providers ignore it.
    @Published var configs: [String: ProviderConfig] = [:]

    // Merged event stream from all monitored providers
    private let eventSubject = PassthroughSubject<AgentEvent, Never>()
    var eventPublisher: AnyPublisher<AgentEvent, Never> { eventSubject.eraseToAnyPublisher() }

    private var providerCancellables: [String: AnyCancellable] = [:]
    private(set) var activeProvider: (any LLMProviderProtocol)?

    // MARK: Connect (auto-detect & monitor all installed)
    /// Connects to every locally-installed provider and bridges their events.
    /// The pet automatically follows whichever agent is doing work.
    func connectDefault() async {
        let installed = available.filter { $0.isInstalledLocally }
        let targets = installed.isEmpty ? [available[0]] : installed

        for provider in targets {
            bridgeEvents(from: provider)
            let config = configs[provider.id] ?? ProviderConfig()
            try? await provider.connect(config: config)

            // Seed the active provider so the UI has something to show.
            if activeProviderId.isEmpty {
                setActiveProvider(provider)
            }
        }
    }

    /// Disconnects every provider (called on app terminate).
    func disconnectAll() {
        available.forEach { $0.disconnect() }
    }

    // MARK: Private
    private func setActiveProvider(_ provider: any LLMProviderProtocol) {
        activeProviderId = provider.id
        activeProvider = provider
    }

    private func bridgeEvents(from provider: any LLMProviderProtocol) {
        providerCancellables[provider.id] = provider.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self else { return }

                // Follow whichever agent is actively working. Any "doing work"
                // event switches the pet's focus to that provider.
                if Self.isActivityEvent(event), self.activeProviderId != provider.id {
                    self.setActiveProvider(provider)
                }
                // Keep the pointer valid if the active provider disconnects.
                if case .disconnected = event, self.activeProviderId == provider.id {
                    // Re-seed to any other connected provider.
                    if let fallback = self.available.first(where: {
                        $0.isConnected && $0.id != provider.id
                    }) {
                        self.setActiveProvider(fallback)
                    }
                }

                self.eventSubject.send(event)
            }
    }

    /// Events that indicate an agent is actively doing work (worth following).
    private static func isActivityEvent(_ event: AgentEvent) -> Bool {
        switch event {
        case .started, .busy, .waiting, .completed, .failed:
            return true
        case .idle, .disconnected, .contextWarning:
            return false
        }
    }

    var activeProviderName: String {
        available.first(where: { $0.id == activeProviderId })?.name ?? "None"
    }
}
