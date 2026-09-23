//
//  SessionStorageManager.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import Foundation
import SSZipArchive

// MARK: - 存储错误枚举

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

// MARK: - 会话存储服务协议

/// 会话持久化与导出服务接口
public protocol SessionStorageManagerProtocol: Sendable {
    /// 沙盒内会话根目录 URL (Documents/Sessions/)
    var sessionsDirectoryURL: URL { get }
    
    /// 检查当前设备空闲存储空间是否满足录制要求 (默认 >= 500MB)
    func hasSufficientStorage(minRequiredMB: Int) -> Bool
    
    /// 创建独立会话文件夹及其子目录 (frames, depths)
    func createSessionFolder(sessionId: String) throws -> URL
    
    /// 保存会话元数据
    func saveMetadata(_ metadata: SessionMetadata, sessionId: String) throws
    
    /// 加载指定会话的元数据
    func loadMetadata(sessionId: String) throws -> SessionMetadata
    
    /// 获取指定会话的文件夹路径
    func sessionFolderURL(for sessionId: String) -> URL
    
    /// 获取当前所有历史会话摘要列表 (按时间降序排列)
    func listSessions() -> [SessionSummaryItem]
    
    /// 删除指定会话及其包含的所有文件
    func deleteSession(sessionId: String) throws
    
    /// 清理所有历史会话
    func clearAllSessions() throws
    
    /// 将指定会话目录打包为 .zip 归档文件
    func createArchive(sessionId: String, progress: ((Double) -> Void)?) throws -> URL
}

// MARK: - 会话沙盒存储管理器实现

/// 负责真机沙盒 Documents/Sessions 目录的管理、空间监控及 zip 压缩打包
public final class SessionStorageManager: SessionStorageManagerProtocol, @unchecked Sendable {
    
    /// 沙盒内会话根目录 URL
    public let sessionsDirectoryURL: URL
    
    /// 默认单例实例
    public static let shared = SessionStorageManager()
    
    /// 默认安全存储门限 (500MB)
    public static let defaultSafetyStorageThresholdMB: Int = 500
    
    private let fileManager = FileManager.default
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    
    /// 初始化会话存储管理器
    /// - Parameter baseDirectoryURL: 自定义基准目录（若为 nil 则默认使用 Documents/Sessions）
    public init(baseDirectoryURL: URL? = nil) {
        if let base = baseDirectoryURL {
            self.sessionsDirectoryURL = base
        } else {
            let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.sessionsDirectoryURL = docsURL.appendingPathComponent("Sessions", isDirectory: true)
        }
        
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        ensureRootDirectoryExists()
    }
    
    // MARK: - 目录安全初始化
    
    private func ensureRootDirectoryExists() {
        if !fileManager.fileExists(atPath: sessionsDirectoryURL.path) {
            do {
                try fileManager.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                Log.error("创建会话根目录失败: \(error.localizedDescription)", category: .general)
            }
        }
    }
    
    // MARK: - 存储容量检查
    
    /// 检查设备空闲存储空间是否满足指定兆字节数
    public func hasSufficientStorage(minRequiredMB: Int = defaultSafetyStorageThresholdMB) -> Bool {
        do {
            let resourceValues = try sessionsDirectoryURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            
            let availableBytes: Int64
            if let important = resourceValues.volumeAvailableCapacityForImportantUsage {
                availableBytes = important
            } else if let general = resourceValues.volumeAvailableCapacity {
                availableBytes = Int64(general)
            } else {
                return false
            }
            
            let requiredBytes = Int64(minRequiredMB) * 1024 * 1024
            return availableBytes >= requiredBytes
        } catch {
            Log.error("检查磁盘剩余空间失败: \(error.localizedDescription)", category: .general)
            return false
        }
    }
    
    // MARK: - 会话文件夹与元数据管理
    
    /// 获取指定会话文件夹的绝对路径
    public func sessionFolderURL(for sessionId: String) -> URL {
        return sessionsDirectoryURL.appendingPathComponent(sessionId, isDirectory: true)
    }
    
    /// 创建独立会话文件夹以及用于抽样快照的 frames/ 和 depths/ 子目录
    public func createSessionFolder(sessionId: String) throws -> URL {
        let folder = sessionFolderURL(for: sessionId)
        let framesFolder = folder.appendingPathComponent("frames", isDirectory: true)
        let depthsFolder = folder.appendingPathComponent("depths", isDirectory: true)
        
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
            try fileManager.createDirectory(at: framesFolder, withIntermediateDirectories: true, attributes: nil)
            try fileManager.createDirectory(at: depthsFolder, withIntermediateDirectories: true, attributes: nil)
            return folder
        } catch {
            throw SessionStorageError.ioFailure("无法创建会话目录: \(error.localizedDescription)")
        }
    }
    
    /// 将会话元数据写入 metadata.json
    public func saveMetadata(_ metadata: SessionMetadata, sessionId: String) throws {
        let folder = sessionFolderURL(for: sessionId)
        guard fileManager.fileExists(atPath: folder.path) else {
            throw SessionStorageError.sessionNotFound(sessionId)
        }
        
        let fileURL = folder.appendingPathComponent("metadata.json")
        do {
            let data = try jsonEncoder.encode(metadata)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw SessionStorageError.ioFailure("保存会话元数据失败: \(error.localizedDescription)")
        }
    }
    
    /// 读取指定会话的 metadata.json
    public func loadMetadata(sessionId: String) throws -> SessionMetadata {
        let fileURL = sessionFolderURL(for: sessionId).appendingPathComponent("metadata.json")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw SessionStorageError.sessionNotFound(sessionId)
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try jsonDecoder.decode(SessionMetadata.self, from: data)
        } catch {
            throw SessionStorageError.ioFailure("解析会话元数据失败: \(error.localizedDescription)")
        }
    }
    
    /// 针对应用强退或意外中断的会话，从 telemetry.jsonl 流式解析并自愈元数据 (SC-003)
    @discardableResult
    public func recoverInterruptedSession(sessionId: String, existingMetadata: SessionMetadata? = nil) -> SessionMetadata? {
        let folder = sessionFolderURL(for: sessionId)
        let telemetryURL = folder.appendingPathComponent("telemetry.jsonl")
        guard fileManager.fileExists(atPath: telemetryURL.path),
              let content = try? String(contentsOf: telemetryURL, encoding: .utf8) else {
            return existingMetadata
        }
        
        var lineCount = 0
        var lastTimestamp: Int64 = 0
        var firstTimestamp: Int64 = 0
        
        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if let data = trimmed.data(using: .utf8),
               let record = try? self.jsonDecoder.decode(FrameTelemetryRecord.self, from: data) {
                if lineCount == 0 {
                    firstTimestamp = record.timestampMs
                }
                lastTimestamp = record.timestampMs
                lineCount += 1
            }
        }
        
        guard lineCount > 0 else { return existingMetadata }
        
        let startMs = existingMetadata?.startTimeMs ?? firstTimestamp
        let endMs = lastTimestamp
        let duration = max(0.0, Double(endMs - startMs) / 1000.0)
        
        // 统计图像快照总数
        let framesDir = folder.appendingPathComponent("frames")
        let imageCount = (try? fileManager.contentsOfDirectory(at: framesDir, includingPropertiesForKeys: nil).count) ?? 0
        
        let recovered = SessionMetadata(
            sessionId: sessionId,
            startTimeMs: startMs,
            endTimeMs: endMs,
            durationSeconds: duration,
            totalTelemetryFrames: lineCount,
            totalImageSnapshots: imageCount,
            deviceInfo: existingMetadata?.deviceInfo ?? "iPhone (自愈恢复)",
            appVersion: existingMetadata?.appVersion ?? "1.0.0",
            algorithmConfig: existingMetadata?.algorithmConfig ?? [:]
        )
        
        try? saveMetadata(recovered, sessionId: sessionId)
        Log.info("成功自愈强退会话元数据: \(sessionId), 恢复 \(lineCount) 帧", category: .perception)
        return recovered
    }
    
    // MARK: - 会话列表检索与格式化
    
    /// 枚举所有已记录的会话摘要，按创建时间由新到旧排序
    public func listSessions() -> [SessionSummaryItem] {
        ensureRootDirectoryExists()
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: sessionsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        var items: [SessionSummaryItem] = []
        
        for url in contents {
            // 仅扫描文件夹（跳过压缩包 .zip 文件等）
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                continue
            }
            
            let sessionId = url.lastPathComponent
            var metadata = try? loadMetadata(sessionId: sessionId)
            if metadata == nil || metadata?.endTimeMs == nil {
                metadata = recoverInterruptedSession(sessionId: sessionId, existingMetadata: metadata)
            }
            
            let creationDate = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
            let totalFrames = metadata?.totalTelemetryFrames ?? 0
            let durationSeconds = metadata?.durationSeconds ?? 0
            let durationFormatted = formatDuration(seconds: durationSeconds)
            
            let folderBytes = calculateDirectorySize(url: url)
            let sizeFormatted = formatSize(bytes: folderBytes)
            
            let item = SessionSummaryItem(
                sessionId: sessionId,
                folderURL: url,
                createdAt: creationDate,
                durationFormatted: durationFormatted,
                sizeFormatted: sizeFormatted,
                totalFrames: totalFrames,
                isCurrentlyRecording: false
            )
            items.append(item)
        }
        
        // 按创建时间降序排序 (最新的排在前面)
        return items.sorted { $0.createdAt > $1.createdAt }
    }
    
    // MARK: - 删除与清理
    
    /// 删除指定会话及其包含的所有内容
    public func deleteSession(sessionId: String) throws {
        let folder = sessionFolderURL(for: sessionId)
        let zipURL = sessionsDirectoryURL.appendingPathComponent("\(sessionId).zip")
        
        if fileManager.fileExists(atPath: folder.path) {
            try? fileManager.removeItem(at: folder)
        }
        if fileManager.fileExists(atPath: zipURL.path) {
            try? fileManager.removeItem(at: zipURL)
        }
    }
    
    /// 清理所有历史会话数据
    public func clearAllSessions() throws {
        guard let contents = try? fileManager.contentsOfDirectory(at: sessionsDirectoryURL, includingPropertiesForKeys: nil) else {
            return
        }
        for item in contents {
            try? fileManager.removeItem(at: item)
        }
    }
    
    // MARK: - 极速 Zip 压缩打包 (基于 SSZipArchive)
    
    /// 调用工程内置 SSZipArchive 将会话目录压缩为单个 .zip 归档
    public func createArchive(sessionId: String, progress: ((Double) -> Void)? = nil) throws -> URL {
        let sourceFolder = sessionFolderURL(for: sessionId)
        guard fileManager.fileExists(atPath: sourceFolder.path) else {
            throw SessionStorageError.sessionNotFound(sessionId)
        }
        
        let destinationZipURL = sessionsDirectoryURL.appendingPathComponent("\(sessionId).zip")
        // 若先前已存在同名 zip 则先删除
        if fileManager.fileExists(atPath: destinationZipURL.path) {
            try? fileManager.removeItem(at: destinationZipURL)
        }
        
        let success = SSZipArchive.createZipFile(
            atPath: destinationZipURL.path,
            withContentsOfDirectory: sourceFolder.path,
            keepParentDirectory: true,
            withPassword: nil,
            andProgressHandler: { entry, total in
                if total > 0 {
                    let progressFraction = Double(entry) / Double(total)
                    progress?(progressFraction)
                }
            }
        )
        
        guard success, fileManager.fileExists(atPath: destinationZipURL.path) else {
            throw SessionStorageError.archiveCreationFailed("SSZipArchive 压缩返回失败或文件未落盘")
        }
        
        return destinationZipURL
    }
    
    // MARK: - 内部格式化辅助函数
    
    private func formatDuration(seconds: Double) -> String {
        let totalSecs = Int(seconds.rounded())
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    private func formatSize(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useBytes]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func calculateDirectorySize(url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                totalBytes += Int64(size)
            }
        }
        return totalBytes
    }
}
