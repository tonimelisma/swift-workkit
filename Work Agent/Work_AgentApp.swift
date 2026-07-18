//
//  Work_AgentApp.swift
//  Work Agent
//
//  Created by Toni Melisma on 7/15/26.
//

import SwiftUI

@main
struct Work_AgentApp: App {
    // Owned here so the Settings scene and the main window observe the same state.
    @State private var providerStore = ProviderStore()
    @State private var registryLoader = RegistryLoader()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(providerStore)
                .environment(registryLoader)
        }

        // REQ: FR-050 — the idiomatic macOS home for this: ⌘, and the app menu.
        Settings {
            ProviderSettingsView()
                .environment(providerStore)
                .environment(registryLoader)
        }
    }
}
