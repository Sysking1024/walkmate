//
//  AcceleratePreprocessor.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import Accelerate
import CoreML
import CoreVideo
import Foundation

// MARK: - 错误定义

/// 图像预处理异常枚举
public enum PreprocessingError: Error, LocalizedError {
    /// 无法锁定 PixelBuffer 内存
    case lockBaseAddressFailed
    /// vImage 缩放失败
    case scalingFailed(vImage_Error)
    /// 创建 MLMultiArray 失败
    case multiArrayCreationFailed
    
    /// 错误中文描述
    public var errorDescription: String? {
        switch self {
        case .lockBaseAddressFailed:
            return "无法锁定 CVPixelBuffer 内存基地址"
        case .scalingFailed(let err):
            return "vImage 图像硬件缩放失败，错误码: \(err)"
        case .multiArrayCreationFailed:
            return "创建 CoreML 输入张量 MLMultiArray 失败"
        }
    }
}

// MARK: - Accelerate 硬件向量化预处理器

/// 利用 Apple Accelerate (vImage + vDSP) 硬件向量化进行极速图像缩放与归一化
public final class AcceleratePreprocessor: Sendable {
    
    /// 目标模型输入宽度
    public static let targetWidth = 512
    /// 目标模型输入高度
    public static let targetHeight = 256
    /// 目标通道数 (RGB)
    public static let targetChannels = 3
    
    /// 初始化预处理器
    public init() {}
    
    // MARK: - 核心预处理流程
    
    /// 将原生全景帧 (1080P 或任意分辨率) 缩放并归一化为模型所需的 [1, 3, 256, 512] 浮点张量
    /// - Parameter pixelBuffer: 原始输入视频帧
    /// - Returns: 符合 CoreML 格式的输入张量 (数值范围 [0.0, 1.0])
    public func preprocess(pixelBuffer: CVPixelBuffer) throws -> MLMultiArray {
        // 1. 锁定输入 PixelBuffer 内存
        let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        guard lockResult == kCVReturnSuccess else {
            Log.error("无法锁定 CVPixelBuffer 内存，错误码: \(lockResult)", category: .perception)
            throw PreprocessingError.lockBaseAddressFailed
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let srcWidth = CVPixelBufferGetWidth(pixelBuffer)
        let srcHeight = CVPixelBufferGetHeight(pixelBuffer)
        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let srcBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw PreprocessingError.lockBaseAddressFailed
        }
        
        var srcBuffer = vImage_Buffer(
            data: srcBaseAddress,
            height: vImagePixelCount(srcHeight),
            width: vImagePixelCount(srcWidth),
            rowBytes: srcBytesPerRow
        )
        
        // 2. 准备 256x512 目标缩放缓冲区 (4 字节 BGRA 或 RGBA)
        let destWidth = Self.targetWidth
        let destHeight = Self.targetHeight
        let destBytesPerRow = destWidth * 4
        let destData = UnsafeMutablePointer<UInt8>.allocate(capacity: destHeight * destBytesPerRow)
        defer { destData.deallocate() }
        
        var destBuffer = vImage_Buffer(
            data: destData,
            height: vImagePixelCount(destHeight),
            width: vImagePixelCount(destWidth),
            rowBytes: destBytesPerRow
        )
        
        // 3. 执行 vImage 硬件极速双线性缩放 (耗时约 2~3ms)
        let scaleError = vImageScale_ARGB8888(&srcBuffer, &destBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
        guard scaleError == kvImageNoError else {
            Log.error("vImage 缩放失败: \(scaleError)", category: .perception)
            throw PreprocessingError.scalingFailed(scaleError)
        }
        
        // 4. 创建 CoreML 输出张量 [1, 3, 256, 512]
        let shape: [NSNumber] = [
            1,
            NSNumber(value: Self.targetChannels),
            NSNumber(value: destHeight),
            NSNumber(value: destWidth)
        ]
        
        guard let multiArray = try? MLMultiArray(shape: shape, dataType: .float32) else {
            Log.error("无法创建 [1, 3, 256, 512] 的 MLMultiArray", category: .perception)
            throw PreprocessingError.multiArrayCreationFailed
        }
        
        // 5. 使用 vImageConvert_ARGB8888toPlanar8 硬件分离四通道至平面缓冲区
        let planeSize = destHeight * destWidth
        let planarBlock = UnsafeMutablePointer<UInt8>.allocate(capacity: 4 * planeSize)
        defer { planarBlock.deallocate() }
        
        let p0 = planarBlock
        let p1 = planarBlock.advanced(by: planeSize)
        let p2 = planarBlock.advanced(by: 2 * planeSize)
        let p3 = planarBlock.advanced(by: 3 * planeSize)
        
        var buf0 = vImage_Buffer(data: p0, height: vImagePixelCount(destHeight), width: vImagePixelCount(destWidth), rowBytes: destWidth)
        var buf1 = vImage_Buffer(data: p1, height: vImagePixelCount(destHeight), width: vImagePixelCount(destWidth), rowBytes: destWidth)
        var buf2 = vImage_Buffer(data: p2, height: vImagePixelCount(destHeight), width: vImagePixelCount(destWidth), rowBytes: destWidth)
        var buf3 = vImage_Buffer(data: p3, height: vImagePixelCount(destHeight), width: vImagePixelCount(destWidth), rowBytes: destWidth)
        
        let convertErr = vImageConvert_ARGB8888toPlanar8(&destBuffer, &buf0, &buf1, &buf2, &buf3, vImage_Flags(kvImageNoFlags))
        guard convertErr == kvImageNoError else {
            Log.error("vImage 通道分离失败: \(convertErr)", category: .perception)
            throw PreprocessingError.scalingFailed(convertErr)
        }
        
        // 6. 根据输入格式 (BGRA vs RGBA) 映射 R, G, B 通道
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let isBGRA = (pixelFormat == kCVPixelFormatType_32BGRA)
        
        let rSource = isBGRA ? p2 : p0
        let gSource = p1
        let bSource = isBGRA ? p0 : p2
        
        // 7. 使用 vDSP 芯片级硬件向量指令执行 UInt8 转 Float32 及归一化 (x * (1/255.0))
        let outPtr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: 3 * planeSize)
        let redPlane = outPtr
        let greenPlane = outPtr.advanced(by: planeSize)
        let bluePlane = outPtr.advanced(by: 2 * planeSize)
        
        let length = vDSP_Length(planeSize)
        var scale: Float = 1.0 / 255.0
        
        // 红色平面
        vDSP_vfltu8(rSource, 1, redPlane, 1, length)
        vDSP_vsmul(redPlane, 1, &scale, redPlane, 1, length)
        
        // 绿色平面
        vDSP_vfltu8(gSource, 1, greenPlane, 1, length)
        vDSP_vsmul(greenPlane, 1, &scale, greenPlane, 1, length)
        
        // 蓝色平面
        vDSP_vfltu8(bSource, 1, bluePlane, 1, length)
        vDSP_vsmul(bluePlane, 1, &scale, bluePlane, 1, length)
        
        return multiArray
    }
}
