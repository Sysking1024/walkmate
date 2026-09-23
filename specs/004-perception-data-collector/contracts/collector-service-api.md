# 接口契约说明书：空间感知数据采集器与存储服务 API (004-perception-data-collector)

**特性分支**: `004-perception-data-collector`  
**创建日期**: 2026-09-23  
**状态**: 计划中 (Planned)

---

## 一、 数据采集协调器服务契约 (`PerceptionDataCollectorProtocol`)

负责连接感知主流水线，管理录制生命周期、异步投递与分级采样。

```swift
import Foundation
import CoreVideo

/// 数据采集控制状态
public enum CollectorState: String, Sendable {
    case idle = "待命中"
    case recording = "录制中"
    case stopping = "正在停止并保存"
}

/// 采集器生命周期与代理回调
public protocol PerceptionDataCollectorDelegate: AnyObject, Sendable {
    /// 采集状态变更
    func collector(_ collector: PerceptionDataCollectorProtocol, didChangeState state: CollectorState)
    /// 录制时长秒数心跳更新 (供 UI 显示动态数字 00:45)
    func collector(_ collector: PerceptionDataCollectorProtocol, didUpdateDuration seconds: Double)
    /// 采集异常 (如存储空间不足、写盘故障)
    func collector(_ collector: PerceptionDataCollectorProtocol, didEncounterError error: Error)
}

/// 空间感知数据采集器核心接口
public protocol PerceptionDataCollectorProtocol: AnyObject, Sendable {
    /// 代理接收器
    var delegate: PerceptionDataCollectorDelegate? { get set }
    /// 当前录制状态
    var state: CollectorState { get }
    /// 当前活动会话标识符 (若未录制则为 nil)
    var currentSessionId: String? { get }
    /// 当前已录制时长 (秒)
    var currentDuration: Double { get }
    
    /// 启动实测数据录制会话
    /// - Throws: 若存储空间不足或目录无法创建则抛出异常
    func startRecording() throws
    
    /// 结束实测数据录制会话
    /// - Parameter completion: 完成刷盘并安全关闭句柄后的回调 (返回会话元数据或错误)
    func stopRecording(completion: (@Sendable (Result<SessionMetadata, Error>) -> Void)?)
    
    /// 接收感知流水线派发的每一帧全量数据 (由主推理线程非阻塞异步提交)
    /// - Parameters:
    ///   - frame: 全景图像帧 (包含 pixelBuffer 与 IMU 姿态)
    ///   - depthMatrix: DAP 估计出的深度矩阵
    ///   - groundPlane: RANSAC 拟合出的地面方程参数 [A, B, C, D]
    ///   - cameraHeight: 估算的相机高度
    ///   - rawObstacles: 原始障碍物列表
    ///   - hazardObstacles: 过滤后的近身危险障碍物列表
    ///   - routeData: 可通行路线数据 (安全纵深、瓶颈净宽、航路点)
    ///   - activeObstacleTarget: 音频触发的障碍物目标坐标
    ///   - activeNavigationTarget: 音频触发的导航首航路点坐标
    ///   - latencyMs: 计算耗时
    func recordFrame(
        frame: PanoramicFrame,
        depthMatrix: DepthMatrix?,
        groundPlane: [Float],
        cameraHeight: Float,
        rawObstacles: [ObstacleItem],
        hazardObstacles: [ObstacleItem],
        routeData: PassableRouteData?,
        activeObstacleTarget: SIMD3<Float>?,
        activeNavigationTarget: SIMD3<Float>?,
        latencyMs: Double
    )
}
```

---

## 二、 会话存储与归档管理服务契约 (`SessionStorageManagerProtocol`)

负责沙盒磁盘管理、存储空间容量检查、目录枚举、删除清理以及利用既有 `SSZipArchive` 打包导出。

```swift
import Foundation

/// 会话存储管理错误定义
public enum SessionStorageError: LocalizedError, Sendable {
    case insufficientStorage(availableMB: Int, requiredMB: Int)
    case sessionNotFound(String)
    case archiveCreationFailed(String)
    case ioFailure(String)
    
    public var errorDescription: String? {
        switch self {
        case .insufficientStorage(let avail, let req):
            return "设备存储空间不足 (可用: \(avail)MB, 至少需要: \(req)MB)"
        case .sessionNotFound(let id):
            return "未能找到指定的实测会话: \(id)"
        case .archiveCreationFailed(let reason):
            return "会话打包压缩失败: \(reason)"
        case .ioFailure(let reason):
            return "文件存储读写错误: \(reason)"
        }
    }
}

/// 会话持久化与导出服务接口
public protocol SessionStorageManagerProtocol: Sendable {
    /// 沙盒内会话根目录 URL (Documents/Sessions/)
    var sessionsDirectoryURL: URL { get }
    
    /// 检查当前设备空闲存储空间是否满足录制要求 (默认 >= 500MB)
    /// - Parameter minRequiredMB: 最小要求兆字节数
    /// - Returns: 是否允许启动录制
    func hasSufficientStorage(minRequiredMB: Int) -> Bool
    
    /// 获取当前所有历史会话摘要列表 (按时间降序排列)
    func listSessions() -> [SessionSummaryItem]
    
    /// 删除指定会话及其包含的所有文件
    /// - Parameter sessionId: 会话标识符
    func deleteSession(sessionId: String) throws
    
    /// 清理所有历史会话
    func clearAllSessions() throws
    
    /// 将指定会话目录打包为 .zip 归档文件
    /// - Parameters:
    ///   - sessionId: 会话标识符
    ///   - progress: 可选压缩进度通知闭包
    /// - Returns: 生成的压缩包本地 URL
    func createArchive(sessionId: String, progress: ((Double) -> Void)?) throws -> URL
}
```

---

## 三、 离线回放测试套件执行器契约 (`PerceptionReplayerProtocol`)

供 Mac 开发机端在 `PerceptionReplayTests` 中执行真机数据集回灌：

```swift
import Foundation

/// 离线回放调优指标报告
public struct ReplayEvaluationReport: Sendable {
    /// 总回放帧数
    public let totalFrames: Int
    /// 成功规划出航路点的帧数
    public let passableFrames: Int
    /// 航路点生成成功率 (0.0 ~ 1.0)
    public var passableRate: Float {
        guard totalFrames > 0 else { return 0 }
        return Float(passableFrames) / Float(totalFrames)
    }
    /// 触发障碍物报警的帧数
    public let obstacleAlertFrames: Int
    /// 平均安全通行距离 (米)
    public let averageSafeDepth: Float
}

/// 离线回放驱动器接口
public protocol PerceptionReplayerProtocol: Sendable {
    /// 载入解压后的会话目录
    /// - Parameter sessionURL: 会话本地文件夹路径
    func loadSession(at sessionURL: URL) throws -> SessionMetadata
    
    /// 执行逐帧回放并接入感知算法进行重新计算
    /// - Parameters:
    ///   - onFrameEvaluated: 每一帧重算后的回调 (传入原始记录与重算后产生的结果)
    /// - Returns: 总体准确率与评估报告
    func executeReplay(
        onFrameEvaluated: ((_ original: FrameTelemetryRecord, _ recomputedRoute: PassableRouteData?, _ recomputedObstacles: [ObstacleItem]) -> Void)?
    ) throws -> ReplayEvaluationReport
}
```
