import AppKit
import Carbon
import ServiceManagement
import MacMuralCore

final class NativeLoginItemService: LoginItemService {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }

    static var isInstalled: Bool {
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let directories = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask) +
                          FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)
        return directories.contains { directory in
            let directory = directory.resolvingSymlinksInPath().standardizedFileURL
            if bundle.path.hasPrefix(directory.path + "/") { return true }
            // Also recognize an Applications symlink to a Homebrew-managed bundle.
            let installed = directory.appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)
            return FileManager.default.fileExists(atPath: installed.path) &&
                   installed.resolvingSymlinksInPath().standardizedFileURL == bundle
        }
    }

    static var isLoginLaunch: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication),
              let reason = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue else { return false }
        return reason == AEKeyword(keyAELaunchedAsLogInItem) || reason == AEKeyword(keyAELaunchedAsServiceItem)
    }
    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
