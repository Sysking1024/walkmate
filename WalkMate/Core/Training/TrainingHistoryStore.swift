import Foundation
import Observation

/// 一次训练的持久记录
struct TrainingRecord: Codable, Identifiable {
    struct Moment: Codable { let frameFileName: String; let text: String }

    let id: UUID
    let durationSeconds: Int
    let distanceMeters: Int
    let obstaclesAvoided: Int
    let moments: [Moment]
    let finishedAt: Date
    /// 使用者点了「记录路线」后标记为一条路线记录
    var savedAsRoute: Bool
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
    }

    /// 训练结束时记录一次，并尝试上传
    @discardableResult
    func record(_ result: TrainingResult) -> TrainingRecord {
        let record = TrainingRecord(
            id: UUID(), durationSeconds: result.durationSeconds, distanceMeters: result.distanceMeters,
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
