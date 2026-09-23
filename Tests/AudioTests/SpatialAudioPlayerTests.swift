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
}
