import Foundation
import os

/// 统一业务日志工具。
///
/// 遵循宪章原则八与原则九：
/// - 日志级别（Level）采用行业标准英文枚举，便于自动化脚本与通用 AI 解析；
/// - 业务消息内容（Message）统一使用中文；
/// - 全项目严禁使用 `print()` 进行调试输出，一律通过本工具记录。
enum Log {

    /// 日志子系统标识，与 Bundle ID 保持一致，便于在 Console.app 中定位本应用
    private static let subsystem = "accera.insta.dap"

    /// 业务模块分类。作为机器可读的过滤字段，与日志级别同理保留英文标识。
    enum Category: String {
        /// 相机连接与数据流
        case camera = "Camera"
        /// 深度推理与空间感知
        case perception = "Perception"
        /// 场景描述与大模型调用
        case narration = "Narration"
        /// 记录合成与导出
        case recording = "Recording"
        /// 界面与无障碍交互
        case ui = "UI"
    }

    /// 按模块缓存 Logger 实例，避免高频调用时重复构造
    private static var loggers: [Category: Logger] = [:]

    /// 取得指定模块的底层 Logger
    private static func logger(for category: Category) -> Logger {
        if let cached = loggers[category] { return cached }
        let created = Logger(subsystem: subsystem, category: category.rawValue)
        loggers[category] = created
        return created
    }

    /// 调试信息：仅用于开发期定位问题，发布构建不保留
    static func debug(_ category: Category, _ message: String) {
        logger(for: category).debug("[DEBUG] \(message, privacy: .public)")
    }

    /// 常规信息：记录关键业务流转节点（状态切换、设备连接、关键决策）
    static func info(_ category: Category, _ message: String) {
        logger(for: category).info("[INFO] \(message, privacy: .public)")
    }

    /// 警告：业务可继续，但出现了非预期状况
    static func warning(_ category: Category, _ message: String) {
        logger(for: category).warning("[WARNING] \(message, privacy: .public)")
    }

    /// 错误：业务流程中断，需要排障介入
    static func error(_ category: Category, _ message: String) {
        logger(for: category).error("[ERROR] \(message, privacy: .public)")
    }
}
