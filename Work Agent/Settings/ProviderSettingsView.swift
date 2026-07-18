//
//  ProviderSettingsView.swift
//  Work Agent
//
//  Settings > Providers.
//

import SwiftUI

struct ProviderSettingsView: View {
    @Environment(ProviderStore.self) private var store
    @Environment(RegistryLoader.self) private var registryLoader

    @State private var isAddingProvider = false
    @State private var providerToRemove: ConfiguredProvider?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.providers.isEmpty {
                emptyState
            } else {
                providerList
            }

            Divider()
            footer
        }
        .frame(width: 560, height: 380)
        .task { await registryLoader.loadLocal() }
        .sheet(isPresented: $isAddingProvider) {
            AddProviderSheet()
        }
        .alert("Remove provider?", isPresented: .constant(providerToRemove != nil)) {
            Button("Cancel", role: .cancel) { providerToRemove = nil }
            Button("Remove", role: .destructive) {
                if let provider = providerToRemove { remove(provider) }
                providerToRemove = nil
            }
        } message: {
            if let provider = providerToRemove {
                Text("\(provider.displayName) will be removed and its key deleted from your keychain.")
            }
        }
        .alert("Something went wrong",
               isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No models connected")
                .font(.title3.weight(.medium))
            Text("Work Agent needs a model to think with. Connect a service you already\npay for, and your key stays on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Connect a Model…") { isAddingProvider = true }
                .controlSize(.large)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var providerList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.providers) { provider in
                    ProviderRow(
                        provider: provider,
                        isActive: provider.id == store.activeProviderID,
                        onActivate: { store.setActive(provider) },
                        onRemove: { providerToRemove = provider }
                    )
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                isAddingProvider = true
            } label: {
                Label("Connect a Model", systemImage: "plus")
            }

            Spacer()

            registryStatus
        }
        .padding(12)
    }

    // REQ: FR-054 — the user can see whether the model list is current, and refresh it.
    // Deliberately quiet: this matters to almost nobody, so it whispers.
    @ViewBuilder
    private var registryStatus: some View {
        HStack(spacing: 6) {
            if registryLoader.isRefreshing {
                ProgressView().controlSize(.small)
            }
            if let source = registryLoader.source {
                Text(source.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Check for New Models") {
                Task { await registryLoader.refresh() }
            }
            .buttonStyle(.link)
            .font(.caption)
            .disabled(registryLoader.isRefreshing)
        }
        .help(registryLoader.refreshError ?? "The list of available models.")
    }

    private func remove(_ provider: ConfiguredProvider) {
        do {
            try store.remove(provider)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProviderRow: View {
    let provider: ConfiguredProvider
    let isActive: Bool
    let onActivate: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.5))
                .font(.system(size: 15))
                .onTapGesture(perform: onActivate)
                .help(isActive ? "Currently in use" : "Use this one")

            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                    .font(.body.weight(.medium))
                Text(provider.modelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Text("In use")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .opacity(isHovering ? 1 : 0)
            .help("Remove")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onActivate)
    }
}
