//
//  PerceptionReplayer.swift
//  ReplayTests
//
//  Created by Antigravity on 2026-09-23.
//

import Foundation
import SSZipArchive
@testable import WalkMate

// MARK: - 回放错误定义

/// 离线回放数据加载与解压错误类型
public enum PerceptionReplayerError: LocalizedError, Sendable {
    case metadataNotFound(String)
    case telemetryNotFound(String)
    case corruptedData(String)
    case archiveUnpackFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .metadataNotFound(let path):
            return "会话元数据文件 metadata.json 不存在: \(path)"
        case .telemetryNotFound(let path):
            return "时序遥测文件 telemetry.jsonl 不存在: \(path)"
        case .corruptedData(let detail):
            return "实测数据损坏或解析失败: \(detail)"
        case .archiveUnpackFailed(let path):
            return "解压归档包失败: \(path)"
        }
    }
}

// MARK: - 离线回放驱动器核心协议

/// 离线回放数据加载与时间戳对齐驱动接口
public protocol PerceptionReplayerProtocol: AnyObject, Sendable {
    /// 当前已载入会话的全局元数据
    var sessionMetadata: SessionMetadata? { get }
    /// 当前已载入的时序遥测帧总数
    var totalFrames: Int { get }
    /// 获取全部已解析的时序遥测快照记录列表
    var telemetryRecords: [FrameTelemetryRecord] { get }
    /// 当前会话所在的沙盒文件夹绝对路径
    var currentFolderURL: URL? { get }
    
    /// 加载并解析指定沙盒会话目录 (包含 metadata.json 与 telemetry.jsonl)
    func loadSession(folderURL: URL) throws -> SessionMetadata
    
    /// 从 .zip 压缩包归档解压并直接加载为离线回放会话
    func loadArchive(zipURL: URL, destinationDir: URL) throws -> SessionMetadata
    
    /// 获取指定索引的时序遥测记录
    func telemetryRecord(at index: Int) -> FrameTelemetryRecord?
    
    /// 读取指定毫秒时间戳对应的原始全景图像快照二进制数据 (JPEG)
    func loadImageSnapshot(timestampMs: Int64) -> Data?
    
    /// 读取指定毫秒时间戳对应的物理深度矩阵快照 (DepthMatrix 256x512)
    func loadDepthSnapshot(timestampMs: Int64) -> DepthMatrix?
}

// MARK: - 离线回放驱动器具体实现

/// 负责从解压会话目录或 zip 压缩包中高速解析时序遥测流、视觉图像与全景深度快照
public final class PerceptionReplayer: PerceptionReplayerProtocol, @unchecked Sendable {
    
    private let lock = NSLock()
    private let jsonDecoder = JSONDecoder()
    
    private var _metadata: SessionMetadata?
    private var _records: [FrameTelemetryRecord] = []
    private var _folderURL: URL?
    
    public var sessionMetadata: SessionMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return _metadata
    }
    
    public var totalFrames: Int {
        lock.lock()
        defer { lock.unlock() }
        return _records.count
    }
    
    public var telemetryRecords: [FrameTelemetryRecord] {
        lock.lock()
        defer { lock.unlock() }
        return _records
    }
    
    public var currentFolderURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return _folderURL
    }
    
    public init() {}
    
    // MARK: - 会话加载与流式解析
    
    /// 从解压后的实测数据目录加载会话
    @discardableResult
    public func loadSession(folderURL: URL) throws -> SessionMetadata {
        lock.lock()
        defer { lock.unlock() }
        
        let fm = FileManager.default
        
        // 递归或直接探查包含 metadata.json 的有效会话根目录
        var targetFolder = folderURL
        let directMetadataURL = targetFolder.appendingPathComponent("metadata.json")
        if !fm.fileExists(atPath: directMetadataURL.path) {
            // 尝试在子目录中寻找（应对解压后多了一层 session_xxx/ 包装）
            if let subItems = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey]) {
                if let sessionSubfolder = subItems.first(where: {
                    fm.fileExists(atPath: $0.appendingPathComponent("metadata.json").path)
                }) {
                    targetFolder = sessionSubfolder
                }
            }
        }
        
        let metadataURL = targetFolder.appendingPathComponent("metadata.json")
        guard fm.fileExists(atPath: metadataURL.path) else {
            throw PerceptionReplayerError.metadataNotFound(metadataURL.path)
        }
        
        // 1. 解码 metadata.json
        let metadataData = try Data(contentsOf: metadataURL)
        let metadata: SessionMetadata
        do {
            metadata = try jsonDecoder.decode(SessionMetadata.self, from: metadataData)
        } catch {
            throw PerceptionReplayerError.corruptedData("解析 metadata.json 失败: \(error.localizedDescription)")
        }
        
        // 2. 流式逐行解析 telemetry.jsonl
        let telemetryURL = targetFolder.appendingPathComponent("telemetry.jsonl")
        guard fm.fileExists(atPath: telemetryURL.path) else {
            throw PerceptionReplayerError.telemetryNotFound(telemetryURL.path)
        }
        
        let contentString = try String(contentsOf: telemetryURL, encoding: .utf8)
        var parsedRecords: [FrameTelemetryRecord] = []
        parsedRecords.reserveCapacity(metadata.totalTelemetryFrames > 0 ? metadata.totalTelemetryFrames : 100)
        
        contentString.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            
            if let lineData = trimmed.data(using: .utf8) {
                if let record = try? self.jsonDecoder.decode(FrameTelemetryRecord.self, from: lineData) {
                    parsedRecords.append(record)
                }
            }
        }
        
        self._metadata = metadata
        self._records = parsedRecords
        self._folderURL = targetFolder
        
        return metadata
    }
    
    /// 从 .zip 压缩归档解压并载入会话
    @discardableResult
    public func loadArchive(zipURL: URL, destinationDir: URL) throws -> SessionMetadata {
        let fm = FileManager.default
        if !fm.fileExists(atPath: destinationDir.path) {
            try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        let success = SSZipArchive.unzipFile(atPath: zipURL.path, toDestination: destinationDir.path)
        guard success else {
            throw PerceptionReplayerError.archiveUnpackFailed(zipURL.path)
        }
        
        return try loadSession(folderURL: destinationDir)
    }
    
    // MARK: - 帧数据与快照访问
    
    /// 获取指定索引的遥测记录
    public func telemetryRecord(at index: Int) -> FrameTelemetryRecord? {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0 && index < _records.count else { return nil }
        return _records[index]
    }
    
    /// 读取指定时间戳对应的全景视觉 JPEG 快照
    public func loadImageSnapshot(timestampMs: Int64) -> Data? {
        lock.lock()
        guard let folder = _folderURL else {
            lock.unlock()
            return nil
        }
        lock.unlock()
        
        let frameURL = folder.appendingPathComponent("frames").appendingPathComponent("\(timestampMs).jpg")
        return try? Data(contentsOf: frameURL)
    }
    
    /// 读取指定时间戳对应的 256x512 物理深度矩阵二进制快照
    public func loadDepthSnapshot(timestampMs: Int64) -> DepthMatrix? {
        lock.lock()
        guard let folder = _folderURL else {
            lock.unlock()
            return nil
        }
        lock.unlock()
        
        let depthURL = folder.appendingPathComponent("depths").appendingPathComponent("\(timestampMs).bin")
        guard let data = try? Data(contentsOf: depthURL) else { return nil }
        
        let expectedCount = DepthMatrix.width * DepthMatrix.height
        let expectedBytes = expectedCount * MemoryLayout<Float>.size
        guard data.count == expectedBytes else { return nil }
        
        var values = ContiguousArray<Float>(repeating: 0.0, count: expectedCount)
        values.withUnsafeMutableBytes { destBuffer in
            _ = data.copyBytes(to: destBuffer)
        }
        
        // 快速统计有效深度极值
        var minD: Float = 100.0
        var maxD: Float = 0.0
        for val in values {
            if !val.isNaN && val > 0.05 {
                if val < minD { minD = val }
                if val > maxD { maxD = val }
            }
        }
        if minD > maxD {
            minD = 0.0
            maxD = 5.0
        }
        
        return DepthMatrix(
            values: values,
            minDepth: minD,
            maxDepth: maxD,
            timestampMs: timestampMs
        )
    }
}
