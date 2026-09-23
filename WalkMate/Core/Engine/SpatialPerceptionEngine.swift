//
//  SpatialPerceptionEngine.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import CoreVideo
import Foundation
import simd

// MARK: - 空间感知对外服务协议契约

/// 空间感知数据监听代理 (上层业务挂载此代理获取基础数据)
public protocol SpatialPerceptionDelegate: AnyObject {
    /// 全场景 360° 障碍物数据到达回调
    func perceptionEngine(
        _ engine: SpatialPerceptionEngineProtocol,
        didProduceObstacles data: ObstacleData
    )
    
    /// 可通行路线折线数据到达回调
    func perceptionEngine(
        _ engine: SpatialPerceptionEngineProtocol,
        didProducePassableRoute data: PassableRouteData
    )
    
    /// 感知引擎异常报错
    func perceptionEngine(
        _ engine: SpatialPerceptionEngineProtocol,
        didEncounterError error: Error
    )
}

/// 空间感知引擎控制接口
public protocol SpatialPerceptionEngineProtocol: AnyObject {
    /// 代理监听
    var delegate: SpatialPerceptionDelegate? { get set }
    
    /// 引擎是否处于活跃运行中
    var isRunning: Bool { get }
    
    /// 启动感知流水线
    func start()
    
    /// 停止感知流水线
    func stop()
    
    /// 处理单帧全景数据 (由 CameraPipeline 回调驱动)
    func processFrame(_ frame: PanoramicFrame)
    
    // MARK: - Swift Concurrency 现代化异步流支持 (供 SwiftUI / Combine 订阅)
    
    /// 360° 障碍物异步事件流
    var obstacleStream: AsyncStream<ObstacleData> { get }
    
    /// 可通行路线异步事件流
    var routeStream: AsyncStream<PassableRouteData> { get }
    
    // MARK: - 主动快照查询接口
    
    /// 获取当前最新一帧的全量 360° 障碍物快照
    var latestObstacles: ObstacleData? { get }
    
    /// 获取当前最新一帧的可通行路线快照
    var latestRoute: PassableRouteData? { get }
}

// MARK: - 空间感知对外服务中枢

/// 空间感知引擎核心总成，接收 PanoramicFrame 视频与姿态流，
/// 串联 Accelerate 预处理、DAP ANE 深度推理、方向 LUT 球面投影、IMU 重力姿态对齐、
/// 纯动态 RANSAC 地面拟合剥离、360° 障碍物检测与 MOT 追踪、以及 BEV/EDT 可通行路线规划，
/// 通过代理监听器 (Delegate)、AsyncStream 异步流及主动快照向外分发结构化数据
public final class SpatialPerceptionEngine: SpatialPerceptionEngineProtocol, @unchecked Sendable {
    
    // MARK: - 公开状态与代理
    
    public weak var delegate: SpatialPerceptionDelegate?
    
    private let stateLock = NSLock()
    private var _isRunning: Bool = false
    public var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isRunning
    }
    
    private var _latestObstacles: ObstacleData?
    public var latestObstacles: ObstacleData? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _latestObstacles
    }
    
    private var _latestRoute: PassableRouteData?
    public var latestRoute: PassableRouteData? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _latestRoute
    }
    
    // MARK: - AsyncStream 异步流分发器
    
    private var obstacleContinuation: AsyncStream<ObstacleData>.Continuation?
    public private(set) lazy var obstacleStream: AsyncStream<ObstacleData> = {
        AsyncStream { [weak self] continuation in
            self?.obstacleContinuation = continuation
        }
    }()
    
    private var routeContinuation: AsyncStream<PassableRouteData>.Continuation?
    public private(set) lazy var routeStream: AsyncStream<PassableRouteData> = {
        AsyncStream { [weak self] continuation in
            self?.routeContinuation = continuation
        }
    }()
    
    // MARK: - 内部底层组件
    
    private let preprocessor: AcceleratePreprocessor
    private let dapEngine: DAPEngine
    private let projector: SphericalProjector
    private let gravityAligner: GravityAligner
    private let groundEstimator: GroundPlaneEstimator
    private let obstacleDetector: ObstacleDetector
    private let obstacleTracker: ObstacleTracker
    private let routePlanner: PassageRoutePlanner
    
    /// 流水线串行计算队列 (QoS userInitiated, 防止主线程卡顿)
    private let pipelineQueue = DispatchQueue(label: "world.accera.walkmate.perception.pipeline", qos: .userInitiated)
    /// 丢帧控制标志 (若上一帧尚未完成计算，主动跳过新到达帧，防止内存积压)
    private var isFrameProcessing: Bool = false
    /// 全局递增输出帧序号
    private var frameCounter: Int64 = 0
    
    // MARK: - 初始化
    
    /// 初始化空间感知引擎与底层算法组件
    public init() throws {
        self.preprocessor = AcceleratePreprocessor()
        self.dapEngine = try DAPEngine()
        self.projector = SphericalProjector()
        self.gravityAligner = GravityAligner()
        self.groundEstimator = GroundPlaneEstimator()
        self.obstacleDetector = ObstacleDetector()
        self.obstacleTracker = ObstacleTracker()
        self.routePlanner = PassageRoutePlanner()
        Log.info("空间感知引擎总成所有组件装配完成", category: .perception)
    }
    
    // MARK: - 生命周期控制
    
    /// 启动空间感知流水线
    public func start() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !_isRunning else { return }
        _isRunning = true
        obstacleTracker.reset()
        routePlanner.reset()
        projector.resetEMA()
        Log.info("空间感知流水线已启动", category: .perception)
    }
    
    /// 停止空间感知流水线
    public func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard _isRunning else { return }
        _isRunning = false
        obstacleTracker.reset()
        routePlanner.reset()
        projector.resetEMA()
        Log.info("空间感知流水线已停止", category: .perception)
    }
    
    // MARK: - 核心帧驱动流水线
    
    /// 接收并处理单帧全景数据 (由 CameraPipeline 帧捕获驱动)
    /// - Parameter frame: 包含 1080P 全景像素缓存与对齐姿态的输入帧
    public func processFrame(_ frame: PanoramicFrame) {
        stateLock.lock()
        guard _isRunning else {
            stateLock.unlock()
            return
        }
        // 若后台正在处理上一帧，主动丢弃当前帧以保全链路低时延
        if isFrameProcessing {
            stateLock.unlock()
            return
        }
        isFrameProcessing = true
        stateLock.unlock()
        
        pipelineQueue.async { [weak self] in
            guard let self = self else { return }
            defer {
                self.stateLock.lock()
                self.isFrameProcessing = false
                self.stateLock.unlock()
            }
            
            do {
                // 1. Accelerate 硬件预处理 (vImage 缩放 + vDSP 归一化)
                let inputTensor = try self.preprocessor.preprocess(pixelBuffer: frame.pixelBuffer)
                
                // 2. DAP ANE 神经引擎硬件深度推理
                let depthMatrix = try self.dapEngine.inferDepth(from: inputTensor, timestampMs: frame.timestampMs)
                
                // 3. 方向向量表 LUT 快速球面反投影 (13 万点云)
                let pointCloud = self.projector.project(depthMatrix: depthMatrix)
                
                // 4. 六轴 IMU 四元数或加速度重力垂直坐标对齐
                let alignedPoints: [SIMD3<Float>]
                if simd_length(frame.orientation.vector) > 0.1 {
                    alignedPoints = self.gravityAligner.align(points: pointCloud, orientation: frame.orientation)
                } else {
                    alignedPoints = self.gravityAligner.align(points: pointCloud, acceleration: frame.acceleration)
                }
                
                // 5. 纯动态 RANSAC 平面拟合与地面点云剥离
                let groundResult = self.groundEstimator.estimateGround(from: alignedPoints)
                
                // 6. 全场景 360° 障碍物网格聚类与高程分类
                let detectedObstacles = self.obstacleDetector.detectObstacles(
                    from: groundResult.nonGroundPoints,
                    cameraHeight: groundResult.cameraHeight
                )
                
                // 7. 3D 多目标跨帧跟踪 (MOT) 与速度解算
                let trackedObstacles = self.obstacleTracker.track(
                    obstacles: detectedObstacles,
                    timestampMs: frame.timestampMs
                )
                
                // 8. 构建最终 ObstacleData 实体
                self.stateLock.lock()
                self.frameCounter += 1
                let currentFrameId = self.frameCounter
                self.stateLock.unlock()
                
                let obstacleData = ObstacleData(
                    frameId: currentFrameId,
                    timestampMs: frame.timestampMs,
                    obstacles: trackedObstacles
                )
                
                // 9. BEV 栅格与可通行路线规划
                let routeData = self.routePlanner.planRoute(
                    obstacles: trackedObstacles,
                    cameraHeight: groundResult.cameraHeight
                )
                
                // 10. 更新本地最新快照
                self.stateLock.lock()
                self._latestObstacles = obstacleData
                self._latestRoute = routeData
                self.stateLock.unlock()
                
                // 11. 分发数据至 AsyncStream 与 Delegate 回调
                self.obstacleContinuation?.yield(obstacleData)
                self.routeContinuation?.yield(routeData)
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let delegate = self.delegate else { return }
                    delegate.perceptionEngine(self, didProduceObstacles: obstacleData)
                    delegate.perceptionEngine(self, didProducePassableRoute: routeData)
                }
                
            } catch {
                Log.error("感知流水线单帧处理异常: \(error.localizedDescription)", category: .perception)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let delegate = self.delegate else { return }
                    delegate.perceptionEngine(self, didEncounterError: error)
                }
            }
        }
    }
}
