import os
import ServiceManagement

final class LoginItemManager {
    static let shared = LoginItemManager()
    private let logger = Logger(subsystem: "com.johncioni.codefm", category: "LoginItem")

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        guard enabled != isEnabled else { return true }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            logger.error("Failed to \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)")
            return false
        }
    }
}
