import Foundation
import Combine
import AppKit

/// 强制下班：当天累计在座达到这个分钟数就弹下班令
let curfewLimitMin = 600

// MARK: - 数据模型

struct SitSettings: Codable, Equatable {
    var thresholdMin: Int = 45      // 触发阈值
    var restMin: Int = 5            // 休息时长
    var holdSec: Int = 5            // 长按要求
    var soundOn: Bool = true
    var sceneMotionOn: Bool = true
    var scanlinesOn: Bool = true
    var launchAtLogin: Bool = true
    var forceEndOfDay: Bool = false // 强制下班，默认关
    var dayStartHour: Int = 0       // 一天从几点切分

    init() {}

    private enum CodingKeys: String, CodingKey {
        case thresholdMin, restMin, holdSec, soundOn, sceneMotionOn, scanlinesOn, launchAtLogin, forceEndOfDay, dayStartHour
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        thresholdMin = try values.decodeIfPresent(Int.self, forKey: .thresholdMin) ?? thresholdMin
        restMin = try values.decodeIfPresent(Int.self, forKey: .restMin) ?? restMin
        holdSec = try values.decodeIfPresent(Int.self, forKey: .holdSec) ?? holdSec
        soundOn = try values.decodeIfPresent(Bool.self, forKey: .soundOn) ?? soundOn
        sceneMotionOn = try values.decodeIfPresent(Bool.self, forKey: .sceneMotionOn) ?? sceneMotionOn
        scanlinesOn = try values.decodeIfPresent(Bool.self, forKey: .scanlinesOn) ?? scanlinesOn
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? launchAtLogin
        forceEndOfDay = try values.decodeIfPresent(Bool.self, forKey: .forceEndOfDay) ?? forceEndOfDay
        dayStartHour = try values.decodeIfPresent(Int.self, forKey: .dayStartHour) ?? dayStartHour
        if ![25, 45, 60, 90].contains(thresholdMin) { thresholdMin = 45 }
        if ![0, 2, 5, 10].contains(restMin) { restMin = 5 }
        if ![3, 5, 8].contains(holdSec) { holdSec = 5 }
        if ![0, 2, 4].contains(dayStartHour) { dayStartHour = 0 }
    }
}

struct SitSession: Codable, Equatable {
    var hour: Int
    var minute: Int
    var minutes: Int      // 连续在座分钟数
    var date: Date
}

struct DayRecord: Codable, Equatable {
    var sessions: [SitSession] = []
    var stands: Int = 0        // 起身次数
    var maxRun: Int = 0        // 当日最长连续(分钟)
    var total: Int = 0         // 当日累计在座(分钟)

    mutating func add(_ s: SitSession) {
        sessions.append(s)
        total += s.minutes
        maxRun = max(maxRun, s.minutes)
    }
}

struct Store: Codable {
    var version: Int = 1
    var settings: SitSettings = SitSettings()
    var days: [String: DayRecord] = [:]
    var checkpoint: RunCheckpoint?

    init() {}

    private enum CodingKeys: String, CodingKey { case version, settings, days, checkpoint }
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        settings = try values.decodeIfPresent(SitSettings.self, forKey: .settings) ?? SitSettings()
        days = try values.decodeIfPresent([String: DayRecord].self, forKey: .days) ?? [:]
        // 不支持的检查点不能拖累已经完成的历史统计。
        checkpoint = try? values.decodeIfPresent(RunCheckpoint.self, forKey: .checkpoint)
    }
}

// MARK: - 状态机

struct RunCheckpoint: Codable {
    var dayKey: String
    var savedAt: Date
    var state: SitState
    var elapsed: TimeInterval
    var restRemaining: TimeInterval
    var destinationID: Int? = nil
    var startedAt: Date? = nil
}

enum SitState: String, Codable {
    case sitting
    case alert
    case resting
    case endOfDay     // 下班令：只能点「下班」，不能长按解除
    case offDuty      // 已下班，当天不再计时
}

// MARK: - 引擎

@MainActor
final class SitEngine: ObservableObject {

    @Published private(set) var state: SitState = .sitting
    @Published private(set) var elapsed: TimeInterval = 0     // 本次在座已累积秒
    @Published private(set) var restRemaining: TimeInterval = 0
    @Published var settings: SitSettings
    @Published private(set) var storageIssue: String?
    private var loadIssue: String?
    private var storageCanWrite = true
    @Published private(set) var today: DayRecord

    /// 警报页上的统计（进入警报时快照）
    @Published private(set) var alertSnapshot: (run: Int, standsToday: Int, totalToday: Int) = (0, 0, 0)

    /// 本段在座要飞往的星球；每次进入 sitting 时随机抽一个
    @Published private(set) var destination: Planet = Planet.all[0]
    /// 飞船造型，跟着用户上次的选择走
    @Published private(set) var shipShape: ShipShape = .xwing
    @Published private(set) var fixedDestinationID: Int?
    private let preferences: UserDefaults

    private struct PreviewSnapshot {
        var state: SitState
        var elapsed: TimeInterval
        var restRemaining: TimeInterval
        var alert: (run: Int, standsToday: Int, totalToday: Int)
    }
    private var previewSnapshot: PreviewSnapshot?
    var isPreview: Bool { previewSnapshot != nil }

    private var store: Store
    private var ticker: Timer?
    private var lastSavedAt: Date
    private var runStartedAt: Date
    private var lastTick: Date
    /// 当前 `today` 对应的存储 key，跨天时靠它判断要不要换天
    private var currentKey: String

    private let dataURL: URL

    // 回调
    var onAlert: (() -> Void)?
    var onRestEnd: (() -> Void)?
    /// 跨天后下班令自动失效，需要收掉遮罩（遮罩不该由引擎直接关）
    var onCurfewExpired: (() -> Void)?

    init(dataURL suppliedURL: URL? = nil, now: Date = Date(), startAutomatically: Bool = true, preferences: UserDefaults = .standard) {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TIESit", isDirectory: true)
        let fileURL = suppliedURL ?? dir.appendingPathComponent("data.json")
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let loadResult = SitEngine.load(fileURL)
        var loaded = loadResult.store
        let key = Fmt.dayKey(now, startHour: loaded.settings.dayStartHour)
        if let saved = loaded.checkpoint, saved.dayKey != key, saved.elapsed >= 60 {
            var previous = loaded.days[saved.dayKey] ?? DayRecord()
            let start = saved.startedAt ?? saved.savedAt.addingTimeInterval(-saved.elapsed)
            previous.add(SitSession(hour: Calendar.current.component(.hour, from: start),
                                    minute: Calendar.current.component(.minute, from: start),
                                    minutes: Int(saved.elapsed / 60), date: start))
            loaded.days[saved.dayKey] = previous
            loaded.checkpoint = nil
        }
        self.preferences = preferences
        dataURL = fileURL
        store = loaded
        settings = loaded.settings
        currentKey = key
        today = loaded.days[key] ?? DayRecord()
        lastTick = now
        runStartedAt = now
        lastSavedAt = now
        loadIssue = loadResult.issue
        storageIssue = loadResult.issue
        storageCanWrite = loadResult.canWrite
        if let raw = preferences.string(forKey: "tiesit.ship"), let shape = ShipShape(rawValue: raw) {
            shipShape = shape
        }
        if let id = preferences.object(forKey: "tiesit.planet") as? Int,
           let planet = Planet.all.first(where: { $0.id == id }) {
            fixedDestinationID = id
            destination = planet
        } else {
            destination = DestinationPool.pick(excluding: nil, preferences: preferences)
        }

        if let saved = loaded.checkpoint, saved.dayKey == key || saved.state == .resting {
            if fixedDestinationID == nil, let id = saved.destinationID,
               let planet = Planet.all.first(where: { $0.id == id }) {
                destination = planet
            }
            runStartedAt = min(now, saved.startedAt ?? saved.savedAt.addingTimeInterval(-saved.elapsed))
            state = saved.state
            elapsed = saved.dayKey == key ? max(0, saved.elapsed) : 0
            restRemaining = max(0, saved.restRemaining)
            if state == .resting {
                restRemaining = max(0, restRemaining - max(0, now.timeIntervalSince(saved.savedAt)))
                if restRemaining == 0 { state = .sitting; beginNewRun(now: now) }
            }
            if !settings.forceEndOfDay && (state == .endOfDay || state == .offDuty) {
                state = .sitting
            }
            alertSnapshot = (max(1, Int(elapsed / 60)), today.stands, daySitMinutes)
        }
        if startAutomatically {
            startTicker()
            observeSleep()
        }
    }

    // MARK: 持久化

    private static func load(_ url: URL) -> (store: Store, issue: String?, canWrite: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (Store(), nil, true) }
        do {
            return (try JSONDecoder().decode(Store.self, from: Data(contentsOf: url)), nil, true)
        } catch {
            let backup = url.deletingPathExtension()
                .appendingPathExtension("recovery-\(UUID().uuidString).json")
            do {
                try FileManager.default.copyItem(at: url, to: backup)
                return (Store(), "数据无法读取，原文件已保留备份，可在统计页打开数据目录。", true)
            } catch {
                return (Store(), "无法读取原数据，已暂停保存。请修复文件权限后重新启动。", false)
            }
        }
    }

    private func saveStore(now: Date = Date()) {
        guard storageCanWrite else { return }
        store.settings = settings
        store.days[currentKey] = today
        store.checkpoint = currentCheckpoint(now: now)
        do {
            let data = try JSONEncoder().encode(store)
            try data.write(to: dataURL, options: .atomic)
            lastSavedAt = now
            storageIssue = loadIssue
        } catch {
            storageIssue = "数据尚未保存，请检查磁盘空间或文件权限后重试。"
        }
    }

    func persist(now: Date = Date()) {
        rolloverIfNeeded(now)
        saveStore(now: now)
    }

    private func currentCheckpoint(now: Date) -> RunCheckpoint {
        RunCheckpoint(dayKey: currentKey, savedAt: now,
                      state: previewSnapshot?.state ?? state,
                      elapsed: previewSnapshot?.elapsed ?? elapsed,
                      restRemaining: previewSnapshot?.restRemaining ?? restRemaining,
                      destinationID: destination.id, startedAt: runStartedAt)
    }

    func exportJSON() -> Data? {
        var s = store
        s.settings = settings
        s.days[currentKey] = today
        s.checkpoint = currentCheckpoint(now: Date())
        return try? JSONEncoder().encode(s)
    }

    /// 跨过「一天从几点算」的日界时，把旧的一天落盘、换上新的一天。
    /// 返回是否真的换天了。
    @discardableResult
    private func rolloverIfNeeded(_ now: Date) -> Bool {
        let key = Fmt.dayKey(now, startHour: settings.dayStartHour)
        guard key != currentKey else { return false }

        let wasPreview = restorePreview(now: now)
        // 日界前尚未解除的一段也要入账，但不增加起身次数。
        let minutes = Int(elapsed / 60)
        if minutes > 0 {
            let start = runStartedAt
            today.add(SitSession(hour: Calendar.current.component(.hour, from: start),
                                 minute: Calendar.current.component(.minute, from: start),
                                 minutes: minutes, date: start))
        }
        store.days[currentKey] = today
        currentKey = key
        today = store.days[key] ?? DayRecord()
        // 新的一天重新计算在座时长；昨天没解除的那一段不跨天累加
        elapsed = 0
        runStartedAt = now
        if state == .offDuty { state = .sitting }
        // 跨天时如果下班令还压在屏幕上，内容已经过期（今天的数已清零），收掉它
        if state == .endOfDay || state == .alert {
            state = .sitting
            onCurfewExpired?()
        }
        if state == .sitting { beginNewRun(now: now) }
        if wasPreview { onCurfewExpired?() }
        return true
    }

    // MARK: 计时

    private func startTicker() {
        ticker?.invalidate()
        // 不用 scheduledTimer：它默认挂在 .default 模式，
        // 用户拖动窗口/打开菜单时会被暂停，倒计时就会卡住。
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func tick(now: Date = Date(), idleSeconds: Double? = nil) {
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        if rolloverIfNeeded(now) { saveStore(now: now) }
        defer {
            if now.timeIntervalSince(lastSavedAt) >= 30 { saveStore(now: now) }
        }
        guard dt > 0, dt < 120 || state == .resting else { return }   // 异常跳变直接丢弃

        switch state {
        case .sitting:
            if (idleSeconds ?? IdleMonitor.secondsSinceLastInput()) > 300 { return }           // 人不在，不累积
            elapsed += dt
            if settings.forceEndOfDay, today.total + Int(elapsed / 60) >= curfewLimitMin {
                triggerCurfew(now: now)
            } else if Double(settings.thresholdMin * 60) <= elapsed {
                triggerAlert(now: now)
            }

        case .resting:
            restRemaining -= dt
            if restRemaining <= 0 {
                restRemaining = 0
                finishRest(now: now)
            }

        case .alert, .endOfDay, .offDuty:
            break
        }
    }

    // MARK: 状态迁移

    private func triggerAlert(now: Date = Date()) {
        state = .alert
        let runMin = max(1, Int(elapsed / 60))
        alertSnapshot = (runMin, today.stands, daySitMinutes)
        saveStore(now: now)
        onAlert?()
    }

    private func triggerCurfew(now: Date = Date()) {
        state = .endOfDay
        saveStore(now: now)
        onAlert?()
    }

    /// 长按完成
    func unlock(now: Date = Date()) {
        guard state == .alert else { return }
        if restorePreview(now: now) { persist(now: now); return }

        recordCurrentRun(now: now)
        elapsed = 0
        restRemaining = Double(settings.restMin * 60)
        state = settings.restMin > 0 ? .resting : .sitting
        if state == .sitting { beginNewRun(now: now) }
        persist(now: now)
    }

    /// 下班令点「下班」：记下这一段，当天不再计时，明早自动恢复
    func endShift(now: Date = Date()) {
        guard state == .endOfDay else { return }
        if restorePreview(now: now) { persist(now: now); return }
        recordCurrentRun(now: now)
        elapsed = 0
        state = .offDuty
        persist(now: now)
    }

    private func recordCurrentRun(now: Date) {
        let runMin = Int(elapsed / 60)
        if runMin > 0 {
            let cal = Calendar.current
            today.add(SitSession(hour: cal.component(.hour, from: runStartedAt),
                                 minute: cal.component(.minute, from: runStartedAt),
                                 minutes: runMin, date: runStartedAt))
        }
        today.stands += 1
    }

    /// 进入新的在座区间：抽一颗新星球，飞船重新起飞
    private func beginNewRun(now: Date) {
        runStartedAt = now
        if let id = fixedDestinationID, let fixed = Planet.all.first(where: { $0.id == id }) {
            destination = fixed
        } else {
            destination = DestinationPool.pick(excluding: destination, preferences: preferences)
        }
        elapsed = 0
    }

    private func finishRest(now: Date) {
        state = .sitting
        beginNewRun(now: now)
        persist(now: now)
        onRestEnd?()
    }

    // 外观选择立即生效，只修改偏好，不重置计时。
    func selectShip(_ shape: ShipShape) {
        shipShape = shape
        preferences.set(shape.rawValue, forKey: "tiesit.ship")
    }

    func selectPlanet(_ planet: Planet) {
        fixedDestinationID = planet.id
        destination = planet
        preferences.set(planet.id, forKey: "tiesit.planet")
    }

    func selectRandomPlanet() {
        fixedDestinationID = nil
        preferences.removeObject(forKey: "tiesit.planet")
        destination = DestinationPool.pick(excluding: destination, preferences: preferences)
    }

    // MARK: 预览（不写入真实计时和统计）

    private func beginPreview(_ target: SitState) {
        guard state == .sitting, previewSnapshot == nil else { return }
        previewSnapshot = PreviewSnapshot(state: state, elapsed: elapsed,
                                          restRemaining: restRemaining, alert: alertSnapshot)
        alertSnapshot = (elapsed < 60 ? settings.thresholdMin : Int(elapsed / 60),
                         today.stands, daySitMinutes)
        state = target
        onAlert?()
    }

    @discardableResult
    private func restorePreview(now: Date) -> Bool {
        guard let saved = previewSnapshot else { return false }
        previewSnapshot = nil
        state = saved.state
        elapsed = saved.elapsed
        restRemaining = saved.restRemaining
        alertSnapshot = saved.alert
        lastTick = now
        return true
    }

    func cancelPreview(now: Date = Date()) {
        guard restorePreview(now: now) else { return }
        persist(now: now)
    }

    func debugTriggerAlert() { beginPreview(.alert) }
    func debugTriggerCurfew() { beginPreview(.endOfDay) }

    // MARK: 设置

    func apply(_ s: SitSettings, now: Date = Date()) {
        let previousRestMin = settings.restMin
        let dayBoundaryChanged = s.dayStartHour != settings.dayStartHour
        settings = s

        if !s.forceEndOfDay && !isPreview {
            if state == .offDuty {
                state = .sitting
                beginNewRun(now: now)
            } else if state == .endOfDay {
                // 下班令还压在屏幕上，用户把开关关了：收掉
                state = .sitting
                onCurfewExpired?()
            }
        }

        if state == .resting && s.restMin != previousRestMin {
            let completed = max(0, Double(previousRestMin * 60) - restRemaining)
            restRemaining = max(0, Double(s.restMin * 60) - completed)
            if restRemaining == 0 { finishRest(now: now) }
        }
        // 换天口径变了要立刻按新口径重新归位，否则今天的数会写到别的 key 上
        if dayBoundaryChanged { rolloverIfNeeded(now) }
        persist(now: now)
    }

    /// 主界面点一下循环切换阈值
    func cycleThreshold() {
        let options = [25, 45, 60, 90]
        let idx = options.firstIndex(of: settings.thresholdMin) ?? 1
        settings.thresholdMin = options[(idx + 1) % options.count]
        persist()
    }

    // MARK: 派生量

    var remaining: TimeInterval {
        max(0, Double(settings.thresholdMin * 60) - elapsed)
    }

    var progress: Double {
        let t = Double(settings.thresholdMin * 60)
        return t > 0 ? (elapsed / t).clamped(to: 0...1) : 0
    }

    var restProgress: Double {
        let t = Double(settings.restMin * 60)
        return t > 0 ? (1 - restRemaining / t).clamped(to: 0...1) : 1
    }

    /// 用于显示的快照，包含正在进行的一段，不写回已完成记录。
    var todayIncludingCurrentRun: DayRecord {
        var record = today
        let minutes = Int(elapsed / 60)
        if minutes > 0 {
            let cal = Calendar.current
            record.add(SitSession(hour: cal.component(.hour, from: runStartedAt),
                                  minute: cal.component(.minute, from: runStartedAt),
                                  minutes: minutes, date: runStartedAt))
        }
        return record
    }

    /// 当天累计在座（含正在累积的这一段），用于强制下班判断
    var daySitMinutes: Int {
        today.total + Int(elapsed / 60)
    }

    // MARK: 休眠

    private func observeSleep() {
        let wc = NSWorkspace.shared.notificationCenter
        wc.addObserver(forName: NSWorkspace.willSleepNotification,
                       object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.lastTick = Date()
                self?.persist()
            }
        }
        wc.addObserver(forName: NSWorkspace.didWakeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        }
    }

    func handleWake(now: Date = Date()) {
        if state == .resting {
            tick(now: now)
        } else {
            // 即使只睡了几秒，也不能把睡眠时间算进在座区间。
            lastTick = now
            persist(now: now)
        }
    }

    // MARK: 统计查询

    /// 「逻辑日」的零点：把 dayStartHour 减掉的日界换算回普通日期
    private var logicalToday: Date {
        Fmt.logicalDayStart(startHour: settings.dayStartHour)
    }

    /// 近 N 天，按时间正序
    func recentDays(_ n: Int) -> [(Date, DayRecord?)] {
        let cal = Calendar.current
        let anchor = logicalToday
        return (0..<n).reversed().compactMap { i in
            guard let d = cal.date(byAdding: .day, value: -i, to: anchor) else { return nil }
            let key = Fmt.formatDay(d)
            let rec = key == currentKey ? todayIncludingCurrentRun : store.days[key]
            let real = cal.date(byAdding: .hour, value: settings.dayStartHour, to: d) ?? d
            return (real, rec)
        }
    }

    /// 连续达标天数（从昨天往前数，今天未结束不算失败）
    var streak: Int {
        let cal = Calendar.current
        var count = 0
        var cursor = logicalToday

        // 今天单独判断：暂时达标就算
        let todayRec = Fmt.formatDay(cursor) == currentKey ? todayIncludingCurrentRun : store.days[Fmt.formatDay(cursor)]
        if let t = todayRec, t.maxRun > settings.thresholdMin {
            return 0
        } else {
            count = 1
        }

        cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        for _ in 0..<365 {
            guard let r = store.days[Fmt.formatDay(cursor)], !r.sessions.isEmpty else { break }
            if r.maxRun > settings.thresholdMin { break }
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    var avg7: Int {
        let days = recentDays(7).compactMap { $0.1 }
        guard !days.isEmpty else { return 0 }
        return days.map(\.total).reduce(0, +) / days.count
    }
}