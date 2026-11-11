import Foundation
import ServiceManagement

// MARK: - 开机自启
//
// macOS 13+ 用 SMAppService.mainApp，这是官方方案，
// 取代了旧的 SMLoginItemSetEnabled + helper bundle 那一套。

enum AppLoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func register() throws {
        // 已经启用时再调一次会抛错，先判断
        guard SMAppService.mainApp.status != .enabled else { return }
        try SMAppService.mainApp.register()
    }

    static func unregister() throws {
        guard SMAppService.mainApp.status == .enabled else { return }
        try SMAppService.mainApp.unregister()
    }
}

// MARK: - 设置页用的薄封装

enum LaunchAtLogin {
    /// 失败不打断用户：设置里的开关状态仍然保存，下次启动会再试一次。
    /// 多数失败是因为从 Xcode 直接 run 而不是装在 /Applications。
    static func set(_ enabled: Bool) {
        do {
            if enabled { try AppLoginItem.register() }
            else { try AppLoginItem.unregister() }
        } catch {
            NSLog("TIESit: login item \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
    }
}