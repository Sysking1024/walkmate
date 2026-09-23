//
//  Log.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-22.
//

import Foundation
import os

/// 统一业务结构化日志工具类
/// 严格遵循宪章原则五、八、九：
/// 1. 业务日志内容统一使用中文；
/// 2. 日志级别遵循行业标准英文（DEBUG, INFO, WARNING, ERROR, SEVERE）；
/// 3. 基于系统 os.Logger 进行封装，严禁在业务代码中使用 print()。
public enum Log {
    
    // 子系统标识，与 App Bundle ID 保持一致
    private static let subsystem = "accera.world.walkmate"
    
    // 按业务分类的专属 Logger 实例
    private static let cameraLogger = Logger(subsystem: subsystem, category: "Camera")
    private static let perceptionLogger = Logger(subsystem: subsystem, category: "Perception")
    private static let uiLogger = Logger(subsystem: subsystem, category: "UI")
    private static let generalLogger = Logger(subsystem: subsystem, category: "General")
    private static let narrationLogger = Logger(subsystem: subsystem, category: "Narration")
    private static let recordingLogger = Logger(subsystem: subsystem, category: "Recording")
    
    /// 调试信息（细粒度追踪、瞬时计算状态等）
    /// - Parameters:
    ///   - message: 中文业务日志描述
    ///   - category: 业务分类
    public static func debug(_ message: String, category: Category = .general) {
        logger(for: category).debug("[\(category.rawValue)] \(message, privacy: .public)")
    }
    
    /// 关键业务里程碑信息（连接建立、模式切换、推流开启等）
    /// - Parameters:
    ///   - message: 中文业务日志描述
    ///   - category: 业务分类
    public static func info(_ message: String, category: Category = .general) {
        logger(for: category).info("[\(category.rawValue)] \(message, privacy: .public)")
    }
    
    /// 业务告警（瞬时丢帧、非阻塞性异常等）
    /// - Parameters:
    ///   - message: 中文业务日志描述
    ///   - category: 业务分类
    public static func warning(_ message: String, category: Category = .general) {
        logger(for: category).warning("[\(category.rawValue)] ⚠️ \(message, privacy: .public)")
    }
    
    /// 错误信息（连接失败、解析异常、模型运行错误等）
    /// - Parameters:
    ///   - message: 中文业务日志描述
    ///   - error: 可选关联错误对象
    ///   - category: 业务分类
    public static func error(_ message: String, error: Error? = nil, category: Category = .general) {
        if let error = error {
            logger(for: category).error("[\(category.rawValue)] ❌ \(message, privacy: .public) | 错误详情: \(error.localizedDescription, privacy: .public)")
        } else {
            logger(for: category).error("[\(category.rawValue)] ❌ \(message, privacy: .public)")
        }
    }
    
    /// 严重故障（硬件死锁、致命资源缺失等）
    /// - Parameters:
    ///   - message: 中文业务日志描述
    ///   - category: 业务分类
    public static func severe(_ message: String, category: Category = .general) {
        logger(for: category).fault("[\(category.rawValue)] 🛑 \(message, privacy: .public)")
    }
    
    /// 获取对应分类的 Logger 实例
    private static func logger(for category: Category) -> Logger {
        switch category {
        case .camera:
            return cameraLogger
        case .perception:
            return perceptionLogger
        case .ui:
            return uiLogger
        case .general:
            return generalLogger
        case .narration:
            return narrationLogger
        case .recording:
            return recordingLogger
        }
    }
    
    /// 日志业务领域分类枚举
    public enum Category: String {
        case camera = "相机管道"
        case perception = "空间感知"
        case ui = "用户界面"
        case general = "基础通用"
        /// 场景描述、伙伴对谈与语音合成
        case narration = "场景描述"
        /// 训练记录短片的合成与导出
        case recording = "记录合成"
    }
}
