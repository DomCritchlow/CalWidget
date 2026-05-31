import Foundation

#if canImport(Sparkle)
import Sparkle

final class UpdaterCoordinator {
    private let controller: SPUStandardUpdaterController?

    init() {
        // Sparkle refuses to start without an SUFeedURL in Info.plist, so skip
        // initialization entirely in Debug builds (where we leave it unset).
        let hasFeed = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?.isEmpty == false
        controller = hasFeed
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
#else
final class UpdaterCoordinator {
    var canCheckForUpdates: Bool { false }
    func checkForUpdates() {}
}
#endif
