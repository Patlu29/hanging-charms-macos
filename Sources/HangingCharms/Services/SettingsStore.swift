import Foundation
import Observation
import HangingCharmsCore

/// The single owner of ``AppSettings``. Every write goes through ``settings``'s setter,
/// which persists once and tells the listeners, so there is no `save()` to forget.
@MainActor
@Observable
final class SettingsStore {
    static let key = "HangingCharms.settings.v1"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var listeners: [(AppSettings, AppSettings) -> Void] = []
    @ObservationIgnored private var storage: AppSettings

    var settings: AppSettings {
        get {
            access(keyPath: \.settings)
            return storage
        }
        set {
            guard newValue != storage else { return }
            let old = storage
            withMutation(keyPath: \.settings) { storage = newValue }
            defaults.set(newValue.encoded(), forKey: Self.key)
            for listener in listeners { listener(old, newValue) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.storage = AppSettings.decode(defaults.data(forKey: Self.key))
    }

    func update(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        settings = copy
    }

    /// Called with (old, new) after every change.
    func observe(_ listener: @escaping (AppSettings, AppSettings) -> Void) {
        listeners.append(listener)
    }

    func reset() {
        settings = AppSettings()
    }
}
