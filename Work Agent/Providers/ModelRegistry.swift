//
//  ModelRegistry.swift
//  Work Agent
//
//  Types for the models.dev registry (ADR-0005).
//

import Foundation

// REQ: NFR-007 — models.dev publishes no schema version and gives no stability
// guarantee, so every container here decodes leniently: an entry that fails is
// skipped, never fatal. A registry change must degrade us, not break us.

/// A provider as published by models.dev.
nonisolated struct RegistryProvider: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Conventional environment variable for this provider's key, e.g. `ANTHROPIC_API_KEY`.
    let env: [String]
    let doc: URL?
    /// Base URL. Absent for anthropic/openai/google — see `ProviderCatalog`.
    let api: URL?
    let models: [RegistryModel]

    var toolCapableModels: [RegistryModel] {
        models.filter(\.toolCall)
    }
}

/// A model as published by models.dev.
nonisolated struct RegistryModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let family: String?
    /// Whether the model can call tools. Universal in the registry (0 of 5,666 omit it)
    /// and the field we care about most — agentic work is impossible without it.
    let toolCall: Bool
    let reasoning: Bool
    let attachment: Bool
    let releaseDate: String?
    let contextLimit: Int?
    let outputLimit: Int?
    let inputCostPerMTok: Double?
    let outputCostPerMTok: Double?
}

/// The whole registry: providers keyed by id at the top level.
nonisolated struct ModelRegistry: Sendable {
    let providers: [RegistryProvider]

    func provider(id: String) -> RegistryProvider? {
        providers.first { $0.id == id }
    }

    /// Providers we can actually reach: one with no base URL, from the registry or our
    /// own catalog, is unusable no matter what else it advertises.
    var usableProviders: [RegistryProvider] {
        providers.filter { ProviderCatalog.baseURL(for: $0) != nil && !$0.toolCapableModels.isEmpty }
    }
}

// MARK: - Decoding

nonisolated private struct DynamicKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

nonisolated extension ModelRegistry: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var decoded: [RegistryProvider] = []
        for key in container.allKeys {
            // REQ: NFR-007 — skip, don't throw.
            guard let provider = try? container.decode(RegistryProvider.self, forKey: key) else {
                continue
            }
            decoded.append(provider)
        }
        providers = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

nonisolated extension RegistryProvider: Decodable {
    private enum Keys: String, CodingKey {
        case id, name, env, doc, api, models
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        env = (try? c.decode([String].self, forKey: .env)) ?? []
        doc = (try? c.decode(String.self, forKey: .doc)).flatMap(URL.init(string:))
        api = (try? c.decode(String.self, forKey: .api)).flatMap(URL.init(string:))

        // Models are a dict keyed by model id; same leniency as the top level.
        var decoded: [RegistryModel] = []
        if let modelsContainer = try? c.nestedContainer(keyedBy: DynamicKey.self, forKey: .models) {
            for key in modelsContainer.allKeys {
                guard let model = try? modelsContainer.decode(RegistryModel.self, forKey: key) else {
                    continue
                }
                decoded.append(model)
            }
        }
        models = decoded.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
    }
}

nonisolated extension RegistryModel: Decodable {
    private enum Keys: String, CodingKey {
        case id, name, family, attachment, reasoning, temperature
        case toolCall = "tool_call"
        case releaseDate = "release_date"
        case limit, cost
    }
    private enum LimitKeys: String, CodingKey { case context, output }
    private enum CostKeys: String, CodingKey { case input, output }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        family = try? c.decode(String.self, forKey: .family)
        // Absent tool_call means we cannot claim the model calls tools. Default false:
        // a false negative hides a usable model, a false positive strands the user in a
        // broken agent loop.
        toolCall = (try? c.decode(Bool.self, forKey: .toolCall)) ?? false
        reasoning = (try? c.decode(Bool.self, forKey: .reasoning)) ?? false
        attachment = (try? c.decode(Bool.self, forKey: .attachment)) ?? false
        releaseDate = try? c.decode(String.self, forKey: .releaseDate)

        let limits = try? c.nestedContainer(keyedBy: LimitKeys.self, forKey: .limit)
        contextLimit = try? limits?.decode(Int.self, forKey: .context)
        outputLimit = try? limits?.decode(Int.self, forKey: .output)

        let costs = try? c.nestedContainer(keyedBy: CostKeys.self, forKey: .cost)
        inputCostPerMTok = try? costs?.decode(Double.self, forKey: .input)
        outputCostPerMTok = try? costs?.decode(Double.self, forKey: .output)
    }
}
