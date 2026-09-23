//
//  PerceptionDataCollector.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import CoreImage
import CoreVideo
import Foundation
import ImageIO
import simd

// MARK: - 采集控制状态与协议

/// 数据采集控制状态
public enum CollectorState: String, Sendable {
    case idle = "待命中"
    case recording = "录制中"
    case stopping = "正在停止并保存"
}

/// 采集器生命周期与代理回调
public protocol PerceptionDataCollectorDelegate: AnyObject, Sendable {
    /// 采集状态变更通知
    func collector(_ collector: PerceptionDataCollectorProtocol, didChangeState state: CollectorState)
    /// 录制时长心跳更新 (秒数，供 UI 实时展示)
    func collector(_ collector: PerceptionDataCollectorProtocol, didUpdateDuration seconds: Double)
    /// 采集异常通知 (如存储空间不足、写盘故障)
    func collector(_ collector: PerceptionDataCollectorProtocol, didEncounterError error: Error)
}

/// 空间感知数据采集器核心接口
public protocol PerceptionDataCollectorProtocol: AnyObject, Sendable {
    /// 代理接收器
    var delegate: PerceptionDataCollectorDelegate? { get set }
    /// 当前录制状态
    var state: CollectorState { get }
    /// 当前活动会话标识符 (若未在录制则为 nil)
    var currentSessionId: String? { get }
    /// 当前已录制时长 (秒)
    var currentDuration: Double { get }
    
    /// 启动实测数据录制会话
    func startRecording() throws
    
    /// 结束实测数据录制会话
    func stopRecording(completion: (@Sendable (Result<SessionMetadata, Error>) -> Void)?)
    
    /// 接收感知流水线派发的每一帧全量数据 (非阻塞快速异步投递)
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

// MARK: - 空间感知实测数据采集协调器实现

/// 负责连接感知流水线，管理会话生命周期、异步分级采样落盘与存储安全防护
public final class PerceptionDataCollector: PerceptionDataCollectorProtocol, @unchecked Sendable {
    
    // MARK: - 公开属性
    
    public weak var delegate: PerceptionDataCollectorDelegate?
    
    private let stateLock = NSLock()
    private var _state: CollectorState = .idle
    public var state: CollectorState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _state
    }
    
    private var _currentSessionId: String?
    public var currentSessionId: String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _currentSessionId
    }
    
    private var _currentDuration: Double = 0
    public var currentDuration: Double {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _currentDuration
    }
    
    // MARK: - 单例与依赖
    
    /// 默认单例协调器实例
    public static let shared = PerceptionDataCollector()
    
    private let storageManager: SessionStorageManagerProtocol
    /// 专用后台异步写盘队列 (Utility QoS，确保主线程和推理线程零 I/O 阻塞)
    private let writeQueue = DispatchQueue(label: "world.accera.walkmate.collector.write", qos: .utility)
    /// 图像预处理与 JPEG 编码上下文
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let jsonEncoder = JSONEncoder()
    
    /// 视觉图像与深度抽样间隔 (毫秒, 默认 500ms 即 2Hz)
    public var snapshotIntervalMs: Int64 = 500
    /// 单次录制上限保护 (15 分钟)
    public static let maxRecordingDurationSeconds: Double = 15 * 60
    
    // MARK: - 会话运行态私有变量
    
    private var fileHandle: FileHandle?
    private var sessionFolderURL: URL?
    private var startTimeMs: Int64 = 0
    private var lastSnapshotTimestampMs: Int64 = 0
    private var telemetryFrameCount: Int = 0
    private var imageSnapshotCount: Int = 0
    private var durationTimer: DispatchSourceTimer?
    private var lastStorageCheckTimestamp: TimeInterval = 0
    
    // MARK: - 初始化
    
    /// 初始化数据采集协调器
    /// - Parameter storageManager: 会话沙盒存储管理器实例
    public init(storageManager: SessionStorageManagerProtocol = SessionStorageManager.shared) {
        self.storageManager = storageManager
    }
    
    // MARK: - 会话启动与停止
    
    /// 启动实测数据录制会话
    public func startRecording() throws {
        stateLock.lock()
        guard _state == .idle else {
            stateLock.unlock()
            return
        }
        
        // 1. 检查磁盘剩余空间安全门限 (>= 500MB)
        guard storageManager.hasSufficientStorage(minRequiredMB: SessionStorageManager.defaultSafetyStorageThresholdMB) else {
            stateLock.unlock()
            throw SessionStorageError.insufficientStorage(availableMB: 0, requiredMB: SessionStorageManager.defaultSafetyStorageThresholdMB)
        }
        
        // 2. 生成规范会话 ID (例如: session_20260923_183015)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestampStr = formatter.string(from: Date())
        let sessionId = "session_\(timestampStr)"
        
        // 3. 创建会话文件夹与子目录
        let folderURL = try storageManager.createSessionFolder(sessionId: sessionId)
        let jsonlURL = folderURL.appendingPathComponent("telemetry.jsonl")
        
        // 4. 创建初始时序遥测文件并打开追加写入句柄
        FileManager.default.createFile(atPath: jsonlURL.path, contents: nil, attributes: nil)
        guard let handle = try? FileHandle(forWritingTo: jsonlURL) else {
            stateLock.unlock()
            throw SessionStorageError.ioFailure("无法打开遥测数据写入流")
        }
        
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        self.fileHandle = handle
        self.sessionFolderURL = folderURL
        self._currentSessionId = sessionId
        self._currentDuration = 0
        self.startTimeMs = nowMs
        self.lastSnapshotTimestampMs = 0
        self.telemetryFrameCount = 0
        self.imageSnapshotCount = 0
        self.lastStorageCheckTimestamp = Date().timeIntervalSinceReferenceDate
        self._state = .recording
        stateLock.unlock()
        
        // 5. 保存初始元数据
        let initialMetadata = SessionMetadata(
            sessionId: sessionId,
            startTimeMs: nowMs,
            endTimeMs: nil,
            durationSeconds: 0,
            totalTelemetryFrames: 0,
            totalImageSnapshots: 0,
            deviceInfo: "iPhone",
            appVersion: "1.0.0",
            algorithmConfig: [
                "groundTolerance": "0.08",
                "corridorWidth": "0.75"
            ]
        )
        try? storageManager.saveMetadata(initialMetadata, sessionId: sessionId)
        
        // 6. 启动计时器 (每秒派发一次时长心跳)
        startHeartbeatTimer()
        
        Log.info("实测数据采集已开启: \(sessionId)", category: .perception)
        if Thread.isMainThread {
            self.delegate?.collector(self, didChangeState: .recording)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.collector(self, didChangeState: .recording)
            }
        }
    }
    
    /// 结束实测数据录制会话
    public func stopRecording(completion: (@Sendable (Result<SessionMetadata, Error>) -> Void)? = nil) {
        stateLock.lock()
        guard _state == .recording else {
            stateLock.unlock()
            completion?(.failure(SessionStorageError.sessionNotFound("当前未处于录制中状态")))
            return
        }
        _state = .stopping
        let sessionId = _currentSessionId ?? ""
        stopHeartbeatTimer()
        stateLock.unlock()
        
        writeQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 刷盘并关闭文件写入流句柄
            try? self.fileHandle?.synchronize()
            try? self.fileHandle?.close()
            self.fileHandle = nil
            
            let endMs = Int64(Date().timeIntervalSince1970 * 1000)
            let duration = max(0, Double(endMs - self.startTimeMs) / 1000.0)
            
            // 构建最终会话元数据
            var finalMetadata = SessionMetadata(
                sessionId: sessionId,
                startTimeMs: self.startTimeMs,
                endTimeMs: endMs,
                durationSeconds: duration,
                totalTelemetryFrames: self.telemetryFrameCount,
                totalImageSnapshots: self.imageSnapshotCount,
                deviceInfo: "iPhone",
                appVersion: "1.0.0"
            )
            
            do {
                try self.storageManager.saveMetadata(finalMetadata, sessionId: sessionId)
                Log.info("实测会话已安全封包落盘: \(sessionId), 遥测: \(self.telemetryFrameCount)帧, 图像快照: \(self.imageSnapshotCount)帧", category: .perception)
                
                self.stateLock.lock()
                self._state = .idle
                self._currentSessionId = nil
                self._currentDuration = 0
                self.stateLock.unlock()
                
                DispatchQueue.main.async {
                    self.delegate?.collector(self, didChangeState: .idle)
                    completion?(.success(finalMetadata))
                }
            } catch {
                Log.error("更新会话最终元数据失败: \(error.localizedDescription)", category: .perception)
                self.stateLock.lock()
                self._state = .idle
                self._currentSessionId = nil
                self._currentDuration = 0
                self.stateLock.unlock()
                
                DispatchQueue.main.async {
                    self.delegate?.collector(self, didChangeState: .idle)
                    completion?(.failure(error))
                }
            }
        }
    }
    
    // MARK: - 帧数据接收与异步分级存储 (零 I/O 阻塞主链路)
    
    /// 接收感知流水线派发的每一帧全量数据
    public func recordFrame(
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
    ) {
        stateLock.lock()
        guard _state == .recording else {
            stateLock.unlock()
            return
        }
        
        let frameIdx = telemetryFrameCount
        telemetryFrameCount += 1
        
        // 评估是否达到 2Hz 视觉图像/深度采样窗口
        let shouldCaptureSnapshot = (frame.timestampMs - lastSnapshotTimestampMs) >= snapshotIntervalMs
        if shouldCaptureSnapshot {
            lastSnapshotTimestampMs = frame.timestampMs
            imageSnapshotCount += 1
        }
        stateLock.unlock()
        
        // 构建轻量级 Codable 遥测快照
        let rawRecords = rawObstacles.map {
            ObstacleRecord(
                id: $0.id,
                position: SIMD3Record($0.position),
                size: SIMD3Record($0.size),
                distance: $0.distance,
                azimuth: $0.azimuth,
                category: $0.category.rawValue
            )
        }
        
        let hazardRecords = hazardObstacles.map {
            ObstacleRecord(
                id: $0.id,
                position: SIMD3Record($0.position),
                size: SIMD3Record($0.size),
                distance: $0.distance,
                azimuth: $0.azimuth,
                category: $0.category.rawValue
            )
        }
        
        let waypoints = routeData?.waypoints.map { SIMD3Record($0.position) } ?? []
        
        // 四元数与欧拉角转换
        let quatRecord = QuaternionRecord(frame.orientation)
        let eulerRecord = extractEulerAngles(from: frame.orientation)
        
        let telemetryRecord = FrameTelemetryRecord(
            timestampMs: frame.timestampMs,
            frameIndex: frameIdx,
            quaternion: quatRecord,
            eulerAngles: eulerRecord,
            acceleration: SIMD3Record(frame.acceleration),
            groundPlane: groundPlane,
            cameraHeight: cameraHeight,
            rawObstacles: rawRecords,
            hazardObstacles: hazardRecords,
            activeObstacleTarget: activeObstacleTarget != nil ? SIMD3Record(activeObstacleTarget!) : nil,
            isPassable: routeData?.isPathAvailable ?? false,
            safeDepth: routeData?.safeDepth ?? 0,
            recommendedHeading: routeData?.recommendedHeading ?? 0,
            waypoints: waypoints,
            activeNavigationTarget: activeNavigationTarget != nil ? SIMD3Record(activeNavigationTarget!) : nil,
            processingLatencyMs: latencyMs,
            hasImageSnapshot: shouldCaptureSnapshot
        )
        
        // 投递至后台 Utility 队列进行物理写盘
        writeQueue.async { [weak self] in
            guard let self = self, self.state == .recording || self.state == .stopping else { return }
            self.persistTelemetryLine(telemetryRecord)
            
            if shouldCaptureSnapshot {
                self.persistSnapshot(frame: frame, depthMatrix: depthMatrix)
            }
            
            // 周期性检查存储容量与安全超长保护 (每隔约 5 秒检查一次)
            let now = Date().timeIntervalSinceReferenceDate
            if now - self.lastStorageCheckTimestamp >= 5.0 {
                self.lastStorageCheckTimestamp = now
                self.performPeriodicSafetyChecks()
            }
        }
    }
    
    // MARK: - 内部持久化辅助逻辑
    
    private func persistTelemetryLine(_ record: FrameTelemetryRecord) {
        guard let handle = self.fileHandle else { return }
        do {
            let data = try jsonEncoder.encode(record)
            handle.write(data)
            if let newline = "\n".data(using: .utf8) {
                handle.write(newline)
            }
        } catch {
            Log.error("遥测记录行序列化写盘失败: \(error.localizedDescription)", category: .perception)
        }
    }
    
    private func persistSnapshot(frame: PanoramicFrame, depthMatrix: DepthMatrix?) {
        guard let folder = self.sessionFolderURL else { return }
        let timestamp = frame.timestampMs
        
        // 1. 保存压缩 JPEG 全景帧快照
        let framesDir = folder.appendingPathComponent("frames", isDirectory: true)
        let frameURL = framesDir.appendingPathComponent("\(timestamp).jpg")
        let ciImage = CIImage(cvPixelBuffer: frame.pixelBuffer)
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
           let jpegData = ciContext.jpegRepresentation(
            of: ciImage,
            colorSpace: colorSpace,
            options: [:]
           ) {
            try? jpegData.write(to: frameURL, options: .atomic)
        }
        
        // 2. 保存半精度/物理二进制深度矩阵快照
        if let depth = depthMatrix {
            let depthsDir = folder.appendingPathComponent("depths", isDirectory: true)
            let depthURL = depthsDir.appendingPathComponent("\(timestamp).bin")
            depth.values.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                let byteCount = buffer.count * MemoryLayout<Float>.size
                let data = Data(bytes: baseAddress, count: byteCount)
                try? data.write(to: depthURL, options: .atomic)
            }
        }
    }
    
    // MARK: - 存储安全与超长限制周期性检查
    
    private func performPeriodicSafetyChecks() {
        // 1. 容量检查 (<500MB 强制中止)
        if !storageManager.hasSufficientStorage(minRequiredMB: SessionStorageManager.defaultSafetyStorageThresholdMB) {
            Log.error("存储空间低于 500MB 安全门限，触发保护性停止录制", category: .perception)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.collector(
                    self,
                    didEncounterError: SessionStorageError.insufficientStorage(
                        availableMB: 0,
                        requiredMB: SessionStorageManager.defaultSafetyStorageThresholdMB
                    )
                )
            }
            self.stopRecording(completion: nil)
            return
        }
        
        // 2. 超长录制保护 (15 分钟滚动分片保护: 自动封包并无缝衔接开启新分片)
        let elapsed = self.currentDuration
        if elapsed >= Self.maxRecordingDurationSeconds {
            Log.info("录制达到单次 15 分钟上限，自动安全封包并无缝开启新分片", category: .perception)
            self.stopRecording { [weak self] result in
                guard let self = self else { return }
                if case .success = result {
                    try? self.startRecording()
                }
            }
        }
    }
    
    // MARK: - 计时器心跳
    
    private func startHeartbeatTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.stateLock.lock()
            guard self._state == .recording else {
                self.stateLock.unlock()
                return
            }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let duration = max(0, Double(nowMs - self.startTimeMs) / 1000.0)
            self._currentDuration = duration
            self.stateLock.unlock()
            
            self.delegate?.collector(self, didUpdateDuration: duration)
        }
        self.durationTimer = timer
        timer.resume()
    }
    
    private func stopHeartbeatTimer() {
        durationTimer?.cancel()
        durationTimer = nil
    }
    
    // MARK: - 辅助数学转换 (四元数转欧拉角)
    
    private func extractEulerAngles(from q: simd_quatf) -> EulerAnglesRecord {
        let w = q.vector.w
        let x = q.vector.x
        let y = q.vector.y
        let z = q.vector.z
        
        // Roll (X 轴)
        let sinr_cosp = 2 * (w * x + y * z)
        let cosr_cosp = 1 - 2 * (x * x + y * y)
        let roll = atan2(sinr_cosp, cosr_cosp)
        
        // Pitch (Y 轴)
        let sinp = 2 * (w * y - z * x)
        let pitch: Float
        if abs(sinp) >= 1 {
            pitch = copysign(.pi / 2, sinp)
        } else {
            pitch = asin(sinp)
        }
        
        // Yaw (Z 轴)
        let siny_cosp = 2 * (w * z + x * y)
        let cosy_cosp = 1 - 2 * (y * y + z * z)
        let yaw = atan2(siny_cosp, cosy_cosp)
        
        // 转为角度制
        let radToDeg: Float = 180.0 / .pi
        return EulerAnglesRecord(
            roll: roll * radToDeg,
            pitch: pitch * radToDeg,
            yaw: yaw * radToDeg
        )
    }
}
