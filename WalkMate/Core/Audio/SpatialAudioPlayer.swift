//
//  SpatialAudioPlayer.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import AVFoundation
import Foundation
import simd

// MARK: - 空间音频播放器接口协议
public protocol SpatialAudioPlayerProtocol: AnyObject, Sendable {
    
    // MARK: - 生命周期管理
    func start() throws
    func stop()
    var isRunning: Bool { get }
    
    // MARK: - 语义通道目标设置（机制与策略分离）
    func setObstacleTarget(position: SIMD3<Float>?)
    func setNavigationTarget(position: SIMD3<Float>?)
    func playRewardSound()
    
    // MARK: - 声学配置与重置
    func reset()
}

// MARK: - 空间音频播放服务实现
/// 负责管理 AVAudioEngine 与 AVAudioEnvironmentNode 3D 声学图，实现避障双音确认、领路脚步声与康复激励
public final class SpatialAudioPlayer: @unchecked Sendable, SpatialAudioPlayerProtocol {
    
    /// 全局单例
    public static let shared = SpatialAudioPlayer()
    
    // MARK: - 核心音频硬件与节点
    internal let engine: AVAudioEngine
    internal let environmentNode: AVAudioEnvironmentNode
    
    internal let obstaclePlayerNode: AVAudioPlayerNode
    internal let navigationPlayerNode: AVAudioPlayerNode
    internal let rewardPlayerNode: AVAudioPlayerNode
    
    // MARK: - 预合成声音缓存 (零文件依赖)
    internal let metallicImpactBuffer: AVAudioPCMBuffer
    internal let footstepBuffer: AVAudioPCMBuffer
    internal let rewardChimeBuffer: AVAudioPCMBuffer
    
    // MARK: - 串行调度队列与并发锁
    internal let audioQueue = DispatchQueue(label: "world.accera.walkmate.audioQueue", qos: .userInteractive)
    
    // MARK: - 运行状态
    private var _isRunning: Bool = false
    private let stateLock = NSLock()
    
    public var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isRunning
    }
    
    // MARK: - 初始化
    public init() {
        self.engine = AVAudioEngine()
        self.environmentNode = AVAudioEnvironmentNode()
        self.obstaclePlayerNode = AVAudioPlayerNode()
        self.navigationPlayerNode = AVAudioPlayerNode()
        self.rewardPlayerNode = AVAudioPlayerNode()
        
        // 1. 预先在内存中生成三种高保真 PCM 缓存
        self.metallicImpactBuffer = ProceduralAudioSynthesizer.generateMetallicImpactBuffer()
        self.footstepBuffer = ProceduralAudioSynthesizer.generateFootstepBuffer()
        self.rewardChimeBuffer = ProceduralAudioSynthesizer.generateRewardChimeBuffer()
        
        // 2. 装配并连接系统 3D 声学音频图
        setupAudioGraph()
    }
    
    // MARK: - 3D 音频图装配
    private func setupAudioGraph() {
        // 附加环境混音节点
        engine.attach(environmentNode)
        engine.connect(environmentNode, to: engine.mainMixerNode, format: nil)
        
        // 设置听者（使用者）位于物理声场原点，面向前方 (-Z 轴)
        environmentNode.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        
        // 附加各语义通道播放器节点
        engine.attach(obstaclePlayerNode)
        engine.attach(navigationPlayerNode)
        engine.attach(rewardPlayerNode)
        
        let format = ProceduralAudioSynthesizer.audioFormat
        engine.connect(obstaclePlayerNode, to: environmentNode, format: format)
        engine.connect(navigationPlayerNode, to: environmentNode, format: format)
        engine.connect(rewardPlayerNode, to: environmentNode, format: format)
        
        // 启用系统最高质量 HRTF 双耳立体声算法
        obstaclePlayerNode.renderingAlgorithm = .HRTFHQ
        navigationPlayerNode.renderingAlgorithm = .HRTFHQ
        rewardPlayerNode.renderingAlgorithm = .HRTFHQ
        
        Log.info("空间音频节点图初始化完成，配置 .HRTFHQ 高精双耳渲染", category: .audio)
    }
    
    // MARK: - 生命周期管理
    
    /// 启动底层音频硬件引擎
    public func start() throws {
        stateLock.lock()
        if _isRunning {
            stateLock.unlock()
            return
        }
        stateLock.unlock()
        
        // 配置系统音频会话 (iOS 平台生效)
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)
        #endif
        
        try engine.start()
        
        obstaclePlayerNode.play()
        navigationPlayerNode.play()
        rewardPlayerNode.play()
        
        stateLock.lock()
        _isRunning = true
        stateLock.unlock()
        
        Log.info("空间音频引擎与声学节点启动成功", category: .audio)
    }
    
    /// 停止音频引擎并释放硬件占用
    public func stop() {
        stateLock.lock()
        guard _isRunning else {
            stateLock.unlock()
            return
        }
        _isRunning = false
        stateLock.unlock()
        
        obstaclePlayerNode.stop()
        navigationPlayerNode.stop()
        rewardPlayerNode.stop()
        engine.stop()
        
        Log.info("空间音频引擎已停止", category: .audio)
    }
    
    /// 全局重置声学状态与激活通道
    public func reset() {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            self.obstaclePlayerNode.stop()
            self.navigationPlayerNode.stop()
            self.rewardPlayerNode.stop()
            
            // 恢复播放节点以备后续发声
            if self.isRunning {
                self.obstaclePlayerNode.play()
                self.navigationPlayerNode.play()
                self.rewardPlayerNode.play()
            }
            
            self.navigationPlayerNode.volume = 1.0
            Log.info("空间音频播放器已完成全局重置，恢复静音初始态", category: .audio)
        }
    }
    
    // MARK: - 内部辅助方法：声源坐标映射
    
    /// 复用 SpatialAudioKit 将相对坐标直接映射至声源物理节点
    internal func apply3DPosition(node: AVAudioPlayerNode, position: SIMD3<Float>) {
        let renderParams = SpatialAudioKit.toSpatialAudioRenderParams(
            position: position,
            boundingSize: ProceduralAudioSynthesizer.defaultPointSourceBoundingSize
        )
        node.position = AVAudio3DPoint(
            x: renderParams.sourcePosition.x,
            y: renderParams.sourcePosition.y,
            z: renderParams.sourcePosition.z
        )
    }
    
    // MARK: - 占位方法（由后续用户故事 Phase 3, 4, 5 分阶段实现）
    
    public func setObstacleTarget(position: SIMD3<Float>?) {
        // 后续由 T006 [US1] 完整实现
    }
    
    public func setNavigationTarget(position: SIMD3<Float>?) {
        // 后续由 T008 [US2] 完整实现
    }
    
    public func playRewardSound() {
        // 后续由 T010 [US3] 完整实现
    }
}
