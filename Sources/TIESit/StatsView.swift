import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 统计
//
// 三个尺度回答三个不同的问题，不是把同一张图换个筛选条件：
//   今天  → 我现在状态怎样
//   30 天 → 最近节奏有没有变坏
//   365 天→ 一年里最低谷是哪几周

struct StatsView: View {

    @ObservedObject var engine: SitEngine
    /// 关闭统计窗口（由 AppDelegate 注入）
    var onClose: () -> Void = {}

    @State private var tab = 0          // 0 今天 / 1 三十天 / 2 一年
    @State private var exportMsg: String?

    private var s: SitSettings { engine.settings }
    private var today: DayRecord { engine.todayIncludingCurrentRun }

    private var exportAlertBinding: Binding<Bool> {
        Binding(
            get: { exportMsg != nil },
            set: { if !$0 { exportMsg = nil } }
        )
    }

    var body: some View {
        ZStack {
            PX.void.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Rectangle().fill(PX.bay).frame(height: 2)
                tabs
                Rectangle().fill(PX.bay).frame(height: 2)

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        metrics
                        Rectangle().fill(PX.bay.opacity(0.6)).frame(height: 2)

                        switch tab {
                        case 0: todaySection
                        case 1: monthSection
                        default: yearSection
                        }

                        exportRow
                    }
                    .padding(22)
                }
            }
        }
        .frame(width: 760, height: 720)
        .overlay(Group { if s.scanlinesOn { Scanlines(opacity: 0.3) } })
        .alert("导出", isPresented: exportAlertBinding) {
            Button("好") { exportMsg = nil }
        } message: {
            Text(exportMsg ?? "")
        }
    }

    // MARK: 顶栏

    private var header: some View {
        HStack(spacing: 12) {
            PixelText("STATS", scale: 2.2, color: PX.chalk)
            CJK("统计", size: 14, color: PX.hull, tracking: 2)
            Spacer()
            PixelText("365D", scale: 1.3, color: PX.sys)
            Button {
                Chiptune.shared.click()
                onClose()
            } label: {
                HStack(spacing: 4) {
                    PixelText("CLOSE", scale: 1.3, color: PX.hull)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .pixelFrame(PX.bay)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(20)
    }

    // MARK: 尺度切换

    private var tabs: some View {
        HStack(spacing: 0) {
            tabButton("今天", 0, "TODAY")
            tabButton("近 30 天", 1, "30D")
            tabButton("近 365 天", 2, "365D")
        }
    }

    private func tabButton(_ cn: String, _ idx: Int, _ en: String) -> some View {
        Button {
            Chiptune.shared.click()
            tab = idx
        } label: {
            VStack(spacing: 5) {
                CJK(cn, size: 14, weight: tab == idx ? .semibold : .regular,
                    color: tab == idx ? PX.chalk : PX.hull, tracking: 1)
                PixelText(en, scale: 1.1, color: tab == idx ? PX.order : PX.bay)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tab == idx ? PX.order.opacity(0.06) : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(tab == idx ? PX.order : Color.clear)
                    .frame(height: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 四个核心指标

    private var metrics: some View {
        HStack(spacing: 0) {
            metric("今日起身", "\(today.stands)", "STANDS", PX.ok)
            vline
            metric("最长连续", "\(today.maxRun)M", "MAX RUN",
                   today.maxRun > s.thresholdMin ? PX.alert : PX.ok)
            vline
            metric("连续达标", "\(engine.streak)", "STREAK", PX.order)
            vline
            metric("日均在座", Fmt.span(engine.avg7), "7D AVG", PX.sys)
        }
    }

    private var vline: some View {
        Rectangle().fill(PX.bay).frame(width: 2, height: 52)
    }

    private func metric(_ cn: String, _ value: String, _ en: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            CJK(cn, size: 12, color: PX.hull, tracking: 1)
            PixelText(value, scale: 2.6, color: color)
            PixelText(en, scale: 1.0, color: PX.bay)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 今天 —— 在座分段条

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("今日在座分段", "TODAY SESSIONS")

            if today.sessions.isEmpty {
                emptyHint("今天还没有在座记录，满一分钟后会显示在这里。")
            } else {
                TimelineBar(sessions: today.sessions,
                            threshold: s.thresholdMin, dayStartHour: s.dayStartHour)
                    .frame(height: 96)

                // 图例
                HStack(spacing: 18) {
                    legend(color: PX.ok, text: "达标区间")
                    legend(color: PX.alert, text: "超过 \(s.thresholdMin) 分钟")
                    Spacer()
                    PixelText("\(today.sessions.count) SEG", scale: 1.2, color: PX.bay)
                }
            }

            // 每段明细
            ForEach(Array(today.sessions.enumerated()), id: \.offset) { index, sess in
                HStack(spacing: 12) {
                    PixelText(String(format: "%02d:%02d", sess.hour, sess.minute),
                              scale: 1.4, color: PX.hull)
                    Rectangle()
                        .fill(sess.minutes > s.thresholdMin ? PX.alert : PX.ok)
                        .frame(width: CGFloat(min(200, sess.minutes * 3)), height: 8)
                    PixelText("\(sess.minutes)M", scale: 1.4,
                              color: sess.minutes > s.thresholdMin ? PX.alert : PX.star)
                    if engine.elapsed >= 60 && index == today.sessions.count - 1 {
                        Text("进行中").font(.system(size: 10)).foregroundColor(PX.order)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: 30 天 —— 日历热力

    private var monthSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("近 30 天热力", "30 DAY HEATMAP")
            HeatGrid(days: engine.recentDays(30), threshold: s.thresholdMin)
                .frame(height: 168)
            heatLegend
            CJK("每格一天。颜色深浅是当日最长连续在座时长；红色代表超过上限那一天。",
                size: 12, color: PX.hull, tracking: 0.6)
        }
    }

    // MARK: 365 天 —— 周报

    private var yearSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("近 365 天周报", "52 WEEK BARS")
            YearBars(days: engine.recentDays(365), threshold: s.thresholdMin)
                .frame(height: 190)

            Rectangle().fill(PX.bay.opacity(0.6)).frame(height: 2)

            sectionLabel("全年日历", "YEAR GRID")
            YearGrid(days: engine.recentDays(365), threshold: s.thresholdMin)
                .frame(height: 150)

            heatLegend

            // 年度汇总
            HStack(spacing: 26) {
                yearStat("达标天数", "\(compliantDays)",
                         of: "\(activeDays)")
                yearStat("最长连续纪录", "\(maxEverRun)M")
                yearStat("总在座", Fmt.span(totalYear))
            }
            .padding(.top, 6)
        }
    }

    private func yearStat(_ label: String, _ v: String, of: String? = nil) -> some View {
        HStack(spacing: 6) {
            CJK(label, size: 12, color: PX.hull, tracking: 0.8)
            PixelText(v, scale: 1.8, color: PX.chalk)
            if let of { PixelText("/ \(of)", scale: 1.3, color: PX.bay) }
        }
    }

    private var activeDays: Int {
        engine.recentDays(365).compactMap { $0.1 }.filter { !$0.sessions.isEmpty }.count
    }

    private var compliantDays: Int {
        engine.recentDays(365).compactMap { $0.1 }
            .filter { !$0.sessions.isEmpty && $0.maxRun <= s.thresholdMin }.count
    }

    private var maxEverRun: Int {
        engine.recentDays(365).compactMap { $0.1 }.map(\.maxRun).max() ?? 0
    }

    private var totalYear: Int {
        engine.recentDays(365).compactMap { $0.1 }.map(\.total).reduce(0, +)
    }

    // MARK: 导出

    private var exportRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(PX.bay).frame(height: 2)
            HStack(spacing: 12) {
                pixelButton("导出 JSON") {
                    exportData()
                }
                pixelButton("打开数据文件夹") {
                    let dir = FileManager.default
                        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("TIESit")
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
                }
                Spacer()
            }
        }
        .padding(.top, 4)
    }

    private func exportData() {
        guard let data = engine.exportJSON() else {
            exportMsg = "生成数据失败。"
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tiesit-\(Fmt.dayKey(startHour: s.dayStartHour)).json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                exportMsg = "已导出到 \(url.lastPathComponent)"
            } catch {
                exportMsg = "写入失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: 小件

    private func sectionLabel(_ cn: String, _ en: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CJK(cn, size: 16, weight: .semibold, color: PX.chalk, tracking: 1.2)
            PixelText(en, scale: 1.1, color: PX.order)
        }
    }

    private func emptyHint(_ t: String) -> some View {
        CJK(t, size: 13, color: PX.bay, tracking: 0.6)
            .padding(.vertical, 18)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 9, height: 9)
            CJK(text, size: 11, color: PX.hull, tracking: 0.5)
        }
    }

    private var heatLegend: some View {
        HStack(spacing: 12) {
            CJK("少", size: 11, color: PX.bay, tracking: 0)
            ForEach(HeatGrid.levels, id: \.self) { c in
                Rectangle().fill(c).frame(width: 11, height: 11)
            }
            CJK("多", size: 11, color: PX.bay, tracking: 0)
            Rectangle().fill(PX.alert).frame(width: 11, height: 11)
            CJK("超标", size: 11, color: PX.bay, tracking: 0)
        }
    }

    private func pixelButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Chiptune.shared.click()
            action()
        } label: {
            CJK(title, size: 12, color: PX.hull, tracking: 0.8)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .pixelFrame(PX.bay)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 今日分段条

struct TimelineBar: View {
    var sessions: [SitSession]
    var threshold: Int
    var dayStartHour: Int = 0

    static func startMinute(for session: SitSession, dayStartHour: Int) -> Int {
        (session.hour * 60 + session.minute - dayStartHour * 60 + 1440) % 1440
    }

    var body: some View {
        Canvas { ctx, size in
            // 底槽 0-24 时
            ctx.fill(Path(CGRect(x: 0, y: size.height * 0.55, width: size.width, height: 6)),
                     with: .color(PX.dim))

            // 每段按时间映射到横向
            for sess in sessions {
                let startMin = Double(Self.startMinute(for: sess, dayStartHour: dayStartHour))
                let x = CGFloat(startMin / 1440.0) * size.width
                let w = min(size.width - x, max(3, CGFloat(Double(sess.minutes) / 1440.0) * size.width))
                let over = sess.minutes > threshold
                let h: CGFloat = over ? 46 : 26
                let y = size.height * 0.55 - h
                ctx.fill(Path(CGRect(x: x, y: y, width: w, height: h)),
                         with: .color(over ? PX.alert : PX.ok))

                // 顶点标记
                ctx.fill(Path(CGRect(x: x, y: y - 4, width: w, height: 3)),
                         with: .color(over ? PX.alert : PX.ok.opacity(0.6)))
            }

            // 小时刻度
            for h in stride(from: 0, through: 24, by: 6) {
                let x = CGFloat(h) / 24.0 * size.width
                ctx.fill(Path(CGRect(x: x, y: size.height * 0.55 + 12, width: 1, height: 8)),
                         with: .color(PX.bay))
            }
        }
    }
}

// MARK: - 30 天热力网格

struct HeatGrid: View {
    var days: [(Date, DayRecord?)]
    var threshold: Int

    static let levels: [Color] = [
        Color(rgb: 0x0A0A0A),
        Color(rgb: 0x1E2A18),
        Color(rgb: 0x3A5A2E),
        Color(rgb: 0x5E8C42),
        PX.ok
    ]

    var body: some View {
        Canvas { ctx, size in
            let cols = 10
            let rows = 3
            let gap: CGFloat = 6
            let cw = (size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let ch = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)

            for (i, item) in days.enumerated() {
                let c = i % cols
                let r = i / cols
                guard r < rows else { break }
                let rect = CGRect(x: CGFloat(c) * (cw + gap),
                                  y: CGFloat(r) * (ch + gap),
                                  width: cw, height: ch)
                ctx.fill(Path(rect), with: .color(color(for: item.1)))
            }
        }
    }

    private func color(for rec: DayRecord?) -> Color {
        guard let rec, !rec.sessions.isEmpty else { return HeatGrid.levels[0] }
        if rec.maxRun > threshold { return PX.alert }
        let t = Double(rec.maxRun) / Double(max(1, threshold))
        if t < 0.3 { return HeatGrid.levels[1] }
        if t < 0.6 { return HeatGrid.levels[2] }
        if t < 0.85 { return HeatGrid.levels[3] }
        return HeatGrid.levels[4]
    }
}

// MARK: - 52 周柱状

struct YearBars: View {
    var days: [(Date, DayRecord?)]
    var threshold: Int

    var body: some View {
        Canvas { ctx, size in
            // 按周聚合：每天切 7 天一组
            let weeks: [[(Date, DayRecord?)]] = stride(from: 0, to: days.count, by: 7).map {
                Array(days[$0..<min($0 + 7, days.count)])
            }
            guard !weeks.isEmpty else { return }

            let gap: CGFloat = 3
            let bw = max(2, (size.width - gap * CGFloat(weeks.count - 1)) / CGFloat(weeks.count))
            let baseY = size.height - 20

            // 阈值参考线
            ctx.fill(Path(CGRect(x: 0, y: baseY - 4, width: size.width, height: 1)),
                     with: .color(PX.order.opacity(0.35)))

            for (i, week) in weeks.enumerated() {
                let avgMax = week.compactMap { $0.1 }.map(\.maxRun)
                let v = avgMax.isEmpty ? 0 : avgMax.reduce(0, +) / avgMax.count
                let over = v > threshold
                let h = CGFloat(min(1.0, Double(v) / Double(max(1, threshold * 2)))) * (baseY - 6)
                let x = CGFloat(i) * (bw + gap)
                // 4px 步进的方块堆叠，不是平滑柱子
                let blocks = max(1, Int(h / 4))
                for b in 0..<blocks {
                    ctx.fill(Path(CGRect(x: x, y: baseY - CGFloat(b + 1) * 4,
                                         width: bw, height: 3)),
                             with: .color(over ? PX.alert : PX.ok.opacity(0.8)))
                }
            }

            // 月份刻度
            let labels = ["JAN", "MAR", "MAY", "JUL", "SEP", "NOV"]
            for (i, m) in labels.enumerated() {
                let x = CGFloat(i) / CGFloat(labels.count) * size.width
                PixelFont.draw(m, into: &ctx,
                               at: CGPoint(x: x, y: size.height - 12),
                               scale: 1.2, color: PX.bay)
            }
        }
    }
}

// MARK: - 全年网格

struct YearGrid: View {
    var days: [(Date, DayRecord?)]
    var threshold: Int

    var body: some View {
        Canvas { ctx, size in
            let weeks = (days.count + 6) / 7
            let gap: CGFloat = 2
            let cw = (size.width - gap * CGFloat(max(1, weeks - 1))) / CGFloat(max(1, weeks))
            let ch = (size.height - gap * 6) / 7

            for (i, item) in days.enumerated() {
                let col = i / 7
                let row = i % 7
                let rect = CGRect(x: CGFloat(col) * (cw + gap),
                                  y: CGFloat(row) * (ch + gap),
                                  width: min(cw, 9), height: min(ch, 9))
                ctx.fill(Path(rect), with: .color(color(for: item.1)))
            }
        }
    }

    private func color(for rec: DayRecord?) -> Color {
        guard let rec, !rec.sessions.isEmpty else { return HeatGrid.levels[0] }
        if rec.maxRun > threshold { return PX.alert }
        let t = Double(rec.maxRun) / Double(max(1, threshold))
        if t < 0.4 { return HeatGrid.levels[1] }
        if t < 0.7 { return HeatGrid.levels[2] }
        if t < 0.9 { return HeatGrid.levels[3] }
        return HeatGrid.levels[4]
    }
}