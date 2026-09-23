import Foundation
import Observation

/// 训练类型，对应训练页的档位
enum TrainingKind: String, Codable, CaseIterable {
    /// 室内基础避障
    case indoor
    /// 半开放环境：小区路线
    case neighborhood

    var title: String {
        switch self {
        case .indoor: return "室内基础避障"
        case .neighborhood: return "小区路线"
        }
    }
}

/// 一次训练的持久记录
struct TrainingRecord: Codable, Identifiable {
    struct Moment: Codable { let frameFileName: String; let text: String }

    let id: UUID
    var kind: TrainingKind = .indoor
    let durationSeconds: Int
    let distanceMeters: Int
    let obstaclesAvoided: Int
    let moments: [Moment]
    let finishedAt: Date
    /// 使用者点了「记录路线」后标记为一条路线记录
    var savedAsRoute: Bool

    init(id: UUID, kind: TrainingKind, durationSeconds: Int, distanceMeters: Int, obstaclesAvoided: Int,
         moments: [Moment], finishedAt: Date, savedAsRoute: Bool) {
        self.id = id; self.kind = kind; self.durationSeconds = durationSeconds; self.distanceMeters = distanceMeters
        self.obstaclesAvoided = obstaclesAvoided; self.moments = moments; self.finishedAt = finishedAt; self.savedAsRoute = savedAsRoute
    }

    /// 旧记录没有 kind 字段，按室内处理
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decodeIfPresent(TrainingKind.self, forKey: .kind) ?? .indoor
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        distanceMeters = try container.decode(Int.self, forKey: .distanceMeters)
        obstaclesAvoided = try container.decode(Int.self, forKey: .obstaclesAvoided)
        moments = try container.decode([Moment].self, forKey: .moments)
        finishedAt = try container.decode(Date.self, forKey: .finishedAt)
        savedAsRoute = try container.decode(Bool.self, forKey: .savedAsRoute)
    }
}

/// 训练记录的本地持久化与后端上传。进度页与成长详情的数据全部来自这里。
@MainActor
@Observable
final class TrainingHistoryStore {

    static let shared = TrainingHistoryStore()

    private(set) var records: [TrainingRecord] = []
    private let fileURL: URL
    private let backend = BackendClient.shared

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("training_history.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([TrainingRecord].self, from: data) {
            records = saved
        }
        seedDemoHistoryIfNeeded()
    }

    /// 首次启动写入一段演示历史，让本周记录、徽章、路线与档位解锁互相对得上：
    /// 连续 5 天室内训练（解锁「KEEP GOING」）、2 次小区路线、昨天一次 320 米避障 20 次、今早一次 18 分钟。
    /// 种子分版本：已装过旧版种子的手机只补今天这一条。
    private func seedDemoHistoryIfNeeded() {
        let versionKey = "walkmate.historySeedVersion"
        let legacyFlag = "walkmate.historySeeded"
        var version = UserDefaults.standard.integer(forKey: versionKey)
        if version == 0, UserDefaults.standard.bool(forKey: legacyFlag) { version = 1 }
        guard version < 2 else { return }

        let calendar = Calendar.current
        func day(_ daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
            return calendar.date(byAdding: .minute, value: hour * 60 + minute, to: base)!
        }
        // (几天前, 小时, 类型, 秒, 米, 避障, 记为路线)
        let history: [(Int, Int, TrainingKind, Int, Int, Int, Bool)] = [
            (7, 10, .indoor, 14 * 60, 180, 8, false),
            (6, 10, .indoor, 16 * 60, 210, 11, false),
            (5, 9, .indoor, 18 * 60, 240, 12, false),
            (4, 10, .neighborhood, 26 * 60, 640, 5, true),
            (4, 17, .indoor, 15 * 60, 200, 10, false),
            (3, 10, .indoor, 20 * 60, 260, 14, false),
            (2, 9, .neighborhood, 24 * 60, 650, 4, true),
            (1, 10, .indoor, 22 * 60, 320, 20, false),
        ]
        let today: (Int, Int, TrainingKind, Int, Int, Int, Bool) = (0, 8, .indoor, 18 * 60, 230, 12, false)

        func make(_ seed: (Int, Int, TrainingKind, Int, Int, Int, Bool)) -> TrainingRecord {
            TrainingRecord(id: UUID(), kind: seed.2, durationSeconds: seed.3, distanceMeters: seed.4, obstaclesAvoided: seed.5,
                           moments: [], finishedAt: day(seed.0, hour: seed.1, minute: 30), savedAsRoute: seed.6)
        }

        if records.isEmpty {
            records = (history + [today]).map(make)
        } else if !records.contains(where: { calendar.isDateInToday($0.finishedAt) }) {
            records.append(make(today))
        }
        records.sort { $0.finishedAt > $1.finishedAt }
        persist()
        UserDefaults.standard.set(2, forKey: versionKey)
        Log.info("演示训练历史已就绪，共 \(records.count) 条", category: .general)
    }

    /// 训练结束时记录一次，并尝试上传
    @discardableResult
    func record(_ result: TrainingResult) -> TrainingRecord {
        let record = TrainingRecord(
            id: UUID(), kind: result.kind, durationSeconds: result.durationSeconds, distanceMeters: result.distanceMeters,
            obstaclesAvoided: result.obstaclesAvoided,
            moments: result.moments.map { .init(frameFileName: $0.frameURL.lastPathComponent, text: $0.narration.text) },
            finishedAt: result.finishedAt, savedAsRoute: false
        )
        records.insert(record, at: 0)
        persist()
        Task { [backend] in
            do { try await backend.uploadSession(record) }
            catch { Log.warning("训练记录上传失败，已保存在本地：\(error)", category: .general) }
        }
        return record
    }

    func markAsRoute(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].savedAsRoute = true
        persist()
    }

    // MARK: - 统计

    /// 最近 7 天有训练的天数
    var trainingDaysThisWeek: Int {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date()))!
        let days = Set(records.filter { $0.finishedAt >= cutoff }.map { calendar.startOfDay(for: $0.finishedAt) })
        return days.count
    }

    var obstaclesThisWeek: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))!
        return records.filter { $0.finishedAt >= cutoff }.reduce(0) { $0 + $1.obstaclesAvoided }
    }

    /// 独立完成指数：没有向伙伴求助（没有留下时刻）就完成的训练占比
    var independentRate: Double {
        guard !records.isEmpty else { return 0 }
        return Double(records.filter { $0.moments.isEmpty }.count) / Double(records.count)
    }

    /// 最近 7 天每天的训练分钟数，从 6 天前到今天
    var minutesPerDay: [(date: Date, minutes: Int)] {
        let calendar = Calendar.current
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: Date()))!
            let seconds = records.filter { calendar.isDate($0.finishedAt, inSameDayAs: day) }.reduce(0) { $0 + $1.durationSeconds }
            return (day, seconds / 60)
        }
    }

    var routeRecords: [TrainingRecord] { records.filter(\.savedAsRoute) }

    func records(of kind: TrainingKind) -> [TrainingRecord] { records.filter { $0.kind == kind } }

    // MARK: - 档位解锁

    /// 半开放环境：完成 5 次室内训练，其中至少 3 次避障不少于 10 次
    var isSemiOpenUnlocked: Bool {
        let indoor = records(of: .indoor)
        return indoor.count >= 5 && indoor.filter { $0.obstaclesAvoided >= 10 }.count >= 3
    }

    /// 户外独立出行：完成 5 次半开放训练，并在小区路线上走完 3 次
    var isOutdoorUnlocked: Bool {
        records(of: .neighborhood).count >= 5 && routeRecords.filter { $0.kind == .neighborhood }.count >= 3
    }

    /// 下一目标的文案，供进度页里程碑展示
    var nextGoalText: (title: String, detail: String) {
        if !isSemiOpenUnlocked {
            let remaining = max(0, 5 - records(of: .indoor).count)
            return ("半开放路线", "再完成\(remaining)次室内训练即可解锁")
        }
        if !isOutdoorUnlocked {
            let remaining = max(0, 5 - records(of: .neighborhood).count)
            return ("户外独立出行", "再完成\(remaining)次小区路线即可解锁")
        }
        return ("户外独立出行", "已解锁，去真实街道上走走吧")
    }

    /// 最近一次剪出的集锦。总结页生成后复制到这里，社群页据此提供分享。
    static var latestReelURL: URL? {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("latest_highlight.mp4")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 把刚生成的集锦存为最近一次
    static func keepAsLatestReel(_ source: URL) {
        let target = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("latest_highlight.mp4")
        do {
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            Log.warning("集锦留存失败：\(error)", category: .recording)
        }
    }

    private func persist() {
        do { try JSONEncoder().encode(records).write(to: fileURL) }
        catch { Log.error("训练记录保存失败：\(error)", category: .general) }
    }
}
