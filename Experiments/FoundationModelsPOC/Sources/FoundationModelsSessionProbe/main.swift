import Foundation
import FoundationModels
import FoundationModelsPOC

@available(macOS 27.0, *)
private struct ScriptedLanguageModel: LanguageModel {
    typealias Executor = ScriptedExecutor

    let capabilities = LanguageModelCapabilities([
        .reasoning, .toolCalling, .guidedGeneration,
    ])
    let executorConfiguration = ScriptedExecutor.Configuration()
}

@available(macOS 27.0, *)
private struct ScriptedExecutor: LanguageModelExecutor {
    struct Configuration: Hashable, Sendable {}

    typealias Model = ScriptedLanguageModel

    init(configuration: Configuration) throws {}

    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: ScriptedLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let hasToolOutput = request.transcript.contains { entry in
            if case .toolOutput = entry { return true }
            return false
        }

        if hasToolOutput {
            let response: LanguageModelExecutorGenerationChannel.Event = .response(
                entryID: "response-2",
                action: .appendText("The tool completed successfully.", tokenCount: 5)
            )
            await channel.send(response)
            let usage: LanguageModelExecutorGenerationChannel.Event = .response(
                entryID: "response-2",
                action: .updateUsage(
                    input: .init(totalTokenCount: 31, cachedTokenCount: 7),
                    output: .init(totalTokenCount: 5, reasoningTokenCount: 0)
                )
            )
            await channel.send(usage)
            return
        }

        let reasoning: LanguageModelExecutorGenerationChannel.Event = .reasoning(
            entryID: "reasoning-1",
            action: .appendText("I should inspect the fixture.", tokenCount: 6)
        )
        await channel.send(reasoning)
        let signature: LanguageModelExecutorGenerationChannel.Event = .reasoning(
            entryID: "reasoning-1",
            action: .updateSignature(Data("scripted-signature".utf8), tokenCount: 1)
        )
        await channel.send(signature)
        let metadata: LanguageModelExecutorGenerationChannel.Event = .reasoning(
            entryID: "reasoning-1",
            action: .updateMetadata([
                "scripted.signature": "scripted-signature",
                TranscriptArchive.signatureProviderMetadataKey: "scripted",
            ])
        )
        await channel.send(metadata)

        let toolCall: LanguageModelExecutorGenerationChannel.Event = .toolCalls(
            entryID: "tool-calls-1",
            action: .toolCall(
                id: "call-1",
                name: "read_fixture",
                action: .appendArguments(#"{"path":"answer.txt"}"#, tokenCount: 5)
            )
        )
        await channel.send(toolCall)
    }
}

private struct ProbeResult: Codable {
    var status: String
    var response: String
    var requestCount: Int
    var toolCallCount: Int
    var toolOutputCount: Int
    var reasoningCount: Int
    var reasoningSignatureRoundTripped: Bool
    var transcriptArchiveRoundTripped: Bool
    var totalTokenCount: Int
}

private struct LiveProbeResult: Codable {
    var status: String
    var provider: String
    var responsePresent: Bool
    var toolCallCount: Int
    var toolOutputCount: Int
    var providerStatePresent: Bool
    var totalTokenCount: Int
}

private struct LiveSwitchResult: Codable {
    var status: String
    var sourceProvider: String
    var destinationProvider: String
    var sourceCompleted: Bool
    var foreignStateRemoved: Bool
    var destinationCompleted: Bool
}

@available(macOS 27.0, *)
private func run(fixtureRoot: URL) async throws -> ProbeResult {
    let tool = FoundationModelsReadFixtureTool(root: fixtureRoot)
    let session = LanguageModelSession(
        model: ScriptedLanguageModel(),
        tools: [tool],
        instructions: "Use the fixture tool before answering."
    )
    let response = try await session.respond(
        to: "Read answer.txt and confirm completion.",
        options: GenerationOptions(toolCallingMode: .required)
    )

    let transcript = session.transcript
    let archive = TranscriptArchive(transcript: transcript)
    let encodedArchive = try archive.encoded()
    let decoded = try TranscriptArchive.decode(encodedArchive)
    let reencodedArchive = try decoded.encoded()

    var toolCallCount = 0
    var toolOutputCount = 0
    var reasoningCount = 0
    var signatureRoundTripped = false
    var responseCount = 0
    for entry in transcript {
        switch entry {
        case let .toolCalls(calls):
            toolCallCount += calls.count
        case .toolOutput:
            toolOutputCount += 1
        case let .reasoning(reasoning):
            reasoningCount += 1
            signatureRoundTripped = reasoning.signature == Data("scripted-signature".utf8)
        case .response:
            responseCount += 1
        case .instructions, .prompt:
            break
        @unknown default:
            break
        }
    }

    return ProbeResult(
        status: "passed",
        response: response.content,
        requestCount: responseCount + toolCallCount,
        toolCallCount: toolCallCount,
        toolOutputCount: toolOutputCount,
        reasoningCount: reasoningCount,
        reasoningSignatureRoundTripped: signatureRoundTripped,
        transcriptArchiveRoundTripped: encodedArchive == reencodedArchive,
        totalTokenCount: session.usage.totalTokenCount
    )
}

@available(macOS 27.0, *)
private func runLive<Model: LanguageModel>(
    model: Model,
    provider: String,
    fixtureRoot: URL
) async throws -> LiveProbeResult {
    let session = LanguageModelSession(
        model: model,
        tools: [FoundationModelsReadFixtureTool(root: fixtureRoot)],
        instructions: "Use read_fixture with path answer.txt before answering."
    )
    let response = try await session.respond(
        to: "Determine whether the fixture answer can be trusted. You must inspect it first.",
        options: GenerationOptions(toolCallingMode: .allowed)
    )

    let result = LiveProbeResult(
        status: "passed",
        provider: provider,
        responsePresent: !response.content.isEmpty,
        toolCallCount: session.transcript.toolCallCount,
        toolOutputCount: session.transcript.toolOutputCount,
        providerStatePresent: session.transcript.hasProviderState(provider),
        totalTokenCount: session.usage.totalTokenCount
    )
    guard result.responsePresent, result.toolCallCount == 1, result.toolOutputCount == 1,
          result.providerStatePresent else {
        throw LiveProbeArgumentError.failedPredicates(provider)
    }
    return result
}

@available(macOS 27.0, *)
private func runLiveProvider(_ provider: String, fixtureRoot: URL) async throws -> LiveProbeResult {
    let environment = ProcessInfo.processInfo.environment
    switch provider {
    case "deepseek":
        return try await runLive(
            model: OpenAICompatibleLiveModel(
                providerID: "deepseek",
                model: "deepseek-v4-pro",
                endpoint: URL(string: "https://api.deepseek.com/chat/completions")!,
                apiKey: try requiredKey("DEEPSEEK_API_KEY", environment: environment)
            ),
            provider: provider,
            fixtureRoot: fixtureRoot
        )
    case "google":
        return try await runLive(
            model: OpenAICompatibleLiveModel(
                providerID: "google",
                model: "gemini-3.5-flash",
                endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!,
                apiKey: try requiredKey("GOOGLE_API_KEY", environment: environment)
            ),
            provider: provider,
            fixtureRoot: fixtureRoot
        )
    case "anthropic":
        return try await runLive(
            model: AnthropicLiveModel(
                model: "claude-sonnet-5",
                apiKey: try requiredKey("ANTHROPIC_API_KEY", environment: environment)
            ),
            provider: provider,
            fixtureRoot: fixtureRoot
        )
    default:
        throw LiveProbeArgumentError.unsupportedProvider(provider)
    }
}

@available(macOS 27.0, *)
private func runDeepSeekToAnthropicSwitch(fixtureRoot: URL) async throws -> LiveSwitchResult {
    let environment = ProcessInfo.processInfo.environment
    let source = LanguageModelSession(
        model: OpenAICompatibleLiveModel(
            providerID: "deepseek",
            model: "deepseek-v4-pro",
            endpoint: URL(string: "https://api.deepseek.com/chat/completions")!,
            apiKey: try requiredKey("DEEPSEEK_API_KEY", environment: environment)
        ),
        tools: [FoundationModelsReadFixtureTool(root: fixtureRoot)],
        instructions: "Use read_fixture with path answer.txt before answering."
    )
    let sourceResponse = try await source.respond(
        to: "Inspect the fixture before answering.",
        options: GenerationOptions(toolCallingMode: .allowed)
    )

    let replay = try TranscriptArchive(transcript: source.transcript).replay(to: "anthropic")
    let foreignStateRemoved = !replay.transcript.hasProviderState("deepseek")
    let destination = LanguageModelSession(
        model: AnthropicLiveModel(
            model: "claude-sonnet-5",
            apiKey: try requiredKey("ANTHROPIC_API_KEY", environment: environment)
        ),
        tools: [FoundationModelsReadFixtureTool(root: fixtureRoot)],
        transcript: replay.transcript
    )
    let destinationResponse = try await destination.respond(
        to: "Confirm in one sentence that you can continue this task after the provider switch.",
        options: GenerationOptions(toolCallingMode: .disallowed)
    )

    let result = LiveSwitchResult(
        status: "passed",
        sourceProvider: "deepseek",
        destinationProvider: "anthropic",
        sourceCompleted: !sourceResponse.content.isEmpty && source.transcript.toolOutputCount > 0,
        foreignStateRemoved: foreignStateRemoved,
        destinationCompleted: !destinationResponse.content.isEmpty
    )
    guard result.sourceCompleted, result.foreignStateRemoved, result.destinationCompleted else {
        throw LiveProbeArgumentError.failedPredicates("deepseek -> anthropic")
    }
    return result
}

private enum LiveProbeArgumentError: LocalizedError {
    case missingKey(String)
    case unsupportedProvider(String)
    case unsupportedSwitch(String, String)
    case failedPredicates(String)

    var errorDescription: String? {
        switch self {
        case let .missingKey(name): "Missing required environment variable \(name)"
        case let .unsupportedProvider(provider): "Unsupported provider \(provider)"
        case let .unsupportedSwitch(source, destination):
            "Unsupported live switch \(source) -> \(destination)"
        case let .failedPredicates(probe): "Live probe predicates failed for \(probe)"
        }
    }
}

private func requiredKey(_ name: String, environment: [String: String]) throws -> String {
    guard let value = environment[name], !value.isEmpty else {
        throw LiveProbeArgumentError.missingKey(name)
    }
    return value
}

@available(macOS 27.0, *)
private extension Transcript {
    var toolCallCount: Int {
        reduce(into: 0) { count, entry in
            if case let .toolCalls(calls) = entry { count += calls.count }
        }
    }

    var toolOutputCount: Int {
        reduce(into: 0) { count, entry in
            if case .toolOutput = entry { count += 1 }
        }
    }

    func hasProviderState(_ provider: String) -> Bool {
        contains { entry in
            switch entry {
            case let .reasoning(reasoning):
                let owner = reasoning.metadata[TranscriptArchive.signatureProviderMetadataKey] as? String
                return owner == provider
                    && (reasoning.signature != nil || !reasoning.segments.isEmpty)
            case let .toolCalls(calls):
                return calls.contains { call in
                    call.metadata.keys.contains { $0.hasPrefix("\(provider).") }
                }
            case let .prompt(prompt):
                return prompt.metadata.keys.contains { $0.hasPrefix("\(provider).") }
            case let .response(response):
                return response.metadata.keys.contains { $0.hasPrefix("\(provider).") }
            case .instructions, .toolOutput:
                return false
            @unknown default:
                return false
            }
        }
    }
}

private func printJSON<Value: Encodable>(_ value: Value) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--help" {
    print("""
    Usage:
      foundation-models-session-probe --fixture-root <directory>
      foundation-models-session-probe --live-provider <deepseek|google|anthropic> --fixture-root <directory>
      foundation-models-session-probe --live-switch deepseek anthropic --fixture-root <directory>
    """)
    exit(EXIT_SUCCESS)
}

let fixtureFlag = arguments.firstIndex(of: "--fixture-root")
guard let fixtureFlag, arguments.indices.contains(fixtureFlag + 1) else {
    print("Missing --fixture-root <directory>")
    exit(EXIT_FAILURE)
}
let fixtureRoot = URL(fileURLWithPath: arguments[fixtureFlag + 1], isDirectory: true)

if arguments.isEmpty {
    print("Use --help for usage.")
    exit(arguments.first == "--help" ? EXIT_SUCCESS : EXIT_FAILURE)
}

guard #available(macOS 27.0, *) else {
    print("Foundation Models provider execution requires macOS 27 or later.")
    exit(EXIT_FAILURE)
}

do {
    if arguments.first == "--live-provider", arguments.count > 1 {
        try printJSON(try await runLiveProvider(arguments[1], fixtureRoot: fixtureRoot))
    } else if arguments.first == "--live-switch", arguments.count > 2 {
        guard arguments[1] == "deepseek", arguments[2] == "anthropic" else {
            throw LiveProbeArgumentError.unsupportedSwitch(arguments[1], arguments[2])
        }
        try printJSON(try await runDeepSeekToAnthropicSwitch(fixtureRoot: fixtureRoot))
    } else if arguments.first == "--fixture-root" {
        try printJSON(try await run(fixtureRoot: fixtureRoot))
    } else {
        throw LiveProbeArgumentError.unsupportedProvider(arguments.first ?? "")
    }
} catch {
    let payload = ["status": "failed", "error": String(reflecting: error)]
    let encoded = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    print(String(decoding: encoded, as: UTF8.self))
    exit(EXIT_FAILURE)
}
