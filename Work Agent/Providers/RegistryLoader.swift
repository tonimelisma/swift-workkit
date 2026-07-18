//
//  RegistryLoader.swift
//  Work Agent
//
//  Loads the models.dev registry: bundled snapshot first, network as a refresh.
//

import Foundation
import Observation
import OSLog

private let log = Logger(subsystem: "net.melisma.Work-Agent", category: "registry")

/// Where the registry in memory came from.
nonisolated enum RegistrySource: Equatable {
    case bundled
    case cached(Date)
    case network(Date)

    var label: String {
        switch self {
        case .bundled: "Built in"
        case .cached: "Downloaded"
        case .network: "Up to date"
        }
    }
}

/// Loads and refreshes the provider registry.
///
/// The ordering here is the whole point: the bundled snapshot is the source of truth at
/// launch, and the network only ever improves on it.
// REQ: FR-054 — if the registry can't be fetched, fall back to the bundled snapshot and
// stay fully usable.
// REQ: NFR-008 — nothing here blocks launch. Loading is explicit and async; the app
// starts without it.
@MainActor
@Observable
final class RegistryLoader {
    private(set) var registry: ModelRegistry?
    private(set) var source: RegistrySource?
    /// Set when a *refresh* failed. Never fatal — the registry stays whatever it was.
    private(set) var refreshError: String?
    private(set) var isRefreshing = false

    private let remoteURL = URL(string: "https://models.dev/api.json")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private var cacheURL: URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true) else { return nil }
        let appDir = dir.appendingPathComponent("Work Agent", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("models-dev-cache.json")
    }

    /// Load the best registry we already have on disk. Never touches the network.
    ///
    /// Cache wins over bundle when both exist and the cache is newer — but a cache that
    /// fails to decode falls through to the bundle rather than leaving us empty.
    func loadLocal() async {
        if let cacheURL,
           let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let modified = attributes[.modificationDate] as? Date,
           let parsed = await Self.decode(contentsOf: cacheURL) {
            registry = parsed
            source = .cached(modified)
            log.info("Registry loaded from cache: \(parsed.providers.count) providers")
            return
        }

        guard let bundled = Bundle.main.url(forResource: "models-dev-snapshot", withExtension: "json"),
              let parsed = await Self.decode(contentsOf: bundled) else {
            log.error("Bundled registry snapshot missing or unreadable")
            return
        }
        registry = parsed
        source = .bundled
        log.info("Registry loaded from bundle: \(parsed.providers.count) providers")
    }

    /// Fetch a fresh registry. Failure leaves the current registry untouched.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshError = nil
        defer { isRefreshing = false }

        do {
            let (data, response) = try await session.data(from: remoteURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let parsed = try await Self.decode(data)

            // A syntactically valid but empty registry is a regression, not a refresh.
            guard !parsed.providers.isEmpty else { throw URLError(.cannotParseResponse) }

            registry = parsed
            source = .network(Date())
            if let cacheURL { try? data.write(to: cacheURL, options: .atomic) }
            log.info("Registry refreshed: \(parsed.providers.count) providers")
        } catch {
            // REQ: FR-054 — a failed refresh is a non-event. Whatever we had, we keep.
            refreshError = error.localizedDescription
            log.warning("Registry refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // 3 MB of JSON has no business on the main thread.
    private static func decode(_ data: Data) async throws -> ModelRegistry {
        try await Task.detached(priority: .userInitiated) {
            try JSONDecoder().decode(ModelRegistry.self, from: data)
        }.value
    }

    private static func decode(contentsOf url: URL) async -> ModelRegistry? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? await decode(data)
    }
}
