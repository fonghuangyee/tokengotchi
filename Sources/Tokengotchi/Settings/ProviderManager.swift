import Foundation
import Combine

// MARK: - Provider Manager
// Manages the active LLM provider and broadcasts its events.
@MainActor
final class ProviderManager: ObservableObject {

    // All available providers
    let available: [any LLMProviderProtocol] = [
        AntigravityProvider(),
        OpenAIProvider(),
        AnthropicProvider(),
        OllamaProvider()
    ]

    @Published var activeProviderId: String = "antigravity" {
        didSet { switchProvider(to: activeProviderId) }
    }

    @Published var configs: [String: ProviderConfig] = [
        "antigravity": ProviderConfig(baseURL: URL(string: "http://127.0.0.1:7432"))
    ]

    // Merged event stream from the active provider
    private let eventSubject = PassthroughSubject<AgentEvent, Never>()
    var eventPublisher: AnyPublisher<AgentEvent, Never> { eventSubject.eraseToAnyPublisher() }

    private var providerCancellable: AnyCancellable?
    private(set) var activeProvider: (any LLMProviderProtocol)?

    // MARK: Connect Default
    func connectDefault() async {
        guard let provider = available.first(where: { $0.id == activeProviderId }) else { return }
        activeProvider = provider
        bridgeEvents(from: provider)
        let config = configs[provider.id] ?? ProviderConfig()
        try? await provider.connect(config: config)
    }

    // MARK: Switch Provider
    func switchProvider(to id: String) {
        activeProvider?.disconnect()
        guard let provider = available.first(where: { $0.id == id }) else { return }
        activeProvider = provider
        bridgeEvents(from: provider)
        let config = configs[id] ?? ProviderConfig()
        Task { try? await provider.connect(config: config) }
    }

    func disconnectAll() {
        available.forEach { $0.disconnect() }
    }

    // MARK: Private
    private func bridgeEvents(from provider: any LLMProviderProtocol) {
        providerCancellable = provider.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.eventSubject.send(event)
            }
    }

    var activeProviderName: String {
        available.first(where: { $0.id == activeProviderId })?.name ?? "None"
    }
}
