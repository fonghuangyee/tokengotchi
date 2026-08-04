import Foundation
import Combine

// MARK: - Agent Events
// Consolidated to 5 top-level modes. `.busy` carries an optional `BusySubMode`
// for providers (currently Antigravity) that report fine-grained tool phases.
public enum AgentEvent {
    case started(taskId: String)              // (kept for compatibility; providers may still emit)
    case busy(subMode: BusySubMode? = nil)  // agent is working
    case completed(taskId: String, totalTokens: Int)
    case failed(taskId: String, error: Error)
    case contextWarning(remainingTokens: Int) // informational only, no animation trigger
    case disconnected
    case idle
    case waiting
}

// MARK: - Provider Config
public struct ProviderConfig {
    public var apiKey: String
    public var baseURL: URL?
    public var modelName: String
    public var extraParams: [String: String]

    public init(apiKey: String = "", baseURL: URL? = nil, modelName: String = "", extraParams: [String: String] = [:]) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.modelName = modelName
        self.extraParams = extraParams
    }
}

// MARK: - LLM Provider Protocol
public protocol LLMProviderProtocol: AnyObject {
    var id: String { get }
    var name: String { get }
    var isConnected: Bool { get }
    /// True when the provider's CLI / data directory is present on this machine,
    /// enabling zero-config auto-detection.
    var isInstalledLocally: Bool { get }
    var eventPublisher: AnyPublisher<AgentEvent, Never> { get }

    func connect(config: ProviderConfig) async throws
    func disconnect()
}

// Default: providers that don't self-report installation are not auto-detected.
public extension LLMProviderProtocol {
    var isInstalledLocally: Bool { false }
}
