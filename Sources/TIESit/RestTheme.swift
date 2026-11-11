import SwiftUI

// 宁静的停泊港：星光、远山与像素飞船，动态仅存在于风景层。
enum RestTheme {
    static let background = Color(rgb: 0x08151F)
    static let text = Color(rgb: 0xE7EBDD)
    static let secondary = Color(rgb: 0xA4BAB8)
    static let quiet = Color(rgb: 0x7C999F)
    static let mint = Color(rgb: 0xA6C7B5)
    static let sand = Color(rgb: 0xC9B88F)
}

struct HarborLayout {
    let planetCenter: CGPoint
    let planetRadius: CGFloat
    let dockCenter: CGPoint
    let dockWidth: CGFloat
    let shipWidth: CGFloat

    init(size: CGSize, compact: Bool) {
        if compact {
            planetCenter = CGPoint(x: size.width * 0.69, y: size.height * 0.30)
            planetRadius = min(size.width * 0.22, size.height * 0.25)
            dockCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.77)
            dockWidth = size.width * 0.64
            shipWidth = min(80, size.width * 0.23)
        } else {
            let wide = size.width >= 760 && size.width / max(1, size.height) >= 1.25
            planetCenter = CGPoint(x: size.width * (wide ? 0.76 : 0.50), y: size.height * (wide ? 0.32 : 0.20))
            planetRadius = wide ? min(size.width * 0.18, size.height * 0.27) : min(size.width * 0.22, size.height * 0.14)
            dockCenter = CGPoint(x: size.width * (wide ? 0.75 : 0.72), y: size.height * (wide ? 0.72 : 0.40))
            dockWidth = wide ? min(460, size.width * 0.34) : min(210, size.width * 0.40)
            shipWidth = wide ? min(136, size.width * 0.14) : min(76, size.width * 0.16)
        }
    }
}

struct HarborMotion {
    let planetY: Double
    let shipY: Double
    let orbitAngle: Double
    let beacon: Double
    let visitorTime: Double
    init(time: Double, reducedMotion: Bool) {
        let t = reducedMotion ? time * 0.65 : time
        visitorTime = t
        let amplitude = reducedMotion ? 0.6 : 1.0
        planetY = sin(t * 2 * .pi / 18) * 4 * amplitude
        shipY = sin(t * 2 * .pi / 9) * 3 * amplitude
        orbitAngle = t * 2 * .pi / 80 + 0.55
        beacon = 0.6 + sin(t * 2 * .pi / 7) * (reducedMotion ? 0.08 : 0.15)
    }
}

struct RestPageLayout {
    let wide: Bool
    let contentWidth: CGFloat
    let contentCenter: CGPoint
    let headingSize: CGFloat
    let compact: Bool
    init(size: CGSize) {
        compact = size.height < 760
        wide = size.width >= 760 && size.width / max(1, size.height) >= 1.25
        contentWidth = wide ? min(420, size.width * 0.43) : min(420, size.width - 48)
        let left = max(40, size.width * 0.085)
        contentCenter = CGPoint(x: wide ? left + contentWidth / 2 : size.width / 2,
                               y: size.height * (wide ? 0.52 : (compact ? 0.68 : 0.65)))
        headingSize = compact ? 38 : 52
    }
}

struct RestHarborScene: View {
    let planet: Planet
    let ship: ShipShape
    var compact = false
    var motionEnabled = true
    /// 确定时刻用于设计导出与动画检查；正常运行由 TimelineView 驱动。
    var renderTime: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    var body: some View {
        Group {
            if motionEnabled && renderTime == nil {
                TimelineView(.periodic(from: startedAt, by: 1.0 / 24)) { frame in
                    scene(time: max(0, frame.date.timeIntervalSince(startedAt)))
                }
            } else {
                scene(time: motionEnabled ? (renderTime ?? 0) : 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func scene(time: Double) -> some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [RestTheme.background, Color(rgb: 0x173541), Color(rgb: 0x183A43)],
                               startPoint: .top, endPoint: .bottom)
                Canvas { ctx, size in draw(&ctx, size: size, time: time) }
                if !compact {
                    LinearGradient(stops: [.init(color: RestTheme.background.opacity(0.70), location: 0),
                                           .init(color: RestTheme.background.opacity(0.30), location: 0.42),
                                           .init(color: .clear, location: 0.72)],
                                   startPoint: .leading, endPoint: .trailing)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, time: Double) {
        guard size.width > 0, size.height > 0 else { return }
        let layout = HarborLayout(size: size, compact: compact)
        let motion = HarborMotion(time: time, reducedMotion: reduceMotion)
        let t = reduceMotion ? time * 0.45 : time
        drawStars(&ctx, size: size, time: t)
        let center = CGPoint(x: layout.planetCenter.x, y: layout.planetCenter.y + motion.planetY)
        let r = layout.planetRadius

        // 光晕、轨道和卫星的前后关系。
        let halo = CGRect(x: center.x - r * 1.5, y: center.y - r * 1.5, width: r * 3, height: r * 3)
        ctx.fill(Path(ellipseIn: halo), with: .radialGradient(
            Gradient(colors: [RestTheme.mint.opacity(0.12), .clear]), center: center,
            startRadius: r * 0.8, endRadius: r * 1.5))
        let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: -.pi / 9)
        let orbit = Path(ellipseIn: CGRect(x: -r * 1.32, y: -r * 0.52, width: r * 2.64, height: r * 1.04)).applying(transform)
        ctx.stroke(orbit, with: .color(RestTheme.mint.opacity(0.16)), lineWidth: 1)
        let satellite = CGPoint(x: cos(motion.orbitAngle) * r * 1.32,
                                y: sin(motion.orbitAngle) * r * 0.52).applying(transform)
        if sin(motion.orbitAngle) < 0 { drawSatellite(&ctx, at: satellite, small: compact) }
        if let image = planet.image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.withCGContext { cg in
                cg.interpolationQuality = .none
                cg.translateBy(x: center.x - r, y: center.y + r)
                cg.scaleBy(x: 1, y: -1)
                cg.draw(image, in: CGRect(x: 0, y: 0, width: r * 2, height: r * 2))
            }
        }
        if sin(motion.orbitAngle) >= 0 { drawSatellite(&ctx, at: satellite, small: compact) }

        drawRidge(&ctx, size: size, baseline: compact ? 0.65 : 0.72, amplitude: 0.055,
                  seed: 3, color: Color(rgb: 0x294E59))
        drawRidge(&ctx, size: size, baseline: compact ? 0.77 : 0.82, amplitude: 0.07,
                  seed: 11, color: Color(rgb: 0x17343F))
        drawDock(&ctx, layout: layout, motion: motion)
        drawRidge(&ctx, size: size, baseline: 0.96, amplitude: 0.045,
                  seed: 17, color: Color(rgb: 0x0B202B))
    }

    private func drawStars(_ ctx: inout GraphicsContext, size: CGSize, time: Double) {
        var random = SplitMix(seed: 887)
        for i in 0..<(compact ? 38 : 105) {
            let bx = Double(random.next() % 10000) / 10000 * size.width
            let y = Double(random.next() % 10000) / 10000 * size.height * 0.72
            let near = i % 6 == 0
            var x = (bx - time * (near ? 0.55 : 0.14)).truncatingRemainder(dividingBy: size.width)
            if x < 0 { x += size.width }
            let d: CGFloat = near ? 2 : 1
            ctx.fill(Path(CGRect(x: floor(x), y: floor(y), width: d, height: d)),
                     with: .color(RestTheme.text.opacity(near ? 0.42 : 0.18)))
            if near && i % 3 == 0 {
                ctx.fill(Path(CGRect(x: floor(x) - 2, y: floor(y) + 0.5, width: 6, height: 1)),
                         with: .color(RestTheme.text.opacity(0.12)))
            }
        }
    }

    private func drawRidge(_ ctx: inout GraphicsContext, size: CGSize, baseline: Double,
                           amplitude: Double, seed: Int, color: Color) {
        let step: CGFloat = compact ? 8 : 14
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for x in stride(from: CGFloat(0), through: size.width + step, by: step) {
            let wave = sin(Double(x) / Double(size.width) * 11 + Double(seed))
                + 0.5 * sin(Double(x) / Double(size.width) * 27 + Double(seed) * 0.3)
            let y = ((size.height * (baseline + wave * amplitude)) / 4).rounded() * 4
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + step, y: y))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
    }

    private func drawSatellite(_ ctx: inout GraphicsContext, at point: CGPoint, small: Bool) {
        let k: CGFloat = small ? 1 : 1.5
        for offset in [-5.0, 2.0] {
            ctx.fill(Path(CGRect(x: point.x + offset * k, y: point.y - 2 * k, width: 3 * k, height: 4 * k)),
                     with: .color(RestTheme.sand.opacity(0.75)))
        }
        ctx.fill(Path(CGRect(x: point.x - k, y: point.y - k, width: 3 * k, height: 2 * k)),
                 with: .color(RestTheme.text))
    }

    private func drawDock(_ ctx: inout GraphicsContext, layout: HarborLayout, motion: HarborMotion) {
        let p = layout.dockCenter
        let w = layout.dockWidth
        let depth: CGFloat = compact ? 15 : 24
        let top = Path { path in
            path.move(to: CGPoint(x: p.x - w / 2, y: p.y))
            path.addLine(to: CGPoint(x: p.x - w / 2 + depth, y: p.y - depth))
            path.addLine(to: CGPoint(x: p.x + w / 2 - depth, y: p.y - depth))
            path.addLine(to: CGPoint(x: p.x + w / 2, y: p.y))
            path.closeSubpath()
        }
        ctx.fill(Path(CGRect(x: p.x - w / 2 + 8, y: p.y, width: w - 16, height: depth)),
                 with: .color(Color(rgb: 0x0B1D29)))
        ctx.fill(top, with: .color(Color(rgb: 0x385560)))
        ctx.stroke(Path(CGRect(x: p.x - w / 2 + depth, y: p.y - depth, width: w - depth * 2, height: 1)),
                   with: .color(RestTheme.mint.opacity(0.55)), lineWidth: 1)
        for n in 0..<7 {
            let x = p.x - w * 0.34 + CGFloat(n) * w * 0.11
            ctx.fill(Path(CGRect(x: x, y: p.y - 6, width: compact ? 6 : 10, height: 2)),
                     with: .color(RestTheme.mint.opacity(motion.beacon)))
        }
        // 支柱与停泊灯，落在前景山峦之前。
        for direction in [-1.0, 1.0] {
            let x = p.x + direction * w * 0.38
            ctx.fill(Path(CGRect(x: x, y: p.y, width: compact ? 5 : 9, height: compact ? 40 : 90)),
                     with: .color(Color(rgb: 0x102732)))
            ctx.fill(Path(CGRect(x: x, y: p.y - depth - 10, width: 2, height: 10)),
                     with: .color(RestTheme.quiet))
            ctx.fill(Path(ellipseIn: CGRect(x: x - 4, y: p.y - depth - 15, width: 10, height: 10)),
                     with: .radialGradient(Gradient(colors: [RestTheme.mint.opacity(motion.beacon * 0.6), .clear]),
                                          center: CGPoint(x: x + 1, y: p.y - depth - 10), startRadius: 0, endRadius: 5))
        }
        let lookout = CoffeeLookoutLayout(harbor: layout, compact: compact)
        // 飞船停稳在平台左侧，着陆支架落到台面上。
        for offset in [-0.23, 0.23] {
            let x = lookout.shipCenter.x + layout.shipWidth * offset
            ctx.fill(Path(CGRect(x: x, y: lookout.groundY - 9, width: compact ? 2 : 3, height: 10)),
                     with: .color(RestTheme.secondary))
            ctx.fill(Path(CGRect(x: x - 3, y: lookout.groundY, width: 8, height: 2)),
                     with: .color(RestTheme.secondary))
        }
        ShipSprites.draw(ship, in: &ctx, center: lookout.shipCenter, cell: layout.shipWidth / 32)
        // 右侧观景栏杆置于小人背后，留出望向行星的开阔视野。
        let railY = p.y - depth - (compact ? 4 : 9)
        let railStart = p.x + w * 0.06
        let railEnd = p.x + w * 0.44
        ctx.fill(Path(CGRect(x: railStart, y: railY, width: railEnd - railStart, height: compact ? 1 : 2)),
                 with: .color(RestTheme.mint.opacity(0.5)))
        for fraction in [0.06, 0.25, 0.44] {
            ctx.fill(Path(CGRect(x: p.x + w * fraction, y: railY, width: compact ? 1 : 2, height: depth + 8)),
                     with: .color(RestTheme.quiet))
        }
        CoffeeVisitor.draw(in: &ctx, foot: lookout.personFoot, cell: lookout.personCell, time: motion.visitorTime)
    }
}

// 小型停泊插画也复用同一场景。
struct RestScene: View {
    let planet: Planet
    let ship: ShipShape
    var body: some View {
        RestHarborScene(planet: planet, ship: ship, compact: true).frame(width: 240, height: 160)
    }
}

struct RestHeader: View {
    var subtitle = "稍作停留"
    var body: some View {
        HStack {
            PixelText("TIE-SIT", scale: 2, color: RestTheme.secondary.opacity(0.7))
            Spacer()
            PixelCJK(subtitle, grid: 12, color: RestTheme.quiet)
        }
    }
}
