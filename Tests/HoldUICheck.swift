import AppKit
import SwiftUI

@main
struct HoldUICheck {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        var cancellations = 0
        var lastDown = ProcessInfo.processInfo.systemUptime
        var heldFor = 0.0
        var completed = 0
        var advanced = false
        var restartedAfterCompletion = false
        let button = HoldButton(progress: 0, totalSeconds: 5, aborted: false) { p, down in
            if completed > 0 && p < 1 && down { restartedAfterCompletion = true }
            if p > 0 { advanced = true }
            if !down && p == 0 { cancellations += 1 }
            if p >= 1 {
                completed += 1
                heldFor = ProcessInfo.processInfo.systemUptime - lastDown
            }
        }
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 420, height: 84),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: button)
        window.orderFrontRegardless()
        func send(_ type: NSEvent.EventType, outside: Bool = false) {
            if type == .leftMouseDown { lastDown = ProcessInfo.processInfo.systemUptime }
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: outside ? 500 : (type == .leftMouseDragged ? 230 : 210), y: 42),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
            window.sendEvent(event)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { send(.leftMouseDown) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { send(.leftMouseUp) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { send(.leftMouseDown) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { send(.leftMouseDragged, outside: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { send(.leftMouseUp, outside: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { send(.leftMouseDown) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.6) { send(.leftMouseDragged) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.8) { send(.leftMouseUp) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            print("Hold UI: advanced=\(advanced) cancellations=\(cancellations), heldFor=\(heldFor) completions=\(completed) restartedAfterCompletion=\(restartedAfterCompletion)")
            window.orderOut(nil)
            exit(advanced && cancellations >= 2 && completed == 1 && heldFor >= 5 && !restartedAfterCompletion ? 0 : 1)
        }
        app.run()
    }
}
