//
//  ProviderCatalogTests.swift
//  Work AgentTests
//

import Foundation
import Testing
@testable import Work_Agent

private func provider(id: String, api: String? = nil) throws -> RegistryProvider {
    let apiField = api.map { "\"api\": \"\($0)\"," } ?? ""
    let json = """
    {"p": {"id": "\(id)", "name": "\(id)", "env": [], \(apiField)
           "models": {"m": {"id": "m", "name": "M", "tool_call": true}}}}
    """
    let registry = try JSONDecoder().decode(ModelRegistry.self, from: Data(json.utf8))
    return try #require(registry.providers.first)
}

@Suite("Provider catalog")
struct ProviderCatalogTests {

    @Test("FR-051: the registry's own base URL wins over our fallback")
    func registryURLWins() throws {
        // If models.dev ever publishes one for a major, it should take precedence
        // without us editing code.
        let p = try provider(id: "anthropic", api: "https://custom.example/v1")
        #expect(ProviderCatalog.baseURL(for: p)?.absoluteString == "https://custom.example/v1")
    }

    @Test("FR-051: the majors fall back to our hardcoded base URLs")
    func fallbackURLsForMajors() throws {
        #expect(try ProviderCatalog.baseURL(for: provider(id: "anthropic"))?.host() == "api.anthropic.com")
        #expect(try ProviderCatalog.baseURL(for: provider(id: "openai"))?.host() == "api.openai.com")
        #expect(try ProviderCatalog.baseURL(for: provider(id: "google"))?.host() == "generativelanguage.googleapis.com")
    }

    @Test("FR-051: a provider with neither a registry URL nor a fallback is unreachable")
    func unknownProviderHasNoURL() throws {
        #expect(try ProviderCatalog.baseURL(for: provider(id: "some-obscure-host")) == nil)
    }

    @Test("FR-056: Anthropic verification sends x-api-key and the version header")
    func anthropicVerificationRequest() throws {
        let request = try #require(
            ProviderCatalog.verificationRequest(for: try provider(id: "anthropic"), key: "sk-ant-test")
        )

        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        // Omitting this yields a 400, which we'd surface to the user as "bad key".
        #expect(request.value(forHTTPHeaderField: "anthropic-version") != nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.url?.path() == "/v1/models")
    }

    @Test("FR-056: OpenAI-style providers use bearer auth")
    func bearerVerificationRequest() throws {
        let request = try #require(
            ProviderCatalog.verificationRequest(for: try provider(id: "openai"), key: "sk-test")
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
    }

    @Test("FR-056: an unknown but reachable provider defaults to bearer")
    func unknownProviderDefaultsToBearer() throws {
        // 142 of 166 registry providers publish a base URL and are OpenAI-compatible,
        // so bearer is the right default for anything we haven't named.
        let request = try #require(
            ProviderCatalog.verificationRequest(
                for: try provider(id: "mystery", api: "https://api.mystery.example/v1"),
                key: "k"
            )
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer k")
    }

    @Test("FR-056: an unreachable provider yields no verification request")
    func noRequestWithoutBaseURL() throws {
        #expect(ProviderCatalog.verificationRequest(for: try provider(id: "nowhere"), key: "k") == nil)
    }

    @Test("FR-052: no credential is ever placed in a URL")
    func credentialsNeverInURLs() throws {
        // Google documents ?key= — a credential in a query string leaks into URL logs,
        // proxy logs, and crash reports. Header only.
        for id in ["anthropic", "openai", "google"] {
            let request = try #require(
                ProviderCatalog.verificationRequest(for: try provider(id: id), key: "SUPER-SECRET-KEY")
            )
            let url = try #require(request.url?.absoluteString)
            #expect(!url.contains("SUPER-SECRET-KEY"), "\(id) leaked the key into the URL: \(url)")
        }
    }

    @Test("FR-056: Google authenticates by header")
    func googleUsesHeader() throws {
        let request = try #require(
            ProviderCatalog.verificationRequest(for: try provider(id: "google"), key: "g-key")
        )
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "g-key")
    }
}
