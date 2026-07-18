//
//  ContentView.swift
//  Work Agent
//
//  Created by Toni Melisma on 7/15/26.
//

import SwiftUI

/// Placeholder main window. The product lives here eventually (roadmap increment 4+);
/// for now it exists to show whether a model is connected and to point at Settings.
struct ContentView: View {
    @Environment(ProviderStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 12) {
            if let active = store.activeProvider {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                Text("Connected to \(active.displayName)")
                    .font(.title3.weight(.medium))
                Text(active.modelName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 34))
                    .foregroundStyle(.tertiary)
                Text("No model connected")
                    .font(.title3.weight(.medium))
                Text("Work Agent needs a model to think with.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Open Settings…") { openSettings() }
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(minWidth: 420, minHeight: 300)
    }
}
