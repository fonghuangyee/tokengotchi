import Foundation
import Combine

// MARK: - OpenAI Provider (Stub — extend with actual streaming API)
final class OpenAIProvider: LLMProviderProtocol {
    let id = "openai"
    let name = "OpenAI"
    @Published private(set) var isConnected: Bool = false
    private let subject = PassthroughSubject<AgentEvent, Never>()
    var eventPublisher: AnyPublisher<AgentEvent, Never> { subject.eraseToAnyPublisher() }
    private var apiKey: String = ""
    private var streamTask: Task<Void, Never>?

    func connect(config: ProviderConfig) async throws {
        apiKey = config.apiKey
        isConnected = true
    }

    func disconnect() {
        streamTask?.cancel()
        isConnected = false
        subject.send(.disconnected)
    }

    // Hook into SSE stream from OpenAI — emit events matching AgentEvent
    func sendMessage(_ message: String, model: String = "gpt-4o") {
        let taskId = UUID().uuidString
        subject.send(.started(taskId: taskId))
        subject.send(.busy(substate: .thinking))
        streamTask = Task {
            // TODO: Stream from https://api.openai.com/v1/chat/completions
            // Parse SSE chunks and emit .streaming(tokens:) per chunk
            // On done, emit .completed
        }
    }
}

// MARK: - Anthropic Provider (Stub)
final class AnthropicProvider: LLMProviderProtocol {
    let id = "anthropic"
    let name = "Anthropic (Claude)"
    @Published private(set) var isConnected: Bool = false
    private let subject = PassthroughSubject<AgentEvent, Never>()
    var eventPublisher: AnyPublisher<AgentEvent, Never> { subject.eraseToAnyPublisher() }

    func connect(config: ProviderConfig) async throws {
        isConnected = true
    }

    func disconnect() {
        isConnected = false
        subject.send(.disconnected)
    }
}

// MARK: - Ollama Provider (Stub — local models via Ollama REST API)
final class OllamaProvider: LLMProviderProtocol {
    let id = "ollama"
    let name = "Ollama (Local)"
    @Published private(set) var isConnected: Bool = false
    private let subject = PassthroughSubject<AgentEvent, Never>()
    var eventPublisher: AnyPublisher<AgentEvent, Never> { subject.eraseToAnyPublisher() }
    private var baseURL: URL = URL(string: "http://127.0.0.1:11434")!

    func connect(config: ProviderConfig) async throws {
        baseURL = config.baseURL ?? baseURL
        isConnected = true
    }

    func disconnect() {
        isConnected = false
        subject.send(.disconnected)
    }
}
