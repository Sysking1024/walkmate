import CoreMotion
import Foundation
import Observation

/// 一次训练的结果，交给总结页展示
struct TrainingResult: Hashable {
    let kind: TrainingKind
    let durationSeconds: Int
    let distanceMeters: Int
    let obstaclesAvoided: Int
    /// 训练中留下的时刻，用于生成集锦与回听
    let moments: [CompanionSession.Moment]
    let finishedAt: Date

    static func == (lhs: TrainingResult, rhs: TrainingResult) -> Bool { lhs.finishedAt == rhs.finishedAt }
    func hash(into hasher: inout Hasher) { hasher.combine(finishedAt) }
}

/// 训练中的状态：计时、步行距离、避障计数，并托管伙伴会话。
///
/// 避障次数的判定是一条简单启发式：感知层检出的障碍从有变无，记为一次成功避开。
/// 感知层本身不区分「绕开了」和「障碍离开了」，正式版需要更严格的判据。
@MainActor
@Observable
final class TrainingSessionModel {

    let kind: TrainingKind

    private(set) var elapsedSeconds = 0
    private(set) var distanceMeters = 0
    private(set) var obstaclesAvoided = 0
    let companion = CompanionSession()

    private var startedAt = Date()
    private var ticker: Timer?
    private let pedometer = CMPedometer()
    private var lastObstacleCount = 0

    init(kind: TrainingKind) { self.kind = kind }

    func start() {
        startedAt = Date()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsedSeconds = Int(Date().timeIntervalSince(self?.startedAt ?? Date())) }
        }
        companion.start()
        startPedometer()
        Log.info("训练开始：\(kind.title)", category: .ui)
    }

    /// 结束训练，返回结果
    func finish() -> TrainingResult {
        ticker?.invalidate(); ticker = nil
        pedometer.stopUpdates()
        companion.stop()
        Log.info("训练结束：\(elapsedSeconds) 秒，\(distanceMeters) 米，避障 \(obstaclesAvoided) 次，时刻 \(companion.moments.count) 个", category: .ui)
        return TrainingResult(
            kind: kind,
            durationSeconds: elapsedSeconds,
            distanceMeters: distanceMeters,
            obstaclesAvoided: obstaclesAvoided,
            moments: companion.moments,
            finishedAt: Date()
        )
    }

    /// 由界面在感知层障碍数变化时调用
    func updateObstacleCount(_ count: Int) {
        if lastObstacleCount > 0, count == 0 { obstaclesAvoided += 1 }
        lastObstacleCount = count
    }

    /// 步行距离来自手机计步器，是真实数据；设备不支持时保持为 0
    private func startPedometer() {
        guard CMPedometer.isDistanceAvailable() else { return }
        pedometer.startUpdates(from: startedAt) { [weak self] data, _ in
            guard let meters = data?.distance?.intValue else { return }
            Task { @MainActor in self?.distanceMeters = meters }
        }
    }

    var elapsedText: String {
        String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }
}
