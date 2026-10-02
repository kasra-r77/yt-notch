import Foundation
import AppKit
import Observation
import Sparkle

/// Sparkle starts only when the app carries the public update key (`SUPublicEDKey`), so
/// nothing half-works before the owner has made the keys (CONTRIBUTING, "Releases and updates").
@MainActor
@Observable
final class Updater: NSObject, SPUUpdaterDelegate {
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    private(set) var updateWaiting = false
    private(set) var lastChecked: Date?

    override init() {
        super.init()
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        lastChecked = controller.updater.lastUpdateCheckDate
    }

    var isEnabled: Bool { controller != nil }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in self.updateWaiting = true }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.updateWaiting = false }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        Task { @MainActor in self.lastChecked = self.controller?.updater.lastUpdateCheckDate }
    }
}
