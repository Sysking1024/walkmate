//
//  SessionStorageManagerTests.swift
//  AppTests
//
//  Created by Antigravity on 2026-09-23.
//

import XCTest
import SSZipArchive
@testable import WalkMate

/// 会话沙盒存储管理器单元测试
final class SessionStorageManagerTests: XCTestCase {
    
    private var tempDirectoryURL: URL!
    private var storageManager: SessionStorageManager!
    
    override func setUp() {
        super.setUp()
        // 使用独立的临时目录隔离每次单测，避免污染真机/模拟器 Documents 目录
        let uniqueName = "TestSessions_\(UUID().uuidString)"
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueName, isDirectory: true)
        storageManager = SessionStorageManager(baseDirectoryURL: tempDirectoryURL)
    }
    
    override func tearDown() {
        if let dir = tempDirectoryURL, FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
        storageManager = nil
        super.tearDown()
    }
    
    // MARK: - 基础目录与生命周期测试
    
    /// 验证会话根目录自动创建
    func testSessionDirectoryInitialization() {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: storageManager.sessionsDirectoryURL.path),
            "会话管理器初始化时必须自动创建根目录"
        )
    }
    
    /// 验证创建独立会话目录并保存/读取元数据
    func testCreateSessionAndMetadataPersistence() throws {
        let sessionId = "session_20260923_120000"
        let sessionURL = try storageManager.createSessionFolder(sessionId: sessionId)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionURL.appendingPathComponent("frames").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionURL.appendingPathComponent("depths").path))
        
        let metadata = SessionMetadata(
            sessionId: sessionId,
            startTimeMs: 1727092800000,
            endTimeMs: 1727092830000,
            durationSeconds: 30.0,
            totalTelemetryFrames: 450,
            totalImageSnapshots: 60,
            deviceInfo: "iPhone 16",
            appVersion: "1.0.0",
            algorithmConfig: ["groundTolerance": "0.08"]
        )
        
        try storageManager.saveMetadata(metadata, sessionId: sessionId)
        
        let loadedMetadata = try storageManager.loadMetadata(sessionId: sessionId)
        XCTAssertEqual(loadedMetadata.sessionId, sessionId)
        XCTAssertEqual(loadedMetadata.durationSeconds, 30.0)
        XCTAssertEqual(loadedMetadata.totalTelemetryFrames, 450)
        XCTAssertEqual(loadedMetadata.totalImageSnapshots, 60)
        XCTAssertEqual(loadedMetadata.algorithmConfig["groundTolerance"], "0.08")
    }
    
    /// 验证会话列表枚举与时间倒序排序
    func testListSessionsOrderingAndFormatting() throws {
        let session1 = "session_20260923_100000"
        let session2 = "session_20260923_110000"
        
        _ = try storageManager.createSessionFolder(sessionId: session1)
        let meta1 = SessionMetadata(
            sessionId: session1,
            startTimeMs: 1000,
            durationSeconds: 45,
            totalTelemetryFrames: 100
        )
        try storageManager.saveMetadata(meta1, sessionId: session1)
        
        // 稍作微小延迟以确保文件创建时间有区分
        Thread.sleep(forTimeInterval: 0.05)
        
        _ = try storageManager.createSessionFolder(sessionId: session2)
        let meta2 = SessionMetadata(
            sessionId: session2,
            startTimeMs: 2000,
            durationSeconds: 90,
            totalTelemetryFrames: 200
        )
        try storageManager.saveMetadata(meta2, sessionId: session2)
        
        let list = storageManager.listSessions()
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].sessionId, session2, "较晚创建的会话应排在首位")
        XCTAssertEqual(list[1].sessionId, session1)
        XCTAssertEqual(list[0].durationFormatted, "01:30")
        XCTAssertEqual(list[1].durationFormatted, "00:45")
    }
    
    /// 验证单项删除与清空所有历史会话
    func testDeleteSessionAndClearAll() throws {
        let sessionA = "session_A"
        let sessionB = "session_B"
        
        _ = try storageManager.createSessionFolder(sessionId: sessionA)
        _ = try storageManager.createSessionFolder(sessionId: sessionB)
        XCTAssertEqual(storageManager.listSessions().count, 2)
        
        try storageManager.deleteSession(sessionId: sessionA)
        let afterDelete = storageManager.listSessions()
        XCTAssertEqual(afterDelete.count, 1)
        XCTAssertEqual(afterDelete.first?.sessionId, sessionB)
        
        try storageManager.clearAllSessions()
        XCTAssertEqual(storageManager.listSessions().count, 0)
    }
    
    /// 验证存储空间阈值检查方法
    func testSufficientStorageCheck() {
        // 请求极小的 1MB 空间，测试机必然满足
        XCTAssertTrue(
            storageManager.hasSufficientStorage(minRequiredMB: 1),
            "常规系统环境应有至少 1MB 空间"
        )
        // 请求极大的空间（如 1000TB），必然返回 false 触发保护
        XCTAssertFalse(
            storageManager.hasSufficientStorage(minRequiredMB: 1_000_000_000),
            "超过实际磁盘总量的请求必须触发拒绝保护"
        )
    }
    
    // MARK: - Zip 归档与解压完整性测试 (T011)
    
    /// 验证基于 SSZipArchive 的会话目录极速打包与解压还原完整性
    func testCreateZipArchiveAndVerifyIntegrity() throws {
        let sessionId = "session_zip_test"
        let folder = try storageManager.createSessionFolder(sessionId: sessionId)
        
        // 构造虚拟文件
        let meta = SessionMetadata(
            sessionId: sessionId,
            startTimeMs: 1727092800000,
            durationSeconds: 15,
            totalTelemetryFrames: 150
        )
        try storageManager.saveMetadata(meta, sessionId: sessionId)
        
        let dummyTelemetry = "{\"frameIndex\":0}\n{\"frameIndex\":1}\n"
        try dummyTelemetry.write(to: folder.appendingPathComponent("telemetry.jsonl"), atomically: true, encoding: .utf8)
        
        var progressValues: [Double] = []
        let zipURL = try storageManager.createArchive(sessionId: sessionId) { progress in
            progressValues.append(progress)
        }
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path), "打包生成的 .zip 文件必须存在")
        XCTAssertGreaterThan(try Data(contentsOf: zipURL).count, 0, "压缩包大小必须大于 0")
        
        // 解压至独立验证目录
        let unpackDir = tempDirectoryURL.appendingPathComponent("Unpacked_\(sessionId)", isDirectory: true)
        let unzipSuccess = SSZipArchive.unzipFile(atPath: zipURL.path, toDestination: unpackDir.path)
        XCTAssertTrue(unzipSuccess, "SSZipArchive 解压必须成功")
        
        // 验证解压后目录结构
        let unpackedSessionDir = unpackDir.appendingPathComponent(sessionId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unpackedSessionDir.appendingPathComponent("metadata.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unpackedSessionDir.appendingPathComponent("telemetry.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unpackedSessionDir.appendingPathComponent("frames").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unpackedSessionDir.appendingPathComponent("depths").path))
    }
    
    /// 验证对不存在的会话执行归档时抛出标准错误
    func testArchiveNonExistentSessionThrows() {
        XCTAssertThrowsError(try storageManager.createArchive(sessionId: "invalid_session_id")) { error in
            guard let storageError = error as? SessionStorageError else {
                XCTFail("必须抛出 SessionStorageError 错误类型")
                return
            }
            switch storageError {
            case .sessionNotFound:
                break
            default:
                XCTFail("对于不存在的会话必须返回 sessionNotFound")
            }
        }
    }
    
    /// 验证应用异常强退未正常封包时的流式元数据自愈恢复 (T019 / SC-003)
    func testRecoverInterruptedSession() throws {
        let sessionId = "session_interrupted_001"
        let folder = try storageManager.createSessionFolder(sessionId: sessionId)
        
        // 模拟未正常关闭的 metadata (endTimeMs 为 nil)
        let initialMetadata = SessionMetadata(
            sessionId: sessionId,
            startTimeMs: 1774340000000,
            endTimeMs: nil,
            durationSeconds: 0,
            totalTelemetryFrames: 0,
            totalImageSnapshots: 0
        )
        try storageManager.saveMetadata(initialMetadata, sessionId: sessionId)
        
        // 模拟已落盘的 3 帧时序数据
        var jsonlData = ""
        for i in 0..<3 {
            let record = FrameTelemetryRecord(
                timestampMs: 1774340000000 + Int64(i * 100),
                frameIndex: i,
                quaternion: QuaternionRecord(x: 0, y: 0, z: 0, w: 1),
                eulerAngles: EulerAnglesRecord(roll: 0, pitch: 0, yaw: 0),
                acceleration: SIMD3Record(x: 0, y: -9.8, z: 0),
                groundPlane: [0, 1, 0, 1.4],
                cameraHeight: 1.4,
                rawObstacles: [],
                hazardObstacles: [],
                activeObstacleTarget: nil,
                isPassable: true,
                safeDepth: 5.0,
                recommendedHeading: 0.0,
                waypoints: [],
                activeNavigationTarget: nil,
                processingLatencyMs: 5.0,
                hasImageSnapshot: false
            )
            let lineData = try JSONEncoder().encode(record)
            jsonlData.append(String(data: lineData, encoding: .utf8)! + "\n")
        }
        try jsonlData.write(to: folder.appendingPathComponent("telemetry.jsonl"), atomically: true, encoding: .utf8)
        
        // 触发自愈
        let recovered = storageManager.recoverInterruptedSession(sessionId: sessionId, existingMetadata: initialMetadata)
        XCTAssertNotNil(recovered, "自愈后必须生成完整元数据")
        XCTAssertEqual(recovered?.totalTelemetryFrames, 3, "自愈帧数必须为 3")
        XCTAssertEqual(recovered?.endTimeMs, 1774340000200, "自愈结束时间戳必须对齐末帧")
        XCTAssertGreaterThan(recovered?.durationSeconds ?? 0, 0, "时长必须大于 0")
        
        // 校验 listSessions() 此时正常展示该自愈会话
        let sessions = storageManager.listSessions()
        let target = sessions.first { $0.sessionId == sessionId }
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.totalFrames, 3)
    }
}

