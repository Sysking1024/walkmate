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
}
