import Foundation
import CoreGraphics
import AppKit
import AVFoundation

// MARK: - 空闲检测
//
// 人不在的时候不该算久坐。这是原生 App 相对网页版最关键的优势。

enum IdleMonitor {
    /// 距离上一次键鼠输入的秒数
    static func secondsSinceLastInput() -> TimeInterval {
        // 任意事件类型里取最近的一次
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .rightMouseDown,
            .keyDown, .scrollWheel, .leftMouseDragged
        ]
        var smallest = TimeInterval.greatestFiniteMagnitude
        for t in types {
            let s = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: t)
            if s >= 0 && s < smallest { smallest = s }
        }
        return smallest == .greatestFiniteMagnitude ? 0 : smallest
    }
}

// MARK: - 8-bit 音效
//
// 方波现场合成，不打包任何音频文件。
// 用 AVAudioEngine + AVAudioSourceNode 画波形。

final class Chiptune {

    static let shared = Chiptune()

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let sampleRate: Double = 44_100
    private let toneQueue = DispatchQueue(label: "tiesit.chiptune")

    // 当前正在发声的音符队列（简化：一次一个）
    private var phase: Double = 0
    private var freq: Double = 0
    private var amp: Double = 0
    private var decayRate: Double = 0    // 每秒衰减量，0 表示不衰减
    private var locked = NSLock()

    var enabled: Bool = true

    private init() {
        // 装配放到独立串行队列：连接音频图不该占主线程
        let q = toneQueue
        q.async { [weak self] in
            self?.setup()
        }
    }

    private func setup() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let buf = abl.first, let ptr = buf.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }

            self.locked.lock()
            let f = self.freq, d = self.decayRate
            var ph = self.phase, a = self.amp
            self.locked.unlock()

            let step = f / self.sampleRate
            for i in 0..<Int(frameCount) {
                // 方波：相位前半为 +1，后半为 -1
                let v = (ph.truncatingRemainder(dividingBy: 1.0) < 0.5) ? 1.0 : -1.0
                ptr[i] = Float(v * a * 0.18)
                ph += step
                if ph > 1_000_000 { ph -= 1_000_000 }
                if d > 0 { a = max(0, a - d / self.sampleRate) }
            }

            self.locked.lock()
            self.phase = ph
            self.amp = a
            self.locked.unlock()

            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
    }

    /// 供 SwiftUI 读取当前静音状态（避免直接摸 internal 存储）
    var isEnabled: Bool {
        get { enabled }
        set { enabled = newValue }
    }

    private func ensureRunning() {
        toneQueue.async { [weak self] in
            guard let self, !self.engine.isRunning else { return }
            do { try self.engine.start() } catch {
                // 没有音频设备时静默失败，不影响主功能
            }
        }
    }

    // MARK: 音型

    func tone(_ hz: Double, duration: Double, decay: Bool = true) {
        guard enabled else { return }
        ensureRunning()
        locked.lock()
        freq = hz
        amp = 1.0
        decayRate = decay ? 1.0 / max(0.05, duration) : 0
        locked.unlock()
        if decay {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self else { return }
                self.locked.lock()
                if self.amp < 0.02 { self.amp = 0 }
                self.locked.unlock()
            }
        }
    }

    /// 长按进度音：按格上升的半音阶
    func tick(step: Int, of total: Int) {
        guard enabled else { return }
        let t = Double(step) / Double(max(1, total))
        let hz = 220.0 * pow(2.0, t * 2.0)     // 两个八度内爬升
        tone(hz, duration: 0.06)
    }

    func unlockSuccess() {
        guard enabled else { return }
        let notes = [523.25, 659.25, 783.99, 1046.5]
        for (i, n) in notes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09) { [weak self] in
                self?.tone(n, duration: 0.18)
            }
        }
    }

    func holdAborted() {
        guard enabled else { return }
        let notes = [392.0, 329.63, 261.63]
        for (i, n) in notes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.07) { [weak self] in
                self?.tone(n, duration: 0.12)
            }
        }
    }

    /// 防空警报：两音交替
    private var alertTimer: Timer?
    private var alertHigh = false

    func startAlertSiren() {
        guard enabled else { return }
        stopAlertSiren()
        ensureRunning()
        let t = Timer(timeInterval: 0.42, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.alertHigh.toggle()
            self.tone(self.alertHigh ? 659.25 : 440.0, duration: 0.38, decay: false)
        }
        RunLoop.main.add(t, forMode: .common)
        alertTimer = t
        tone(659.25, duration: 0.38, decay: false)
    }

    func stopAlertSiren() {
        alertTimer?.invalidate()
        alertTimer = nil
        locked.lock(); amp = 0; locked.unlock()
    }

    func click() { tone(880, duration: 0.03) }

    func restDone() {
        guard enabled else { return }
        tone(660, duration: 0.1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            self?.tone(880, duration: 0.12)
        }
    }
}