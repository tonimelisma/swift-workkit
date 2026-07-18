import Foundation
import FoundationModels

@available(macOS 27.0, *)
public struct OpenAICompatibleLiveModel: LanguageModel {
    public typealias Executor = OpenAICompatibleLiveExecutor

    public let capabilities = LanguageModelCapabilities([.reasoning, .toolCalling])
    public let executorConfiguration: OpenAICompatibleLiveExecutor.Configuration

    public init(
        providerID: String,
        model: String,
        endpoint: URL,
        apiKey: String
    ) {
        executorConfiguration = .init(
            providerID: providerID,
            model: model,
            endpoint: endpoint,
            apiKey: apiKey
        )
    }
}

@available(macOS 27.0, *)
public struct OpenAICompatibleLiveExecutor: LanguageModelExecutor {
    public struct Configuration: Hashable, Sendable {
        public var providerID: String
        public var model: String
        public var endpoint: URL
        public var apiKey: String

        public init(providerID: String, model: String, endpoint: URL, apiKey: String) {
            self.providerID = providerID
            self.model = model
            self.endpoint = endpoint
            self.apiKey = apiKey
        }
    }

    public typealias Model = OpenAICompatibleLiveModel
    private let configuration: Configuration

    public init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: OpenAICompatibleLiveModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        providerDebug("\(configuration.providerID) request entries=\(request.transcript.count)")
        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": configuration.model,
            "messages": try ProviderRequestEncoder.openAIMessages(
                from: request.transcript,
                providerID: configuration.providerID
            ),
            "tools": try ProviderRequestEncoder.openAITools(request.enabledToolDefinitions),
            "stream": true,
            "stream_options": ["include_usage": true],
        ]
        if request.generationOptions.toolCallingMode == .required {
            body["tool_choice"] = "required"
        } else if request.generationOptions.toolCallingMode == .disallowed {
            body["tool_choice"] = "none"
        } else {
            body["tool_choice"] = "auto"
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        try ProviderRequestEncoder.validate(response: response, providerID: configuration.providerID)

        var parser = OpenAICompatibleStreamParser()
        var bridge = ProviderChannelBridge(
            requestID: request.id,
            providerID: configuration.providerID
        )
        var lineNumber = 0
        for try await line in bytes.lines {
            lineNumber += 1
            for event in try parser.consume(line, lineNumber: lineNumber) {
                providerDebug("\(configuration.providerID) event=\(event.kindName)")
                for channelEvent in bridge.channelEvents(for: event) {
                    await channel.send(channelEvent)
                }
            }
        }
    }
}

@available(macOS 27.0, *)
public struct AnthropicLiveModel: LanguageModel {
    public typealias Executor = AnthropicLiveExecutor

    public let capabilities = LanguageModelCapabilities([.reasoning, .toolCalling])
    public let executorConfiguration: AnthropicLiveExecutor.Configuration

    public init(model: String, apiKey: String) {
        executorConfiguration = .init(model: model, apiKey: apiKey)
    }
}

@available(macOS 27.0, *)
public struct AnthropicLiveExecutor: LanguageModelExecutor {
    public struct Configuration: Hashable, Sendable {
        public var model: String
        public var apiKey: String

        public init(model: String, apiKey: String) {
            self.model = model
            self.apiKey = apiKey
        }
    }

    public typealias Model = AnthropicLiveModel
    private let configuration: Configuration

    public init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: AnthropicLiveModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        providerDebug("anthropic request entries=\(request.transcript.count)")
        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoded = try ProviderRequestEncoder.anthropicMessages(from: request.transcript)
        var body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": request.generationOptions.maximumResponseTokens ?? 4_096,
            "messages": encoded.messages,
            "tools": try ProviderRequestEncoder.anthropicTools(request.enabledToolDefinitions),
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": "max"],
            "stream": true,
        ]
        if !encoded.system.isEmpty { body["system"] = encoded.system }
        if request.generationOptions.toolCallingMode == .required {
            body["tool_choice"] = ["type": "any"]
        } else if request.generationOptions.toolCallingMode == .disallowed {
            body["tools"] = []
        } else {
            body["tool_choice"] = ["type": "auto"]
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        try ProviderRequestEncoder.validate(response: response, providerID: "anthropic")

        var parser = AnthropicStreamParser()
        var bridge = ProviderChannelBridge(requestID: request.id, providerID: "anthropic")
        var lineNumber = 0
        for try await line in bytes.lines {
            lineNumber += 1
            for event in try parser.consume(line, lineNumber: lineNumber) {
                providerDebug("anthropic event=\(event.kindName)")
                for channelEvent in bridge.channelEvents(for: event) {
                    await channel.send(channelEvent)
                }
            }
        }
    }
}

@available(macOS 27.0, *)
public enum LiveProviderExecutorError: LocalizedError, Sendable {
    case invalidHTTPResponse(provider: String)
    case httpFailure(provider: String, status: Int)
    case unsupportedTranscriptSegment(entryID: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidHTTPResponse(provider):
            "\(provider) returned a non-HTTP response"
        case let .httpFailure(provider, status):
            "\(provider) returned HTTP \(status)"
        case let .unsupportedTranscriptSegment(entryID):
            "Cannot translate non-text transcript segment in entry \(entryID)"
        }
    }
}

@available(macOS 27.0, *)
private enum ProviderRequestEncoder {
    struct AnthropicRequest {
        var system: String
        var messages: [[String: Any]]
    }

    static func validate(response: URLResponse, providerID: String) throws {
        guard let response = response as? HTTPURLResponse else {
            throw LiveProviderExecutorError.invalidHTTPResponse(provider: providerID)
        }
        guard 200 ..< 300 ~= response.statusCode else {
            throw LiveProviderExecutorError.httpFailure(
                provider: providerID,
                status: response.statusCode
            )
        }
    }

    static func openAITools(_ definitions: [Transcript.ToolDefinition]) throws -> [[String: Any]] {
        try definitions.map { definition in
            [
                "type": "function",
                "function": [
                    "name": definition.name,
                    "description": definition.description,
                    "parameters": try schemaObject(definition.parameters),
                ],
            ]
        }
    }

    static func anthropicTools(_ definitions: [Transcript.ToolDefinition]) throws -> [[String: Any]] {
        try definitions.map { definition in
            [
                "name": definition.name,
                "description": definition.description,
                "input_schema": try schemaObject(definition.parameters),
            ]
        }
    }

    static func openAIMessages(
        from transcript: Transcript,
        providerID: String
    ) throws -> [[String: Any]] {
        var messages: [[String: Any]] = []
        var assistantContent = ""
        var assistantReasoning = ""
        var assistantMetadata: [String: Any] = [:]
        var assistantTools: [[String: Any]] = []

        func flushAssistant() {
            guard !assistantContent.isEmpty || !assistantReasoning.isEmpty || !assistantTools.isEmpty else {
                return
            }
            var message: [String: Any] = ["role": "assistant"]
            message["content"] = assistantContent.isEmpty ? NSNull() : assistantContent
            if !assistantReasoning.isEmpty { message["reasoning_content"] = assistantReasoning }
            if !assistantTools.isEmpty { message["tool_calls"] = assistantTools }
            for (key, value) in assistantMetadata { message[key] = value }
            messages.append(message)
            assistantContent = ""
            assistantReasoning = ""
            assistantMetadata = [:]
            assistantTools = []
        }

        for entry in transcript {
            switch entry {
            case let .instructions(instructions):
                flushAssistant()
                let text = try text(from: instructions.segments, entryID: instructions.id)
                if !text.isEmpty { messages.append(["role": "system", "content": text]) }

            case let .prompt(prompt):
                flushAssistant()
                messages.append([
                    "role": "user",
                    "content": try text(from: prompt.segments, entryID: prompt.id),
                ])

            case let .reasoning(reasoning):
                let owner = reasoning.metadata[TranscriptArchive.signatureProviderMetadataKey] as? String
                guard owner == providerID else { continue }
                assistantReasoning += try text(from: reasoning.segments, entryID: reasoning.id)
                if let signature = reasoning.metadata["google.thought_signature"] as? String {
                    assistantMetadata["extra_content"] = [
                        "google": ["thought_signature": signature],
                    ]
                }

            case let .toolCalls(calls):
                for call in calls {
                    var encoded: [String: Any] = [
                        "id": call.id,
                        "type": "function",
                        "function": [
                            "name": call.toolName,
                            "arguments": call.arguments.jsonString,
                        ],
                    ]
                    if let signature = call.metadata["google.thought_signature"] as? String {
                        encoded["extra_content"] = [
                            "google": ["thought_signature": signature],
                        ]
                    }
                    assistantTools.append(encoded)
                }

            case let .toolOutput(output):
                flushAssistant()
                messages.append([
                    "role": "tool",
                    "tool_call_id": output.id,
                    "content": try text(from: output.segments, entryID: output.id),
                ])

            case let .response(response):
                assistantContent += try text(from: response.segments, entryID: response.id)

            @unknown default:
                throw LiveProviderExecutorError.unsupportedTranscriptSegment(entryID: entry.id)
            }
        }
        flushAssistant()
        return messages
    }

    static func anthropicMessages(from transcript: Transcript) throws -> AnthropicRequest {
        var systemParts: [String] = []
        var messages: [[String: Any]] = []
        var assistantBlocks: [[String: Any]] = []

        func flushAssistant() {
            guard !assistantBlocks.isEmpty else { return }
            messages.append(["role": "assistant", "content": assistantBlocks])
            assistantBlocks = []
        }

        for entry in transcript {
            switch entry {
            case let .instructions(instructions):
                let value = try text(from: instructions.segments, entryID: instructions.id)
                if !value.isEmpty { systemParts.append(value) }

            case let .prompt(prompt):
                flushAssistant()
                messages.append([
                    "role": "user",
                    "content": try text(from: prompt.segments, entryID: prompt.id),
                ])

            case let .reasoning(reasoning):
                let owner = reasoning.metadata[TranscriptArchive.signatureProviderMetadataKey] as? String
                guard owner == "anthropic", let signatureData = reasoning.signature,
                      let signature = String(data: signatureData, encoding: .utf8) else { continue }
                assistantBlocks.append([
                    "type": "thinking",
                    "thinking": try text(from: reasoning.segments, entryID: reasoning.id),
                    "signature": signature,
                ])

            case let .toolCalls(calls):
                for call in calls {
                    assistantBlocks.append([
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.toolName,
                        "input": try JSONSerialization.jsonObject(with: Data(call.arguments.jsonString.utf8)),
                    ])
                }

            case let .toolOutput(output):
                flushAssistant()
                messages.append([
                    "role": "user",
                    "content": [[
                        "type": "tool_result",
                        "tool_use_id": output.id,
                        "content": try text(from: output.segments, entryID: output.id),
                    ]],
                ])

            case let .response(response):
                let value = try text(from: response.segments, entryID: response.id)
                if !value.isEmpty { assistantBlocks.append(["type": "text", "text": value]) }

            @unknown default:
                throw LiveProviderExecutorError.unsupportedTranscriptSegment(entryID: entry.id)
            }
        }
        flushAssistant()
        return AnthropicRequest(system: systemParts.joined(separator: "\n\n"), messages: messages)
    }

    private static func schemaObject(_ schema: GenerationSchema) throws -> Any {
        let data = try JSONEncoder().encode(schema)
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func text(from segments: [Transcript.Segment], entryID: String) throws -> String {
        try segments.map { segment in
            guard case let .text(text) = segment else {
                throw LiveProviderExecutorError.unsupportedTranscriptSegment(entryID: entryID)
            }
            return text.content
        }.joined()
    }
}

@available(macOS 27.0, *)
private struct ProviderChannelBridge {
    private let responseEntryID: String
    private let reasoningEntryID: String
    private let toolCallsEntryID: String
    private let providerID: String
    private var sawResponse = false
    private var sawReasoning = false
    private var sawToolCall = false

    init(requestID: UUID, providerID: String) {
        responseEntryID = "response-\(requestID.uuidString)"
        reasoningEntryID = "reasoning-\(requestID.uuidString)"
        toolCallsEntryID = "tool-calls-\(requestID.uuidString)"
        self.providerID = providerID
    }

    mutating func channelEvents(
        for event: ExecutorEvent
    ) -> [LanguageModelExecutorGenerationChannel.Event] {
        switch event {
        case let .response(text):
            guard !text.isEmpty else { return [] }
            sawResponse = true
            return [.response(
                entryID: responseEntryID,
                action: .appendText(text, tokenCount: estimatedTokens(text))
            )]

        case let .reasoning(text, signature, metadata):
            sawReasoning = true
            var events: [LanguageModelExecutorGenerationChannel.Event] = []
            if !text.isEmpty {
                events.append(.reasoning(
                    entryID: reasoningEntryID,
                    action: .appendText(text, tokenCount: estimatedTokens(text))
                ))
            }
            if let signature, !signature.isEmpty {
                events.append(.reasoning(
                    entryID: reasoningEntryID,
                    action: .updateSignature(Data(signature.utf8), tokenCount: 1)
                ))
            }
            var values: [String: any Sendable & Codable & Equatable] = metadata
            values[TranscriptArchive.signatureProviderMetadataKey] = providerID
            events.append(.reasoning(
                entryID: reasoningEntryID,
                action: .updateMetadata(values)
            ))
            return events

        case let .toolCall(_, id, name, argumentsFragment, metadata):
            sawToolCall = true
            var events: [LanguageModelExecutorGenerationChannel.Event] = [
                .toolCalls(
                    entryID: toolCallsEntryID,
                    action: .toolCall(
                        id: id,
                        name: name,
                        action: .appendArguments(
                            argumentsFragment,
                            tokenCount: argumentsFragment.isEmpty ? 0 : estimatedTokens(argumentsFragment)
                        )
                    )
                ),
            ]
            if !metadata.isEmpty {
                events.append(.toolCalls(
                    entryID: toolCallsEntryID,
                    action: .toolCall(
                        id: id,
                        name: name,
                        action: .updateMetadata(metadata)
                    )
                ))
            }
            return events

        case let .usage(input, output):
            let inputUsage = LanguageModelExecutorGenerationChannel.Usage.Input(
                totalTokenCount: input,
                cachedTokenCount: 0
            )
            let outputUsage = LanguageModelExecutorGenerationChannel.Usage.Output(
                totalTokenCount: output,
                reasoningTokenCount: 0
            )
            if sawToolCall {
                return [.toolCalls(
                    entryID: toolCallsEntryID,
                    action: .updateUsage(input: inputUsage, output: outputUsage)
                )]
            }
            if sawResponse {
                return [.response(
                    entryID: responseEntryID,
                    action: .updateUsage(input: inputUsage, output: outputUsage)
                )]
            }
            if sawReasoning {
                return [.reasoning(
                    entryID: reasoningEntryID,
                    action: .updateUsage(input: inputUsage, output: outputUsage)
                )]
            }
            return []

        case .finish:
            return []
        }
    }

    private func estimatedTokens(_ text: String) -> Int {
        max(1, text.utf8.count / 4)
    }
}

private extension ExecutorEvent {
    var kindName: String {
        switch self {
        case .response: "response"
        case .reasoning: "reasoning"
        case .toolCall: "toolCall"
        case .usage: "usage"
        case .finish: "finish"
        }
    }
}

private func providerDebug(_ message: String) {
    guard ProcessInfo.processInfo.environment["FOUNDATION_MODELS_POC_DEBUG"] == "1" else { return }
    FileHandle.standardError.write(Data("[provider-poc] \(message)\n".utf8))
}
