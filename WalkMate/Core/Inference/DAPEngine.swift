//
//  DAPEngine.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import CoreML
import Foundation

// MARK: - 协议定义

/// DAP 全景深度估计引擎服务协议
public protocol DAPEngineProtocol: AnyObject {
    /// 基于归一化张量执行深度推理
    func inferDepth(from input: MLMultiArray, timestampMs: Int64) throws -> DepthMatrix
}

// MARK: - 错误定义

/// DAP 推理引擎错误枚举
public enum DAPEngineError: Error, LocalizedError {
    /// 模型资源未找到
    case modelNotFound(String)
    /// CoreML 预测失败
    case predictionFailed(Error)
    /// 输出特征提取失败
    case missingOutputFeature(String)
    
    /// 错误中文描述
    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "无法定位 DAP 深度估计模型文件: \(path)"
        case .predictionFailed(let err):
            return "DAP 模型 CoreML 硬件推理失败: \(err.localizedDescription)"
        case .missingOutputFeature(let name):
            return "DAP 模型输出中未找到目标深度特征: \(name)"
        }
    }
}

// MARK: - 核心推理引擎实现

/// 基于 Apple Neural Engine (ANE) 硬件加速的 DAP 深度推理执行器
public final class DAPEngine: DAPEngineProtocol {
    
    /// 底层 CoreML 模型实例
    private let model: MLModel
    
    /// 初始化 DAP 推理引擎
    /// - Parameter modelURL: 可选显式传入的模型 URL，若为空则自动在 Bundle 与已知路径中查找
    public init(modelURL: URL? = nil) throws {
        let finalURL: URL
        if let url = modelURL {
            finalURL = url
        } else if let bundleURL = Bundle.main.url(forResource: "dap_256x512_int8", withExtension: "mlpackage") {
            finalURL = bundleURL
        } else if let frameworkBundleURL = Bundle(for: DAPEngine.self).url(forResource: "dap_256x512_int8", withExtension: "mlpackage") {
            finalURL = frameworkBundleURL
        } else {
            // 开发与脱机单元测试环境下的相对路径与工作空间动态定位
            let sourceFileURL = URL(fileURLWithPath: #filePath)
            let projectRootURL = sourceFileURL
                .deletingLastPathComponent() // Inference
                .deletingLastPathComponent() // Core
                .deletingLastPathComponent() // WalkMate
                .deletingLastPathComponent() // 工作空间根目录
            
            let candidatePaths = [
                "WalkMate/Resources/Models/dap_256x512_int8.mlpackage",
                "../WalkMate/Resources/Models/dap_256x512_int8.mlpackage",
                "tmp/dap_256x512_int8.mlpackage",
                "../tmp/dap_256x512_int8.mlpackage",
                projectRootURL.appendingPathComponent("WalkMate/Resources/Models/dap_256x512_int8.mlpackage").path,
                projectRootURL.appendingPathComponent("tmp/dap_256x512_int8.mlpackage").path
            ]
            var foundURL: URL?
            for path in candidatePaths {
                let u = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: u.path) {
                    foundURL = u
                    break
                }
            }
            guard let validURL = foundURL else {
                Log.error("未找到 dap_256x512_int8.mlpackage 模型资源", category: .perception)
                throw DAPEngineError.modelNotFound("dap_256x512_int8.mlpackage")
            }
            finalURL = validURL
        }
        
        Log.info("开始编译并加载 CoreML 模型: \(finalURL.lastPathComponent)", category: .perception)
        
        // 配置 ANE 神经引擎计算单元
        let config = MLModelConfiguration()
        config.computeUnits = .all
        
        // 若为 mlpackage 格式，先执行本地编译缓存
        let compiledURL: URL
        if finalURL.pathExtension == "mlpackage" || finalURL.pathExtension == "mlmodel" {
            compiledURL = try MLModel.compileModel(at: finalURL)
        } else {
            compiledURL = finalURL
        }
        
        self.model = try MLModel(contentsOf: compiledURL, configuration: config)
        Log.info("DAP ANE 硬件模型加载成功", category: .perception)
    }
    
    // MARK: - 深度推理方法
    
    /// 执行深度推理并返回物理深度矩阵
    /// - Parameters:
    ///   - input: 预处理后的图像张量 [1, 3, 256, 512]
    ///   - timestampMs: 毫秒时间戳
    /// - Returns: 全向物理深度矩阵 (256x512)
    public func inferDepth(from input: MLMultiArray, timestampMs: Int64) throws -> DepthMatrix {
        // 1. 构建 CoreML 特征输入字典
        let featureDictionary: [String: Any] = ["image": input]
        let featureProvider = try MLDictionaryFeatureProvider(dictionary: featureDictionary)
        
        // 2. 执行模型推理 (在 ANE 上硬件执行)
        let predictionOutput: MLFeatureProvider
        do {
            predictionOutput = try model.prediction(from: featureProvider)
        } catch {
            Log.error("CoreML 预测报错: \(error.localizedDescription)", category: .perception)
            throw DAPEngineError.predictionFailed(error)
        }
        
        // 3. 提取输出特征 "pred_depth"
        guard let depthFeature = predictionOutput.featureValue(for: "pred_depth")?.multiArrayValue else {
            Log.error("未在模型输出中找到 pred_depth 特征", category: .perception)
            throw DAPEngineError.missingOutputFeature("pred_depth")
        }
        
        // 4. 解析深度数据构建 DepthMatrix
        let totalCount = DepthMatrix.width * DepthMatrix.height
        var values = ContiguousArray<Float>(repeating: 0.0, count: totalCount)
        
        var minVal: Float = Float.infinity
        var maxVal: Float = -Float.infinity
        
        // 检查数据类型 (Float16 或 Float32)
        if depthFeature.dataType == .float16 {
            let ptr = depthFeature.dataPointer.bindMemory(to: Float16.self, capacity: totalCount)
            for i in 0..<totalCount {
                let depth = Float(ptr[i])
                values[i] = depth
                if depth > 0 {
                    if depth < minVal { minVal = depth }
                    if depth > maxVal { maxVal = depth }
                }
            }
        } else {
            let ptr = depthFeature.dataPointer.bindMemory(to: Float.self, capacity: totalCount)
            for i in 0..<totalCount {
                let depth = ptr[i]
                values[i] = depth
                if depth > 0 {
                    if depth < minVal { minVal = depth }
                    if depth > maxVal { maxVal = depth }
                }
            }
        }
        
        if minVal == Float.infinity { minVal = 0.0 }
        if maxVal == -Float.infinity { maxVal = 0.0 }
        
        return DepthMatrix(
            values: values,
            minDepth: minVal,
            maxDepth: maxVal,
            timestampMs: timestampMs
        )
    }
}
