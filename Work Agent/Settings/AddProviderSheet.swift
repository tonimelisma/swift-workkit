//
//  AddProviderSheet.swift
//  Work Agent
//
//  Settings > Providers > Connect a Model.
//

import SwiftUI

struct AddProviderSheet: View {
    @Environment(ProviderStore.self) private var store
    @Environment(RegistryLoader.self) private var registryLoader
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var selectedProviderID: String?
    @State private var selectedModelID: String?
    @State private var apiKey = ""
    @State private var state: SubmitState = .editing

    private enum SubmitState: Equatable {
        case editing
        case verifying
        case failed(String)
    }

    private var providers: [RegistryProvider] {
        registryLoader.registry?.usableProviders ?? []
    }

    private var selectedProvider: RegistryProvider? {
        providers.first { $0.id == selectedProviderID }
    }

    // REQ: FR-053 — only tool-capable models are offered. A model that can't call tools
    // can't do agentic work, so listing it would be offering a trap.
    private var models: [RegistryModel] {
        selectedProvider?.toolCapableModels ?? []
    }

    private var canSubmit: Bool {
        selectedProvider != nil && selectedModelID != nil
            && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
            && state != .verifying
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Connect a Model")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Form {
                Section {
                    Picker("Service", selection: $selectedProviderID) {
                        Text("Choose…").tag(String?.none)
                        ForEach(providers) { provider in
                            Text(provider.name).tag(String?.some(provider.id))
                        }
                    }
                    .onChange(of: selectedProviderID) { _, _ in
                        selectedModelID = models.first?.id
                        state = .editing
                    }

                    Picker("Model", selection: $selectedModelID) {
                        Text("Choose…").tag(String?.none)
                        ForEach(models) { model in
                            Text(model.name).tag(String?.some(model.id))
                        }
                    }
                    .disabled(selectedProvider == nil)

                    if let model = models.first(where: { $0.id == selectedModelID }) {
                        LabeledContent("") {
                            Text(modelSummary(model))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    SecureField("Key", text: $apiKey)
                        .textContentType(.password)
                        .disabled(selectedProvider == nil)
                        .onChange(of: apiKey) { _, _ in state = .editing }

                    if let provider = selectedProvider, let doc = provider.doc {
                        LabeledContent("") {
                            Button("Where do I find this?") { openURL(doc) }
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }
                } footer: {
                    // REQ: FR-052 / product principle 5 — say plainly where the key goes.
                    Text("Your key is stored in your Mac's keychain and is only ever sent to \(selectedProvider?.name ?? "the service").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            if case .failed(let message) = state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action: submit) {
                    if state == .verifying {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Checking…")
                        }
                    } else {
                        Text("Connect")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
            .padding(12)
        }
        .frame(width: 480)
        .animation(.default, value: state)
        .task {
            if registryLoader.registry == nil { await registryLoader.loadLocal() }
        }
    }

    private func modelSummary(_ model: RegistryModel) -> String {
        var parts: [String] = []
        if let context = model.contextLimit {
            parts.append("\(context / 1000)K context")
        }
        if let input = model.inputCostPerMTok, let output = model.outputCostPerMTok {
            parts.append(String(format: "$%.2f in / $%.2f out per million tokens", input, output))
        }
        if model.reasoning { parts.append("reasoning") }
        return parts.joined(separator: " · ")
    }

    private func submit() {
        guard let provider = selectedProvider,
              let model = models.first(where: { $0.id == selectedModelID }) else { return }

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        state = .verifying

        Task {
            // REQ: FR-056 — verify against the live provider before claiming it works.
            // Storing an unverified key means the first real failure surfaces deep in an
            // agent run, where it's unattributable.
            let result = await ProviderVerifier().verify(provider: provider, key: key)

            switch result {
            case .verified:
                do {
                    try store.add(
                        ConfiguredProvider(
                            id: provider.id,
                            displayName: provider.name,
                            modelID: model.id,
                            modelName: model.name,
                            addedAt: Date()
                        ),
                        key: key
                    )
                    dismiss()
                } catch {
                    state = .failed(error.localizedDescription)
                }
            case .failed(let failure):
                state = .failed(failure.errorDescription ?? "That didn't work.")
            }
        }
    }
}
