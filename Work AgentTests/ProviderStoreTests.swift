//
//  ProviderStoreTests.swift
//  Work AgentTests
//

import Foundation
import Testing
@testable import Work_Agent

/// A UserDefaults suite per test, so tests don't leak into each other or into the app.
private func isolatedDefaults() -> UserDefaults {
    let name = "test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private func sample(_ id: String, model: String = "m1") -> ConfiguredProvider {
    ConfiguredProvider(id: id, displayName: id.capitalized, modelID: model,
                       modelName: model.uppercased(), addedAt: Date())
}

@Suite("Configured provider persistence", .serialized)
@MainActor
struct ProviderStoreTests {

    @Test("FR-052: a configured provider carries no credential into preferences")
    func credentialNeverPersistedInDefaults() throws {
        let defaults = isolatedDefaults()
        let store = ProviderStore(defaults: defaults)
        let provider = sample("anthropic")

        try store.add(provider, key: "sk-ant-SUPER-SECRET")
        defer { try? store.remove(provider) }

        // Whatever shape the encoding takes, the secret must not appear in it.
        let data = try #require(defaults.data(forKey: "configuredProviders"))
        let asString = String(decoding: data, as: UTF8.self)
        #expect(!asString.contains("SUPER-SECRET"))
        #expect(!asString.contains("sk-ant"))
    }

    @Test("FR-050 / FR-011: configured providers survive a restart")
    func providersPersistAcrossInstances() throws {
        let defaults = isolatedDefaults()
        let provider = sample("anthropic")

        let first = ProviderStore(defaults: defaults)
        try first.add(provider, key: "k")
        defer { try? first.remove(provider) }

        // A fresh store over the same defaults is what a relaunch looks like.
        let second = ProviderStore(defaults: defaults)
        #expect(second.providers.count == 1)
        #expect(second.providers.first?.id == "anthropic")
        #expect(second.activeProviderID == "anthropic")
    }

    @Test("FR-055: the first provider added becomes active")
    func firstProviderBecomesActive() throws {
        let store = ProviderStore(defaults: isolatedDefaults())
        let first = sample("anthropic")
        let second = sample("openai")
        defer { try? store.remove(first); try? store.remove(second) }

        try store.add(first, key: "k")
        #expect(store.activeProviderID == "anthropic")

        // Adding a second must not silently steal the active slot.
        try store.add(second, key: "k")
        #expect(store.activeProviderID == "anthropic")
    }

    @Test("FR-055: the user can change which provider is active")
    func setActive() throws {
        let store = ProviderStore(defaults: isolatedDefaults())
        let anthropic = sample("anthropic")
        let openai = sample("openai")
        defer { try? store.remove(anthropic); try? store.remove(openai) }

        try store.add(anthropic, key: "k")
        try store.add(openai, key: "k")
        store.setActive(openai)

        #expect(store.activeProviderID == "openai")
        #expect(store.activeProvider?.displayName == "Openai")
    }

    @Test("FR-057: removing a provider deletes its key from the keychain")
    func removeDeletesCredential() throws {
        let store = ProviderStore(defaults: isolatedDefaults())
        let provider = sample("anthropic")

        try store.add(provider, key: "sk-ant-test")
        #expect(try Keychain.get(account: provider.keychainAccount) == "sk-ant-test")

        try store.remove(provider)
        #expect(try Keychain.get(account: provider.keychainAccount) == nil)
        #expect(store.providers.isEmpty)
    }

    @Test("FR-055: removing the active provider promotes another rather than leaving none")
    func removingActivePromotesAnother() throws {
        let store = ProviderStore(defaults: isolatedDefaults())
        let anthropic = sample("anthropic")
        let openai = sample("openai")
        defer { try? store.remove(anthropic); try? store.remove(openai) }

        try store.add(anthropic, key: "k")
        try store.add(openai, key: "k")
        #expect(store.activeProviderID == "anthropic")

        try store.remove(anthropic)
        // A dangling activeProviderID would read as "connected" while nothing works.
        #expect(store.activeProviderID == "openai")
        #expect(store.activeProvider != nil)
    }

    @Test("FR-050: re-adding a provider replaces it rather than duplicating")
    func addReplacesExisting() throws {
        let store = ProviderStore(defaults: isolatedDefaults())
        let provider = sample("anthropic", model: "old-model")
        defer { try? store.remove(provider) }

        try store.add(provider, key: "k1")
        try store.add(sample("anthropic", model: "new-model"), key: "k2")

        #expect(store.providers.count == 1)
        #expect(store.providers.first?.modelID == "new-model")
        #expect(try Keychain.get(account: provider.keychainAccount) == "k2")
    }
}

@Suite("Keychain", .serialized)
struct KeychainTests {
    private let account = "test.provider.\(UUID().uuidString)"

    @Test("FR-052: a secret round-trips through the keychain")
    func roundTrip() throws {
        defer { try? Keychain.delete(account: account) }

        try Keychain.set("hunter2", account: account)
        #expect(try Keychain.get(account: account) == "hunter2")
    }

    @Test("FR-052: storing again replaces rather than duplicating")
    func overwrite() throws {
        defer { try? Keychain.delete(account: account) }

        try Keychain.set("first", account: account)
        try Keychain.set("second", account: account)
        #expect(try Keychain.get(account: account) == "second")
    }

    @Test("FR-052: reading a missing account returns nil rather than throwing")
    func missingIsNil() throws {
        #expect(try Keychain.get(account: "definitely.not.stored.\(UUID())") == nil)
    }

    @Test("FR-057: deleting is idempotent")
    func deleteIsIdempotent() throws {
        try Keychain.set("x", account: account)
        try Keychain.delete(account: account)
        // Removing a provider twice, or removing one whose key was already gone, must
        // not throw — the user's intent is satisfied either way.
        try Keychain.delete(account: account)
        #expect(try Keychain.get(account: account) == nil)
    }
}
