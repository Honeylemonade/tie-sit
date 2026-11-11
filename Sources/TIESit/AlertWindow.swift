import AppKit
import SwiftUI

// MARK: - 全屏警报遮罩
//
// 关键点：
//   · 无边框、无标题栏、没有关闭按钮
//   · window.level = .screenSaver —— 比普通窗口高，压得住全屏浏览器和视频
//   · collectionBehavior 覆盖所有 Space、盖住全屏 App
//   · 每个 NSScreen 各铺一块，多显示器一起锁
//   · canBecomeKey 返回 true，才能吃下键盘事件

extension Notification.Name {
    /// 长按 5 秒成功、遮罩该收起来了
    static let tiesitAlertReleased = Notification.Name("TIESitAlertReleased")
    /// 下班令点了「下班」
    static let tiesitShiftEnded = Notification.Name("TIESitShiftEnded")
}

@MainActor
final class AlertWindowController {

    private var windows: [NSWindow] = []
    private let engine: SitEngine
    private var onClose: (() -> Void)?
    private var presented = false
    private var screenObserver: NSObjectProtocol?
    private let screenFrames: () -> [NSRect]

    init(engine: SitEngine, screenFrames: @escaping () -> [NSRect] = { NSScreen.screens.map(\.frame) }) {
        self.engine = engine
        self.screenFrames = screenFrames
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildForScreens() }
        }
    }

    deinit {
        if let observer = screenObserver { NotificationCenter.default.removeObserver(observer) }
    }

    var isShowing: Bool { presented }

    func show(onClose: @escaping () -> Void) {
        guard !presented else { return }
        presented = true
        self.onClose = onClose

        // 先把 App 激活到前台，否则窗口抬不起来
        NSApp.activate(ignoringOtherApps: true)

        for frame in screenFrames() {
            let w = AlertWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            w.isOpaque = true
            w.backgroundColor = NSColor(red: 11.0 / 255, green: 21.0 / 255, blue: 29.0 / 255, alpha: 1)
            w.level = .screenSaver
            w.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle
            ]
            w.hasShadow = false
            w.isMovable = false
            w.isMovableByWindowBackground = false
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false

            // 下班令和久坐警报共用这个遮罩，内容不同
            let content: AnyView
            let previewing = engine.isPreview
            if engine.state == .endOfDay {
                content = AnyView(CurfewView(engine: engine, onEndShift: {
                    NotificationCenter.default.post(name: previewing ? .tiesitAlertReleased : .tiesitShiftEnded, object: nil)
                }))
            } else {
                content = AnyView(AlertView(engine: engine, onReleased: {
                    NotificationCenter.default.post(name: .tiesitAlertReleased, object: nil)
                }))
            }
            let host = NSHostingView(rootView: content)
            host.frame = NSRect(origin: .zero, size: frame.size)
            w.contentView = host
            w.setFrame(frame, display: true)

            windows.append(w)
        }

        // 装一层事件拦截：ESC / Cmd+Q / Cmd+W 全部吞掉
        EventTrap.shared.activate()
        EventTrap.shared.onSwallow = nil

        // 所有窗口都加进来之后再统一抬到最前
        for w in windows {
            w.makeKeyAndOrderFront(nil)
            w.orderFrontRegardless()
        }
        }

    private func rebuildForScreens() {
        guard presented else { return }
        let callback = onClose ?? {}
        tearDownWindows()
        presented = false
        show(onClose: callback)
    }

    private func tearDownWindows() {
        EventTrap.shared.deactivate()
        for w in windows {
            w.orderOut(nil)
            w.contentView = nil
        }
        windows.removeAll()
    }

    func close() {
        guard presented else { return }
        presented = false
        tearDownWindows()
        onClose?()
        onClose = nil
    }

}

// MARK: - 无边框窗口

final class AlertWindow: NSWindow {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // 拒绝关闭
    override func close() {
        // 故意空实现：警报期间不允许关闭
    }

    override func performClose(_ sender: Any?) {
        // 同上
    }

    // 吃掉 ESC（cancelOperation）
    override func cancelOperation(_ sender: Any?) {
        // 安静地保留长按确认，不用声音惩罚误按。
    }

    override func keyDown(with event: NSEvent) {
        // 所有按键都不往下传，保持安静
        // 按键不打断休息站，也不播放提示音。
    }
}

// MARK: - 全局事件拦截

final class EventTrap {

    static let shared = EventTrap()
    private var monitor: Any?
    var onSwallow: (() -> Void)?

    func activate() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            // 允许的按键：无。全部吞掉，警报期间不接受任何键盘输入。
            // 安静拦截误按，不增加打扰。
            self?.onSwallow?()
            return nil              // 返回 nil = 事件被吃掉
        }
    }

    func deactivate() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}