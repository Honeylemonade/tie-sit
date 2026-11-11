import SwiftUI

// MARK: - 驾驶舱（菜单栏浮层主视图）
//
// 一块 360×560 的竖屏。没有滚动，一屏读完。

struct CockpitView: View {

    static let panelSize = CGSize(width: 360, height: 560)

    @ObservedObject var engine: SitEngine
    var onOpenStats: () -> Void
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    private var s: SitSettings { engine.settings }

    var body: some View {
        ZStack {
            PX.void.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Divider().overlay(PX.bay).frame(height: 2)
                // 场景吃掉剩余空间：下面几段是固定高度的读数区
                battlefield
                Divider().overlay(PX.bay).frame(height: 2)
                hudBar
                Divider().overlay(PX.bay).frame(height: 2)
                progressBlock
                Divider().overlay(PX.bay).frame(height: 2)
                todayBlock
                Divider().overlay(PX.bay).frame(height: 2)
                bottomBar
            }
            .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .overlay(
            Group {
                if s.scanlinesOn { Scanlines(opacity: 0.35) }
            }
        )

    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 10) {
            PixelText("TIE-SIT", scale: 2, color: PX.chalk)

            Spacer()

            Button {
                Chiptune.shared.click()
                engine.cycleThreshold()
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(PX.order)
                        .frame(width: 5, height: 5)
                    PixelText("\(s.thresholdMin)M", scale: 1.6, color: PX.order)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .pixelFrame(PX.order.opacity(0.55), width: 2)
            }
            .buttonStyle(.plain)
            .help("点击切换阈值：25 / 45 / 60 / 90 分钟")

            Button {
                var ns = s
                ns.soundOn.toggle()
                Chiptune.shared.enabled = ns.soundOn
                if ns.soundOn { Chiptune.shared.click() }
                engine.apply(ns)
            } label: {
                PixelText(s.soundOn ? "SND" : "MUTE", scale: 1.4,
                          color: s.soundOn ? PX.sys : PX.bay)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .pixelFrame(s.soundOn ? PX.sys.opacity(0.5) : PX.bay, width: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: 战场（飞船飞向星球）

    private var battlefield: some View {
        Group {
            if engine.state == .resting || engine.state == .offDuty {
                RestHarborScene(planet: engine.destination, ship: engine.shipShape, compact: true, motionEnabled: s.sceneMotionOn)
                    .overlay(alignment: .bottom) {
                        PixelCJK("停泊于\(engine.destination.name)", grid: 12)
                            .foregroundColor(RestTheme.secondary).padding(.bottom, 10)
                    }
            } else {
                FlightScene(progress: engine.progress, planet: engine.destination,
                            ship: engine.shipShape, flying: engine.state == .sitting, motionEnabled: s.sceneMotionOn)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// 独立 HUD 条：剩余时间。原来是绝对定位在战场里的，会和死星标签压字。
    private var hudBar: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                PixelText(hudLabel, scale: 1.3, color: hudAccent.opacity(0.75))
                PixelText(hudValue, scale: 3, color: hudAccent)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                PixelText("LIMIT", scale: 1.0, color: PX.bay)
                PixelText(Fmt.clock(s.thresholdMin * 60), scale: 1.7, color: PX.hull)
                PixelText("\(Int(engine.progress * 100))%", scale: 1.0,
                          color: engine.progress > 0.75 ? PX.alert : PX.bay)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var hudLabel: String {
        switch engine.state {
        case .sitting, .alert: return "TIME TO STAND"
        case .resting: return "REST REMAIN"
        case .endOfDay: return "SHIFT TOTAL"
        case .offDuty: return "OFF DUTY"
        }
    }

    private var hudValue: String {
        switch engine.state {
        case .sitting, .alert: return Fmt.clock(Int(engine.remaining))
        case .resting: return Fmt.clock(Int(engine.restRemaining))
        case .endOfDay: return Fmt.span(engine.daySitMinutes)
        case .offDuty: return Fmt.span(engine.today.total)
        }
    }

    private var hudAccent: Color {
        switch engine.state {
        case .sitting, .alert:
            return engine.progress > 0.75 ? PX.alert : PX.order
        case .resting, .offDuty: return RestTheme.mint
        case .endOfDay: return PX.order
        }
    }

    // MARK: 进度

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                PixelText(stateLabel, scale: 1.5, color: PX.hull)
                Spacer()
                Button {
                    Chiptune.shared.click()
                    onOpenStats()
                } label: {
                    PixelText("STATS >", scale: 1.4, color: PX.sys)
                }
                .buttonStyle(.plain)
            }

            if engine.state == .resting {
                BlockBar(progress: engine.restProgress, color: RestTheme.mint, blocks: 20)
                    .pixelFrame(PX.bay.opacity(0.7), width: 1)
                HStack {
                    PixelText("RESTING", scale: 1.2, color: RestTheme.mint.opacity(0.8))
                    Spacer()
                    PixelText(Fmt.clock(Int(engine.restRemaining)), scale: 1.4, color: PX.ok)
                }
            } else if engine.state == .offDuty || engine.state == .endOfDay {
                BlockBar(progress: Double(engine.daySitMinutes) / Double(curfewLimitMin),
                         color: PX.ok, blocks: 20)
                    .pixelFrame(PX.bay.opacity(0.7), width: 1)
                HStack {
                    PixelText(Fmt.span(engine.today.total), scale: 1.4, color: PX.chalk)
                    PixelText("/", scale: 1.2, color: PX.bay)
                    PixelText(Fmt.span(curfewLimitMin), scale: 1.4, color: PX.hull)
                    Spacer()
                    PixelText(engine.state == .offDuty ? "DONE" : "LIMIT",
                              scale: 1.3, color: engine.state == .offDuty ? PX.ok : PX.alert)
                }
            } else {
                BlockBar(
                    progress: engine.progress,
                    color: engine.progress > 0.8 ? PX.alert : PX.order,
                    blocks: 20,
                    flashing: engine.progress > 0.9
                )
                .pixelFrame(PX.bay.opacity(0.7), width: 1)
                HStack {
                    PixelText(Fmt.clock(Int(engine.elapsed)), scale: 1.4, color: PX.chalk)
                    PixelText("/", scale: 1.2, color: PX.bay)
                    PixelText(Fmt.clock(s.thresholdMin * 60), scale: 1.4, color: PX.hull)
                    Spacer()
                    PixelText("\(Int(engine.progress * 100))%", scale: 1.3, color: PX.hull)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var stateLabel: String {
        switch engine.state {
        case .sitting, .alert: return "SIT"
        case .resting: return "REST"
        case .endOfDay: return "SHIFT"
        case .offDuty: return "OFF"
        }
    }

    // MARK: 今日

    private var todayBlock: some View {
        HStack(spacing: 0) {
            statCell(label: "STANDS", value: "\(engine.today.stands)", color: PX.ok)
            cellDivider
            statCell(label: "MAX RUN", value: "\(max(engine.today.maxRun, Int(engine.elapsed / 60)))M",
                     color: max(engine.today.maxRun, Int(engine.elapsed / 60)) > s.thresholdMin ? PX.alert : PX.ok)
            cellDivider
            statCell(label: "SIT TOTAL", value: Fmt.span(engine.daySitMinutes), color: PX.sys)
            cellDivider
            statCell(label: "STREAK", value: "\(engine.streak)D", color: PX.order)
        }
        .padding(.vertical, 8)
    }

    private var cellDivider: some View {
        Rectangle().fill(PX.bay.opacity(0.6)).frame(width: 1, height: 26)
    }

    private func statCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            PixelText(label, scale: 1.0, color: PX.bay)
            PixelText(value, scale: 1.8, color: color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 底栏

    private var bottomBar: some View {
        HStack(spacing: 0) {
            barButton("STATS", PX.sys) { onOpenStats() }
            barButton("SETUP", PX.order) { onOpenSettings() }
            barButton("QUIT", PX.alert) { onQuit() }
        }
        .frame(height: 40)
    }

    private func barButton(_ title: String, _ tint: Color,
                           action: @escaping () -> Void) -> some View {
        Button {
            Chiptune.shared.click()
            action()
        } label: {
            VStack(spacing: 4) {
                PixelText(title, scale: 1.3, color: PX.hull)
                Rectangle()
                    .fill(tint.opacity(0.55))
                    .frame(width: PixelFont.width(title, scale: 1.3), height: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Rectangle().fill(PX.bay.opacity(0.5)).frame(width: 1)
        }
    }
}

// MARK: - 组件

struct Starfield: View {
    var count: Int = 40
    var seed: UInt64 = 1
    var maxSize: CGFloat = 3
    /// 横向偏移（像素）。远近两层给不同的 drift 就有视差。
    var drift: CGFloat = 0

    var body: some View {
        Canvas { ctx, size in
            var rng = SplitMix(seed: seed)
            let span = size.width + 40
            for _ in 0..<count {
                let bx = CGFloat(rng.next() % 10000) / 10000 * size.width
                let y = CGFloat(rng.next() % 10000) / 10000 * size.height
                let big = rng.next() % 100 > 86
                let s: CGFloat = big ? maxSize : max(2, maxSize - 1)
                let c = rng.next() % 100 > 72 ? PX.star : PX.bay
                // 偏移后按 span 取模，出了右边就从左边回来
                var x = (bx + drift).truncatingRemainder(dividingBy: span)
                if x < -20 { x += span }
                // 对齐到 2px 网格，保持像素感
                let rect = CGRect(x: (x / 2).rounded(.down) * 2,
                                  y: (y / 2).rounded(.down) * 2,
                                  width: s, height: s)
                ctx.fill(Path(rect), with: .color(c.opacity(0.75)))
            }
        }
    }
}

/// 死星：实心球 + 赤道沟槽 + 超空间反应堆，外面套一圈轨道刻度。
/// 进度越高，反应堆凹槽越亮、轨道环越完整。
struct DeathStar: View {
    var staged: Double          // 0...1
    var pulsing: Bool

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let cx = size.width / 2
            let cy = size.height / 2
            let r = s * 0.38

            // 球体：用几个同心圆叠出硬边明暗，不做渐变（红白机没有渐变）
            let ball = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: ball), with: .color(PX.dim))
            ctx.stroke(Path(ellipseIn: ball), with: .color(PX.hull), lineWidth: 2)

            // 左上高光
            let hl = CGRect(x: cx - r * 0.62, y: cy - r * 0.68,
                            width: r * 0.46, height: r * 0.32)
            ctx.fill(Path(ellipseIn: hl), with: .color(PX.hull.opacity(0.45)))

            // 赤道沟槽
            ctx.fill(Path(CGRect(x: cx - r, y: cy - r * 0.11,
                                 width: r * 2, height: r * 0.22)),
                     with: .color(PX.void))
            ctx.fill(Path(CGRect(x: cx - r, y: cy - r * 0.11,
                                 width: r * 2, height: 1)),
                     with: .color(PX.bay))
            ctx.fill(Path(CGRect(x: cx - r, y: cy + r * 0.11 - 1,
                                 width: r * 2, height: 1)),
                     with: .color(PX.bay))

            // 超空间反应堆：进度越高越亮
            let coreR = r * 0.22
            let core = CGRect(x: cx - coreR, y: cy - coreR, width: coreR * 2, height: coreR * 2)
            ctx.fill(Path(ellipseIn: core), with: .color(PX.void))
            ctx.stroke(Path(ellipseIn: core), with: .color(PX.bay), lineWidth: 1)
            let hot = CGRect(x: cx - coreR * 0.5, y: cy - coreR * 0.5,
                             width: coreR, height: coreR)
            let glow = 0.3 + 0.6 * staged
            ctx.fill(Path(ellipseIn: hot),
                     with: .color(PX.alert.opacity(pulsing ? min(1, glow + 0.2) : glow * 0.6)))

            // 轨道刻度环：随进度一段段点亮
            let orbitR = s * 0.48
            let ticks = 24
            for i in 0..<ticks {
                let a = Double(i) / Double(ticks) * 2 * .pi - .pi / 2
                let lit = Double(i) / Double(ticks) <= staged
                let inner = orbitR - (lit ? 5 : 3)
                let p = Path { path in
                    path.move(to: CGPoint(x: cx + cos(a) * inner, y: cy + sin(a) * inner))
                    path.addLine(to: CGPoint(x: cx + cos(a) * orbitR, y: cy + sin(a) * orbitR))
                }
                ctx.stroke(p, with: .color(lit ? PX.order.opacity(0.85) : PX.bay.opacity(0.5)),
                           lineWidth: 2)
            }
        }
    }
}

/// 确定性伪随机，保证每次渲染星位一致
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// TIE 战机侧影：六边形机翼 + 球形驾驶舱
struct TIESilhouette: View {
    var size: CGFloat = 30
    var color: Color = PX.star

    var body: some View {
        Canvas { ctx, gsize in
            let s = min(gsize.width, gsize.height)
            let cx = gsize.width / 2
            let cy = gsize.height / 2

            // 两侧六边形机翼
            for dir in [-1.0, 1.0] {
                let x = cx + CGFloat(dir) * s * 0.34
                var p = Path()
                p.move(to: CGPoint(x: x, y: cy - s * 0.42))
                p.addLine(to: CGPoint(x: x + CGFloat(dir) * s * 0.16, y: cy))
                p.addLine(to: CGPoint(x: x, y: cy + s * 0.42))
                p.addLine(to: CGPoint(x: x - CGFloat(dir) * s * 0.14, y: cy))
                p.closeSubpath()
                ctx.fill(p, with: .color(color))
            }

            // 中间连接杆
            ctx.fill(Path(CGRect(x: cx - s * 0.12, y: cy - s * 0.06,
                                 width: s * 0.24, height: s * 0.12)),
                     with: .color(color))

            // 驾驶舱球体
            let ball = CGRect(x: cx - s * 0.13, y: cy - s * 0.13,
                              width: s * 0.26, height: s * 0.26)
            ctx.fill(Path(ellipseIn: ball), with: .color(color))
            // 舷窗

            ctx.fill(Path(ellipseIn: ball.insetBy(dx: s * 0.05, dy: s * 0.05)),
                     with: .color(PX.void))
        }
        .frame(width: size, height: size)
    }
}