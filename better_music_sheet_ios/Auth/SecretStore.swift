import Foundation

/// Where small durable secrets live. Abstracted so the identity layer can be
/// exercised without touching a real Keychain — on a Mac, an unentitled test
/// process hitting the login keychain can block on a system prompt, which is
/// not something a test suite should ever depend on.
nonisolated protocol SecretStore: Sendable {
    func string(for key: String) -> String?
    func set(_ value: String?, for key: String)
}

nonisolated struct KeychainStore: SecretStore {
    init() {}
    func string(for key: String) -> String? { Keychain.string(for: key) }
    func set(_ value: String?, for key: String) { Keychain.set(value, for: key) }
}

/// For tests, and for any context where persistence is neither available nor
/// wanted.
nonisolated final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    init(_ initial: [String: String] = [:]) { values = initial }

    func string(for key: String) -> String? { lock.withLock { values[key] } }

    func set(_ value: String?, for key: String) {
        lock.withLock { values[key] = value }
    }
}
