import Foundation
import simd

/// 驻足检测器：根据相机 IMU 的加速度判断使用者是否已经停下来。
///
/// 数据源是相机自带的 IMU，随 `PanoramicFrame` 逐帧到达。相机佩戴在身上，
/// 比手机传感器更能反映身体本身的运动。
///
/// 判定方式：取最近一秒内加速度模长的标准差。行走时身体起伏会让模长
/// 以每秒两三米每平方秒的幅度摆动；站定时即便手持也只有零点几。
/// 只用模长而不用三轴分量，是为了对相机的佩戴姿态不敏感。
///
/// 纯逻辑、不读时钟，时间戳由调用方传入，可完整单元测试。
struct StandstillDetector {

    /// 统计窗口长度（毫秒）
    static let windowMs: Int64 = 1_000
    /// 判定为静止的标准差上限（米每平方秒）。这个值需要在真机上校准。
    static let motionThreshold: Float = 0.35
    /// 窗口内至少要有多少个样本才做判定，避免刚开始时误判
    static let minimumSamples = 5

    private var samples: [(timestampMs: Int64, magnitude: Float)] = []
    /// 连续静止的起点；正在运动时为 nil
    private var stillSinceMs: Int64?

    /// 送入一条加速度样本，返回截至此刻已连续静止的毫秒数；正在运动时返回 0。
    mutating func ingest(acceleration: SIMD3<Float>, timestampMs: Int64) -> Int {
        samples.append((timestampMs, simd_length(acceleration)))
        samples.removeAll { timestampMs - $0.timestampMs > Self.windowMs }

        guard samples.count >= Self.minimumSamples else {
            stillSinceMs = nil
            return 0
        }

        let mean = samples.reduce(0) { $0 + $1.magnitude } / Float(samples.count)
        let variance = samples.reduce(0) { $0 + ($1.magnitude - mean) * ($1.magnitude - mean) } / Float(samples.count)
        let deviation = variance.squareRoot()

        guard deviation < Self.motionThreshold else {
            stillSinceMs = nil
            return 0
        }

        let since = stillSinceMs ?? timestampMs
        stillSinceMs = since
        return Int(timestampMs - since)
    }

    /// 清空历史，重新开始统计
    mutating func reset() {
        samples.removeAll()
        stillSinceMs = nil
    }
}
