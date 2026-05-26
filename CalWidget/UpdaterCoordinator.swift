import Foundation

#if canImport(Sparkle)
import Sparkle

final class UpdaterCoordinator: NSObject, SPUUpdaterDelegate {
    private let controller: SPUStandardUpdaterController

    override init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
        controller.updater.delegate = self
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
#else
final class UpdaterCoordinator {
    var canCheckForUpdates: Bool { false }
    func checkForUpdates() {}
}
#endif
