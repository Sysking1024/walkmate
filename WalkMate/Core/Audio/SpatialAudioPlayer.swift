//
//  SpatialAudioPlayer.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import AVFoundation
import Foundation
import simd

// MARK: - 障碍物双音发声状态枚举
/// 管理“固定 800ms 播放 2 次后自动静音”的状态机
public enum ObstacleAlertPhase: Sendable, Equatable {
    /// 空闲状态，未发声
    case idle
    /// 正在播放第 1 声金属撞击音
    case firstPing
    /// 等待 800ms 间隔
    case waitingInterval
    /// 正在播放第 2 声金属撞击音
    case secondPing
    /// 双响播放完成，保持静音等待业务层下一轮触发
    case completed
}

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
    internal let stateLock = NSLock()
    
    // MARK: - 运行状态
    private var _isRunning: Bool = false
    public var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isRunning
    }
    
    // MARK: - 障碍物发声状态机 (US1)
    private var _obstacleAlertPhase: ObstacleAlertPhase = .idle
    public var obstacleAlertPhase: ObstacleAlertPhase {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _obstacleAlertPhase
    }
    
    private var obstacleAlertWorkItem: DispatchWorkItem?
    private var obstacleTargetPosition: SIMD3<Float>?
    
    // MARK: - 导航脚步声调度状态机 (US2)
    /// 导航步频间隔时间（成人自然行走步频默认 1.1 秒）
    public var navigationCadenceInterval: TimeInterval = 1.1
    
    private var _isNavigationActive: Bool = false
    public var isNavigationActive: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isNavigationActive
    }
    
    private var _navigationStepCount: Int = 0
    public var navigationStepCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _navigationStepCount
    }
    
    private var navigationCadenceWorkItem: DispatchWorkItem?
    private var navigationTargetPosition: SIMD3<Float>?
    
    // MARK: - 压音调度状态 (Ducking Coordinator)
    private var isObstacleDucking: Bool = false
    private var isRewardDucking: Bool = false
    
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
        
        cancelObstacleAlertInternal()
        stopNavigationCadenceInternal()
        
        obstaclePlayerNode.stop()
        navigationPlayerNode.stop()
        rewardPlayerNode.stop()
        engine.stop()
        
        Log.info("空间音频引擎已停止", category: .audio)
    }
    
    /// 全局重置声学状态与激活通道
    public func reset() {
        stateLock.lock()
        _isNavigationActive = false
        _navigationStepCount = 0
        _obstacleAlertPhase = .idle
        isObstacleDucking = false
        isRewardDucking = false
        stateLock.unlock()
        
        obstacleAlertWorkItem?.cancel()
        obstacleAlertWorkItem = nil
        navigationCadenceWorkItem?.cancel()
        navigationCadenceWorkItem = nil
        obstacleTargetPosition = nil
        navigationTargetPosition = nil
        
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            self.cancelObstacleAlertInternal()
            self.stopNavigationCadenceInternal()
            
            self.obstaclePlayerNode.stop()
            self.navigationPlayerNode.stop()
            self.rewardPlayerNode.stop()
            
            if self.isRunning {
                self.obstaclePlayerNode.play()
                self.navigationPlayerNode.play()
                self.rewardPlayerNode.play()
            }
            
            self.navigationPlayerNode.volume = 1.0
            Log.info("空间音频播放器已完成全局重置，恢复静音初始态", category: .audio)
        }
    }
    
    // MARK: - 内部辅助方法：声源坐标映射与平滑更新
    
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
    
    /// 平滑更新障碍物三维声源坐标（防声相突变与爆音）
    private func smoothUpdateObstaclePosition(to newPos: SIMD3<Float>) {
        self.obstacleTargetPosition = newPos
        self.apply3DPosition(node: self.obstaclePlayerNode, position: newPos)
    }
    
    /// 统一压音协调器：障碍物警示或康复和弦期间将脚步声压低至 30%
    private func updateFootstepDucking() {
        let targetVolume: Float = (isObstacleDucking || isRewardDucking) ? 0.30 : 1.0
        navigationPlayerNode.volume = targetVolume
    }
    
    // MARK: - 用户故事 1: 危险障碍物金属撞击双音确认警示 (US1)
    
    /// 设置危险障碍物目标坐标（触发金属撞击声双音确认警示）
    /// - Parameter position: 障碍物相对三维坐标 (x, y, z)，单位米；传入 nil 则立即停止当前警示
    public func setObstacleTarget(position: SIMD3<Float>?) {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 1. 若传入 nil，立即取消当前发声并恢复静音
            guard let position = position else {
                self.cancelObstacleAlertInternal()
                return
            }
            
            self.stateLock.lock()
            let currentPhase = self._obstacleAlertPhase
            self.stateLock.unlock()
            
            // 2. 防重入机制：若双音发声正在进行中，仅动态平滑移动声源位置，严禁打断重入
            if currentPhase == .firstPing || currentPhase == .waitingInterval || currentPhase == .secondPing {
                self.smoothUpdateObstaclePosition(to: position)
                return
            }
            
            // 3. 处于 idle 或 completed 状态，启动全新一轮 800ms 双音警示
            self.startObstacleDoublePing(at: position)
        }
    }
    
    /// 启动 800ms 双音警示序列
    private func startObstacleDoublePing(at position: SIMD3<Float>) {
        cancelObstacleAlertInternal()
        
        stateLock.lock()
        _obstacleAlertPhase = .firstPing
        stateLock.unlock()
        
        smoothUpdateObstaclePosition(to: position)
        
        // 发声期间开启脚步声压音让位 (Ducking 至 30%)
        isObstacleDucking = true
        updateFootstepDucking()
        
        // 播放第 1 声金属撞击音
        obstaclePlayerNode.scheduleBuffer(metallicImpactBuffer, at: nil, options: [])
        if !obstaclePlayerNode.isPlaying && isRunning {
            obstaclePlayerNode.play()
        }
        
        Log.info("触发危险障碍物金属警示音 (第 1 声): \(position)", category: .audio)
        
        stateLock.lock()
        _obstacleAlertPhase = .waitingInterval
        stateLock.unlock()
        
        // 调度精确 800ms 后的第 2 声
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            self.stateLock.lock()
            guard self._obstacleAlertPhase == .waitingInterval else {
                self.stateLock.unlock()
                return
            }
            self._obstacleAlertPhase = .secondPing
            self.stateLock.unlock()
            
            self.obstaclePlayerNode.scheduleBuffer(self.metallicImpactBuffer, at: nil, options: [])
            Log.info("触发危险障碍物金属警示音 (第 2 声)", category: .audio)
            
            // 第 2 声音频播完后（0.1s）转入 completed 状态并自动安静
            let completionItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                
                self.stateLock.lock()
                guard self._obstacleAlertPhase == .secondPing else {
                    self.stateLock.unlock()
                    return
                }
                self._obstacleAlertPhase = .completed
                self.stateLock.unlock()
                
                // 恢复背景脚步声音量至 100%
                self.isObstacleDucking = false
                self.updateFootstepDucking()
                
                Log.info("障碍物双音确认完毕，自动静音转入 completed 态", category: .audio)
            }
            
            self.obstacleAlertWorkItem = completionItem
            self.audioQueue.asyncAfter(deadline: .now() + 0.1, execute: completionItem)
        }
        
        self.obstacleAlertWorkItem = workItem
        audioQueue.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }
    
    /// 内部取消障碍物发声并恢复状态
    private func cancelObstacleAlertInternal() {
        obstacleAlertWorkItem?.cancel()
        obstacleAlertWorkItem = nil
        
        obstaclePlayerNode.stop()
        if isRunning {
            obstaclePlayerNode.play()
        }
        
        stateLock.lock()
        _obstacleAlertPhase = .idle
        stateLock.unlock()
        
        isObstacleDucking = false
        updateFootstepDucking()
    }
    
    // MARK: - 用户故事 2: 安全可行路线前方领路脚步声 (US2)
    
    /// 设置安全可通行航路点目标坐标（持续以人体自然步频播放领路脚步声）
    /// - Parameter position: 前方安全通道航路点相对三维坐标 (x, y, z)，单位米；传入 nil 则停止脚步导引
    public func setNavigationTarget(position: SIMD3<Float>?) {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 1. 若传入 nil，立即停止导航脚步声
            guard let position = position else {
                self.stopNavigationCadenceInternal()
                Log.info("导航目标置空，停止领路脚步声", category: .audio)
                return
            }
            
            self.navigationTargetPosition = position
            // 动态映射航路点三维空间声相方位
            self.apply3DPosition(node: self.navigationPlayerNode, position: position)
            
            self.stateLock.lock()
            let wasActive = self._isNavigationActive
            self._isNavigationActive = true
            self.stateLock.unlock()
            
            // 2. 若此前未激活，立即启动步频节拍循环
            if !wasActive {
                Log.info("激活前方领路脚步声，初始方位: \(position)", category: .audio)
                self.scheduleNextFootstep(immediate: true)
            }
        }
    }
    
    /// 调度下一个自然步频踏步声
    private func scheduleNextFootstep(immediate: Bool) {
        navigationCadenceWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            self.stateLock.lock()
            guard self._isNavigationActive && self._isRunning else {
                self.stateLock.unlock()
                return
            }
            self._navigationStepCount += 1
            self.stateLock.unlock()
            
            // 播放单次轻快踏地音
            self.navigationPlayerNode.scheduleBuffer(self.footstepBuffer, at: nil, options: [])
            if !self.navigationPlayerNode.isPlaying && self.isRunning {
                self.navigationPlayerNode.play()
            }
            
            // 循环调度下一步
            self.scheduleNextFootstep(immediate: false)
        }
        
        self.navigationCadenceWorkItem = workItem
        let delay = immediate ? 0.0 : self.navigationCadenceInterval
        audioQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    /// 停止导航脚步声节拍循环
    private func stopNavigationCadenceInternal() {
        navigationCadenceWorkItem?.cancel()
        navigationCadenceWorkItem = nil
        navigationTargetPosition = nil
        
        stateLock.lock()
        _isNavigationActive = false
        _navigationStepCount = 0
        stateLock.unlock()
        
        navigationPlayerNode.stop()
        if isRunning {
            navigationPlayerNode.play()
        }
    }
    
    // MARK: - 占位方法（由后续用户故事 Phase 5 实现）
    
    public func playRewardSound() {
        // 后续由 T010 [US3] 完整实现
    }
}
