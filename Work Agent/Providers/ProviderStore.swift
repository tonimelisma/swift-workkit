//
//  ProviderStore.swift
//  Work Agent
//
//  The user's configured providers. Metadata only — secrets live in the Keychain.
//

import Foundation
import Observation

/// A provider the user has configured.
///
// REQ: FR-052 — no credential field, deliberately. This type is written to preferences,
// so a secret here would be a secret on disk in plain text. The key lives in the
// Keychain under `keychainAccount`.
nonisolated struct ConfiguredProvider: Codable, Identifiable, Hashable {
    /// models.dev provider id, e.g. "anthropic".
    let id: String
    /// Display name captured at configure time, so the UI still reads correctly if the
    /// registry later drops or renames the provider.
    var displayName: String
    /// models.dev model id, e.g. "claude-opus-4-5".
    var modelID: String
    var modelName: String
    var addedAt: Date

    var keychainAccount: String { "provider.\(id)" }
}

/// Persists which providers are configured and which one is active.
@MainActor
@Observable
final class ProviderStore {
    private(set) var providers: [ConfiguredProvider] = []
    private(set) var activeProviderID: String?

    private let defaults: UserDefaults
    private let providersKey = "configuredProviders"
    private let activeKey = "activeProviderID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var activeProvider: ConfiguredProvider? {
        providers.first { $0.id == activeProviderID }
    }

    private func load() {
        if let data = defaults.data(forKey: providersKey),
           let decoded = try? JSONDecoder().decode([ConfiguredProvider].self, from: data) {
            providers = decoded
        }
        activeProviderID = defaults.string(forKey: activeKey)
        reconcileActive()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(providers) {
            defaults.set(data, forKey: providersKey)
        }
        defaults.set(activeProviderID, forKey: activeKey)
    }

    /// Add or replace a provider, storing its key in the Keychain.
    // REQ: FR-050 — the user can configure one or more providers.
    func add(_ provider: ConfiguredProvider, key: String) throws {
        try Keychain.set(key, account: provider.keychainAccount)
        providers.removeAll { $0.id == provider.id }
        providers.append(provider)
        providers.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        // First provider added becomes active — otherwise the user configures a provider
        // and the app still claims none is set up, which reads as a bug.
        if activeProviderID == nil { activeProviderID = provider.id }
        save()
    }

    /// Remove a provider and delete its credential.
    // REQ: FR-057 — removing a provider deletes its stored credential.
    func remove(_ provider: ConfiguredProvider) throws {
        try Keychain.delete(account: provider.keychainAccount)
        providers.removeAll { $0.id == provider.id }
        reconcileActive()
        save()
    }

    // REQ: FR-055 — the user designates which provider and model is used.
    func setActive(_ provider: ConfiguredProvider) {
        guard providers.contains(where: { $0.id == provider.id }) else { return }
        activeProviderID = provider.id
        save()
    }

    func setModel(_ model: RegistryModel, for provider: ConfiguredProvider) {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        providers[index].modelID = model.id
        providers[index].modelName = model.name
        save()
    }

    /// Never leave `activeProviderID` pointing at a provider that isn't configured.
    private func reconcileActive() {
        if let active = activeProviderID, !providers.contains(where: { $0.id == active }) {
            activeProviderID = providers.first?.id
        } else if activeProviderID == nil {
            activeProviderID = providers.first?.id
        }
    }
}
