//
//  SpatialAudioPlayerTests.swift
//  AudioTests
//
//  Created by Antigravity on 2026-09-23.
//

import AVFoundation
import simd
import XCTest
@testable import WalkMate

// MARK: - 空间音频播放器状态机与调度测试套件
final class SpatialAudioPlayerTests: XCTestCase {
    
    // MARK: - 测试 1: 播放器生命周期、音频图装配与坐标映射 (T004)
    func testPlayerLifecycleAndGraph() throws {
        let player = SpatialAudioPlayer()
        
        // 初始状态断言
        XCTAssertFalse(player.isRunning, "播放器初始化后默认处于未运行状态")
        XCTAssertEqual(player.metallicImpactBuffer.frameLength, 4410)
        XCTAssertEqual(player.footstepBuffer.frameLength, 3528)
        XCTAssertEqual(player.rewardChimeBuffer.frameLength, 17640)
        
        // 验证 3D 坐标映射纯函数复用
        let testPos = SIMD3<Float>(-1.5, 0.5, -2.0)
        player.apply3DPosition(node: player.obstaclePlayerNode, position: testPos)
        XCTAssertEqual(player.obstaclePlayerNode.position.x, -1.5, accuracy: 0.001)
        XCTAssertEqual(player.obstaclePlayerNode.position.y, 0.5, accuracy: 0.001)
        XCTAssertEqual(player.obstaclePlayerNode.position.z, -2.0, accuracy: 0.001)
        
        // 验证启动生命周期
        try player.start()
        XCTAssertTrue(player.isRunning, "调用 start() 后 isRunning 必须为 true")
        
        // 重复调用 start() 幂等性
        try player.start()
        XCTAssertTrue(player.isRunning)
        
        // 验证全局重置
        player.reset()
        
        // 验证停止生命周期
        player.stop()
        XCTAssertFalse(player.isRunning, "调用 stop() 后 isRunning 必须为 false")
    }
    
    // MARK: - 测试 2: 障碍物双音确认节奏、脚步压音与自动静音 (T005 - US1)
    func testObstacleDoublePingCadenceAndAutoSilence() throws {
        let player = SpatialAudioPlayer()
        try player.start()
        
        // 1. 设置左侧障碍物目标 (触发金属双响避障)
        let obsPos = SIMD3<Float>(-1.2, 0.0, -1.8)
        player.setObstacleTarget(position: obsPos)
        
        // 验证进入双响状态机，声源坐标与压音生效
        let expInitial = expectation(description: "初次触发进入双响中")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertNotEqual(player.obstacleAlertPhase, .idle, "触发后状态机不能为 idle")
            XCTAssertEqual(player.obstaclePlayerNode.position.x, -1.2, accuracy: 0.05)
            // 验证发声期间领路脚步声被自动压低至 30%
            XCTAssertLessThanOrEqual(player.navigationPlayerNode.volume, 0.35, "障碍物警示发声期间脚步声必须自动压低至 30%")
            expInitial.fulfill()
        }
        wait(for: [expInitial], timeout: 0.2)
        
        // 2. 等待 800ms 间隔 + 第 2 声播放结束（约 950ms）
        let expCompleted = expectation(description: "双响结束自动静音归于 completed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            // 验证状态机转入 completed 态，自动安静不再继续发声
            XCTAssertEqual(player.obstacleAlertPhase, .completed, "双音播放完毕后必须自动静音并进入 completed 状态")
            // 验证双响结束后领路脚步声音量恢复 100%
            XCTAssertGreaterThanOrEqual(player.navigationPlayerNode.volume, 0.95, "双音播完后脚步声音量必须恢复 100%")
            expCompleted.fulfill()
        }
        wait(for: [expCompleted], timeout: 1.3)
        
        player.stop()
    }
    
    // MARK: - 测试 3: 障碍物发声期间高频调用防重入与平滑位移 (T005 - US1)
    func testObstacleNonReentrantSmoothMovement() throws {
        let player = SpatialAudioPlayer()
        try player.start()
        
        // 1. 触发第一声
        player.setObstacleTarget(position: SIMD3<Float>(-1.0, 0.0, -2.0))
        
        // 2. 在 800ms 间隔等待期间（例如 300ms 时）高频重复传入新坐标
        let expReenter = expectation(description: "高频调用平滑移动声源且不重入打断")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let phaseBefore = player.obstacleAlertPhase
            XCTAssertTrue(phaseBefore == .firstPing || phaseBefore == .waitingInterval)
            
            // 传入位移后的新坐标
            player.setObstacleTarget(position: SIMD3<Float>(-2.0, 0.0, -1.5))
            
            // 验证不发生打断重入回到 firstPing
            XCTAssertNotEqual(player.obstacleAlertPhase, .idle)
            
            // 稍作延迟验证声源平滑插值平移到了新位置
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                XCTAssertEqual(player.obstaclePlayerNode.position.x, -2.0, accuracy: 0.1)
                expReenter.fulfill()
            }
        }
        wait(for: [expReenter], timeout: 0.6)
        
        player.stop()
    }
    
    // MARK: - 测试 4: 障碍物目标置 nil 或 reset 立即打断静音 (T005 - US1)
    func testObstacleCancelOnNilAndReset() throws {
        let player = SpatialAudioPlayer()
        try player.start()
        
        // 1. 触发双响
        player.setObstacleTarget(position: SIMD3<Float>(-1.0, 0.0, -2.0))
        
        // 2. 立即传入 nil
        let expNil = expectation(description: "传入 nil 立即静音")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            player.setObstacleTarget(position: nil)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                XCTAssertEqual(player.obstacleAlertPhase, .idle, "传入 nil 后状态机必须立刻回到 idle 状态")
                XCTAssertGreaterThanOrEqual(player.navigationPlayerNode.volume, 0.95, "传入 nil 后脚步声必须立刻恢复正常")
                expNil.fulfill()
            }
        }
        wait(for: [expNil], timeout: 0.3)
        
        // 3. 再次触发并测试 reset()
        player.setObstacleTarget(position: SIMD3<Float>(1.0, 0.0, -2.0))
        let expReset = expectation(description: "调用 reset() 立即重置静音")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            player.reset()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                XCTAssertEqual(player.obstacleAlertPhase, .idle, "调用 reset() 后障碍物状态机必须回到 idle")
                XCTAssertGreaterThanOrEqual(player.navigationPlayerNode.volume, 0.95)
                expReset.fulfill()
            }
        }
        wait(for: [expReset], timeout: 0.3)
        
        player.stop()
    }
    
    // MARK: - 测试 5: 导航脚步声自然步频调度与方位平移追踪 (T007 - US2)
    func testNavigationCadenceAndTracking() throws {
        let player = SpatialAudioPlayer()
        try player.start()
        
        // 1. 设置正前方导航航路点
        let forwardPos = SIMD3<Float>(0.0, -1.4, -3.0)
        player.setNavigationTarget(position: forwardPos)
        
        let expActive = expectation(description: "脚步声导引激活并正前发声")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertTrue(player.isNavigationActive, "设置航路点后导航导引必须处于激活状态")
            XCTAssertEqual(player.navigationPlayerNode.position.x, 0.0, accuracy: 0.05)
            XCTAssertEqual(player.navigationPlayerNode.position.z, -3.0, accuracy: 0.05)
            expActive.fulfill()
        }
        wait(for: [expActive], timeout: 0.2)
        
        // 2. 模拟道路向右折转，航路点右移
        let rightPos = SIMD3<Float>(1.5, -1.4, -2.5)
        player.setNavigationTarget(position: rightPos)
        
        let expRight = expectation(description: "脚步声声源动态平移至右前方")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertTrue(player.isNavigationActive)
            XCTAssertEqual(player.navigationPlayerNode.position.x, 1.5, accuracy: 0.05)
            XCTAssertEqual(player.navigationPlayerNode.position.z, -2.5, accuracy: 0.05)
            expRight.fulfill()
        }
        wait(for: [expRight], timeout: 0.2)
        
        // 3. 通道受阻或到达目的地，传入 nil 取消脚步声
        player.setNavigationTarget(position: nil)
        let expNil = expectation(description: "传入 nil 导航脚步声停止")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertFalse(player.isNavigationActive, "传入 nil 后导航导引必须停止")
            expNil.fulfill()
        }
        wait(for: [expNil], timeout: 0.2)
        
        player.stop()
    }
    
    // MARK: - 测试 6: 导航脚步声自然步频周期性发声验证 (T007 - US2)
    func testNavigationCadencePeriodicPlayback() throws {
        let player = SpatialAudioPlayer()
        try player.start()
        
        // 设定步频为 0.2s 快速单测验证周期性循环
        player.navigationCadenceInterval = 0.2
        player.setNavigationTarget(position: SIMD3<Float>(0.0, 0.0, -2.0))
        
        let expPeriodic = expectation(description: "步频定时器周期循环调度")
        // 0.45s 预期至少调度 2 次以上脚步声发声
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            XCTAssertTrue(player.navigationStepCount >= 2, "在 0.45s 内以 0.2s 步频必须至少触发 2 次踏地声，实测: \(player.navigationStepCount)")
            expPeriodic.fulfill()
        }
        wait(for: [expPeriodic], timeout: 0.6)
        
        player.reset()
        XCTAssertFalse(player.isNavigationActive, "reset 后脚步声必须停止")
        XCTAssertEqual(player.navigationStepCount, 0, "reset 后踏步计数必须归零")
        
        player.stop()
    }
    
    // MARK: - 测试 7: 康复训练达标激励和弦音播放与脚步声压音让位验证 (T009 - US3)
    func testRewardSoundPlaybackAndDucking() throws {
        let player = SpatialAudioPlayer()
        try player.start()
        
        // 1. 激活导航脚步声，初始音量应为 1.0 (100%)
        player.setNavigationTarget(position: SIMD3<Float>(0.0, 0.0, -2.0))
        let expInit = expectation(description: "脚步声激活")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertTrue(player.isNavigationActive)
            XCTAssertEqual(player.navigationPlayerNode.volume, 1.0, accuracy: 0.01)
            expInit.fulfill()
        }
        wait(for: [expInit], timeout: 0.2)
        
        // 2. 触发康复激励音，断言脚步声音量被平滑压低至 0.3 (30%)
        player.playRewardSound()
        let expDucking = expectation(description: "激励音播放期间脚步声被压低至 30%")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertTrue(player.isRewardActive, "激励音当前应处于激活播放态")
            XCTAssertEqual(player.navigationPlayerNode.volume, 0.3, accuracy: 0.01, "播放激励音期间脚步声音量必须降为 30%")
            expDucking.fulfill()
        }
        wait(for: [expDucking], timeout: 0.2)
        
        // 3. 和弦时长 0.4s 播完后，脚步声音量应自动恢复至 1.0 (100%)
        let expRestore = expectation(description: "激励音播完脚步声音量恢复至 100%")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            XCTAssertFalse(player.isRewardActive, "0.4s 后激励音播放完毕应自动结束")
            XCTAssertEqual(player.navigationPlayerNode.volume, 1.0, accuracy: 0.01, "激励音播完后脚步声音量必须恢复至 100%")
            expRestore.fulfill()
        }
        wait(for: [expRestore], timeout: 0.6)
        
        player.stop()
    }
}
