import SwiftUI
import AppKit
import UserNotifications

// MARK: - 入口
//
// 菜单栏常驻应用。LSUIElement = true 让它不进 Dock、不占 Cmd+Tab。
// 没有主窗口，点菜单栏图标弹 NSPopover。

@main
struct TIESitApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // 空 Scene：窗口全部由 AppDelegate 手动管理。
        // 配置项类型叫 SitSettings，不会和 SwiftUI.Settings 撞名，但仍写全名更清楚
        SwiftUI.Settings { EmptyView() }
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    private var engine: SitEngine!
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var alertController: AlertWindowController!
    private var statsWindow: NSWindow?
    private var statusTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine = SitEngine()
        engine.onAlert = { [weak self] in self?.presentAlert() }
        engine.onCurfewExpired = { [weak self] in
            self?.alertController.close()
            self?.refreshStatusItem()
        }
        engine.onRestEnd = { [weak self] in
            Chiptune.shared.restDone()
            self?.notify(title: "休息结束",
                         body: "可以回到座位了。下一次在座计时已开始。")
        }

        Chiptune.shared.enabled = engine.settings.soundOn

        setupStatusItem()
        setupPopover()

        alertController = AlertWindowController(engine: engine)

        // 长按完成 → 引擎已记录解锁，这里负责把遮罩收掉并刷新菜单栏。
        // 用 NotificationCenter 而不是直接引用：遮罩窗口和 AppDelegate 互相持有会成环。
        NotificationCenter.default.addObserver(
            forName: .tiesitAlertReleased, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissAlert() }
        }

        NotificationCenter.default.addObserver(
            forName: .tiesitShiftEnded, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismissAlert()
                self?.notify(title: "今天辛苦了",
                             body: "今天的计时已结束，明天再出发。", sound: false)
            }
        }

        // 恢复退出前仍未解除的警报；此时窗口控制器和回调均已准备好。
        if engine.state == .alert || engine.state == .endOfDay { presentAlert() }
        refreshStatusItem()
        requestNotificationPermission()

        if engine.settings.launchAtLogin {
            LaunchAtLogin.set(true)
        }

        // 菜单栏图标上的倒计时，每秒刷新
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatusItem() }
        }
        RunLoop.main.add(statusTimer!, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.persist()
        statusTimer?.invalidate()
    }

    // 关掉最后一个窗口不退出：这是菜单栏 App
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = StatusIcon.makeTIE()
        button.imagePosition = .imageLeading
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// 左键弹驾驶舱，右键出测试菜单
    @objc private func statusItemClicked() {
        let isRight = NSApp.currentEvent?.type == .rightMouseUp
        if isRight { showTestMenu() } else { togglePopover() }
    }

    private func showTestMenu() {
        let menu = NSMenu()

        let alertItem = NSMenuItem(title: "预览休息提醒", action: #selector(triggerAlertNow), keyEquivalent: "")
        alertItem.target = self
        alertItem.isEnabled = engine.state == .sitting
        menu.addItem(alertItem)

        let curfewItem = NSMenuItem(title: "预览下班提醒", action: #selector(triggerCurfewNow), keyEquivalent: "")
        curfewItem.target = self
        curfewItem.isEnabled = engine.state == .sitting
        menu.addItem(curfewItem)

        menu.addItem(.separator())

        let stats = NSMenuItem(title: "统计…", action: #selector(openStatsFromMenu), keyEquivalent: "")
        stats.target = self
        menu.addItem(stats)

        let setup = NSMenuItem(title: "设置…", action: #selector(openSettingsFromMenu), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)

        // 用 popUpMenu 而不是挂 statusItem.menu，否则左键也会弹菜单
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: statusItem.button?.bounds.height ?? 0),
                   in: statusItem.button)
    }

    @objc private func triggerAlertNow() { engine.debugTriggerAlert() }
    @objc private func triggerCurfewNow() { engine.debugTriggerCurfew() }
    @objc private func openStatsFromMenu() { openStats() }
    @objc private func openSettingsFromMenu() {
        // 等右键菜单结束跟踪后再展开 transient 浮层。
        DispatchQueue.main.async { [weak self] in self?.openSettings() }
    }

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }

        switch engine.state {
        case .sitting:
            button.title = " " + Fmt.clock(Int(engine.remaining))
            button.image = StatusIcon.makeTIE()
            button.contentTintColor = nil
        case .resting:
            button.title = " " + Fmt.clock(Int(engine.restRemaining))
            button.image = StatusIcon.makeTIE(color: .systemGreen)
            button.contentTintColor = nil
        case .alert:
            button.title = " REST"
            button.image = StatusIcon.makeTIE(color: NSColor(red: 0.65, green: 0.80, blue: 0.72, alpha: 1))
            button.contentTintColor = nil
        case .endOfDay:
            button.title = " OFF"
            button.image = StatusIcon.makeTIE(color: .systemYellow)
            button.contentTintColor = nil
        case .offDuty:
            button.title = " DONE"
            button.image = StatusIcon.makeTIE(color: .systemGreen)
            button.contentTintColor = nil
        }

        if let issue = engine.storageIssue {
            button.title += " !"
            button.toolTip = issue
        } else {
            button.toolTip = "TIE-SIT · 起身休息提醒"
        }
        // 统一用小号等宽字体，宽度稳定不跳动
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false        // 像素风不要平滑缩放
        popover.delegate = self
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        Chiptune.shared.click()

        let root = CockpitView(
            engine: engine,
            onOpenStats: { [weak self] in
                self?.popover.performClose(nil)
                self?.openStats()
            },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        presentPopover(root, size: CockpitView.panelSize)
    }

    private func presentPopover<Content: View>(_ content: Content, size: NSSize) {
        guard let button = statusItem.button else { return }
        popover.contentViewController = NSHostingController(rootView: content)
        popover.contentSize = size
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: 警报

    private func presentAlert() {
        popover.performClose(nil)

        // 全屏休息站已经足够醒目，不再叠加通知音和催促通知。
        alertController.show { }
    }

    func dismissAlert() {
        alertController.close()
        refreshStatusItem()
    }

    // MARK: 子窗口

    private func openStats() {
        if let w = statsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(
            rootView: StatsView(engine: engine, onClose: { [weak self] in
                self?.statsWindow?.close()
                self?.statsWindow = nil
            })
        )
        let w = NSWindow(contentViewController: host)
        w.title = "TIE-SIT · 统计"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        w.level = .floating
        statsWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettings() {
        let root = SettingsView(engine: engine, onClose: { [weak self] in
            self?.showPopover()
        })
        presentPopover(root, size: CockpitView.panelSize)
    }

    // MARK: 通知

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String, sound: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound && engine.settings.soundOn ? .default : nil
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content,
                                        trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

// MARK: - 菜单栏图标
// 六边形太阳能翼板、横向连接杆和空心驾驶舱；按菜单栏原生尺寸设计。

enum StatusIcon {
    private static let template = draw(color: .black, template: true)

    static func makeTIE(color: NSColor? = nil) -> NSImage {
        if let color { return draw(color: color, template: false) }
        return template
    }

    private static func draw(color: NSColor, template: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            color.setFill()
            for mirrored in [false, true] {
                let points: [NSPoint] = [(1.0,4.0),(2.0,2.0),(6.0,2.0),(6.0,16.0),(2.0,16.0),(1.0,14.0)].map { x,y in
                    NSPoint(x: mirrored ? 20-x : x, y: y)
                }
                let panel = NSBezierPath()
                panel.move(to: points[0])
                for point in points.dropFirst() { panel.line(to: point) }
                panel.close()
                panel.windingRule = .evenOdd
                // 翼板网格用透明镂空构成，不擦除图标后面的菜单栏。
                panel.appendRect(NSRect(x: mirrored ? 16 : 3, y: 4, width: 1, height: 10))
                for x: CGFloat in mirrored ? [15, 17] : [2, 4] {
                    for y: CGFloat in [6, 11] {
                        panel.appendRect(NSRect(x: x, y: y, width: 1, height: 1))
                    }
                }
                panel.fill()
            }
            NSBezierPath(rect: NSRect(x: 6, y: 8, width: 1.5, height: 2)).fill()
            NSBezierPath(rect: NSRect(x: 12.5, y: 8, width: 1.5, height: 2)).fill()
            let cockpit = NSBezierPath(ovalIn: NSRect(x: 7, y: 6, width: 6, height: 6))
            cockpit.appendOval(in: NSRect(x: 8.5, y: 7.5, width: 3, height: 3))
            cockpit.windingRule = .evenOdd
            cockpit.fill()
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = "TIE 战机"
        return image
    }
}
