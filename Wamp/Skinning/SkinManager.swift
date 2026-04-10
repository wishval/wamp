// Wamp/Skinning/SkinManager.swift
// Atomic skin lifecycle. See spec §2.3 and §12 (Known pitfalls).

import AppKit
import Combine

final class SkinManager: ObservableObject {
    static let shared = SkinManager()

    /// Observers should subscribe to this. After the publisher fires, both
    /// `WinampTheme.provider` and `currentSkin` are guaranteed to be the new value.
    @Published private(set) var currentSkin: SkinProvider = BuiltInSkin()

    private init() {}

    /// Loads a skin off the main thread, then transitions on main.
    func loadSkin(from url: URL) async throws {
        let model = try await SkinParser().parse(contentsOf: url)
        let skin = WinampClassicSkin(model: model)
        await MainActor.run {
            self.transition(to: skin)
        }
    }

    /// Synchronous load for app startup. Run before window creation to avoid flicker.
    func loadSkinSync(from url: URL) throws {
        let model = try SkinParser().parseSync(contentsOf: url)
        let skin = WinampClassicSkin(model: model)
        transition(to: skin)
    }

    /// Restores BuiltInSkin.
    func unloadSkin() {
        transition(to: BuiltInSkin())
    }

    /// Atomic transition: WinampTheme.provider is updated FIRST so that any code path
    /// that checks `WinampTheme.skinIsActive` or calls `WinampTheme.sprite(...)` from
    /// inside an observer sink sees consistent state. The first attempt
    /// (feature/skin-support) had this in the wrong order and caused render races.
    private func transition(to newSkin: SkinProvider) {
        WinampTheme.provider = newSkin
        self.currentSkin = newSkin   // fires @Published — observers run AFTER provider is set
    }
}
