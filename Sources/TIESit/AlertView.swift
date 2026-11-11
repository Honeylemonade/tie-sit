import SwiftUI

// MARK: - 抵达休息站

struct AlertView: View {
    @ObservedObject var engine: SitEngine
    var onReleased: () -> Void = {}
    var sceneTime: Double? = nil

    @State private var holdProgress: Double = 0
    @State private var aborted = false
    @State private var completed = false

    private var holdSeconds: Double { Double(max(1, engine.settings.holdSec)) }

    var body: some View {
        GeometryReader { geo in
            let layout = RestPageLayout(size: geo.size)
            ZStack {
                RestHarborScene(planet: engine.destination, ship: engine.shipShape, motionEnabled: engine.settings.sceneMotionOn, renderTime: sceneTime)
                VStack(alignment: layout.wide ? .leading : .center, spacing: layout.compact ? 18 : 24) {
                    PixelCJK("已抵达\(engine.destination.name)", grid: 12, color: RestTheme.mint)
                    PixelCJK(layout.wide ? "看着星球，\n喝杯咖啡。" : "看星球，喝咖啡", scale: layout.wide ? (layout.compact ? 2 : 3) : 2,
                             color: RestTheme.text, spacing: 12, alignment: layout.wide ? .leading : .center)
                    PixelCJK("起身走走，看看远处。\n飞船和事情，都可以等一等。", color: RestTheme.secondary,
                             spacing: 9, alignment: layout.wide ? .leading : .center)
                    HStack(spacing: 20) {
                        PixelCJK("这一程 \(engine.alertSnapshot.run) 分钟", grid: 12, color: RestTheme.quiet)
                        PixelCJK("第 \(engine.alertSnapshot.standsToday + 1) 次起身", grid: 12, color: RestTheme.quiet)
                    }
                    VStack(alignment: layout.wide ? .leading : .center, spacing: 14) {
                        HoldButton(progress: holdProgress, totalSeconds: holdSeconds,
                                   aborted: aborted, onChange: handleHoldChange, width: layout.contentWidth)
                        PixelCJK(aborted ? "没关系，准备好了再按住。" :
                             (engine.settings.restMin > 0 ? "留给自己 \(engine.settings.restMin) 分钟。" : "让身体动一动，再继续下一程。"),
                             grid: 12, color: RestTheme.secondary)
                    }
                    .padding(.top, layout.compact ? 2 : 8)
                }
                .frame(width: layout.contentWidth, alignment: layout.wide ? .leading : .center)
                .position(layout.contentCenter)

                VStack {
                    HStack(spacing: 20) {
                        RestHeader()
                        if engine.isPreview {
                            Button { engine.cancelPreview(); onReleased() } label: {
                                PixelCJK("退出预览", grid: 12, color: RestTheme.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                    Spacer()
                    HStack {
                        PixelCJK("此刻，只需要照顾一下自己。", grid: 12, color: RestTheme.quiet)
                        Spacer()
                        if layout.wide { PixelCJK("飞船已经停稳，可以放心离开片刻。", grid: 12, color: RestTheme.quiet) }
                    }
                    .font(.system(size: 11)).foregroundColor(RestTheme.quiet)
                }
                .padding(layout.compact ? 24 : 36)
            }
        }
    }

    private func handleHoldChange(_ progress: Double, _ isHolding: Bool) {
        guard !completed else { return }
        let hadProgress = holdProgress > 0
        holdProgress = progress
        if isHolding { aborted = false }
        if progress == 0 && !isHolding && hadProgress { aborted = true }
        if progress >= 1 {
            completed = true
            engine.unlock()
            onReleased()
        }
    }
}

// MARK: - 长按按钮

/// 柔和填充进度。按下开始，松手或拖出立刻归零。
/// 用 DragGesture(minimumDistance: 0) 而不是 Button，才能拿到按下/抬起两个时刻。
struct HoldButton: View {

    var progress: Double
    var totalSeconds: Double
    var aborted: Bool
    var onChange: (Double, Bool) -> Void
    var width: CGFloat = 420

    @State private var startTime: Date?
    @State private var display = 0.0
    @State private var timer: Timer?
    @State private var isDown = false
    @State private var hovered = false
    @State private var didComplete = false

    var body: some View {
        RestChargeFace(progress: display, totalSeconds: totalSeconds, pressed: isDown,
                       hovered: hovered, aborted: aborted)
        .frame(width: width, height: 84)
        .onHover { hovered = $0 }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let inside = CGRect(x: 0, y: 0, width: width, height: 84).contains(value.location)
                    if inside && !isDown { begin() }
                    if !inside && isDown { end() }
                }
                .onEnded { _ in
                    end()
                }
        )
        .onDisappear {
            timer?.invalidate()
            timer = nil
            startTime = nil
            isDown = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("begin-rest")
        .accessibilityLabel("长按 \(Int(totalSeconds)) 秒开始休息")
    }

    private func begin() {
        guard !isDown && !didComplete else { return }
        isDown = true
        startTime = Date()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            guard let st = startTime else { return }
            let elapsed = Date().timeIntervalSince(st)
            let p = min(1.0, elapsed / max(1, totalSeconds))
            display = p
            onChange(p, true)
            if p >= 1 {
                didComplete = true
                timer?.invalidate()
                timer = nil
                isDown = false
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func end() {
        // 已经跑满 = 已解锁，不走中断逻辑
        let finished = display >= 1
        isDown = false
        timer?.invalidate()
        timer = nil
        startTime = nil
        display = 0
        if finished { return }
        // 没跑满就是中途松手/移出
        onChange(0, false)
    }
}