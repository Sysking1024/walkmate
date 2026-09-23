import AVFoundation
import UIKit

/// 把屏幕上那块拼好的全景预览录成短视频。
///
/// 相机 SDK 只把拼接结果画在预览视图里，不吐拼接后的帧；解码回调给的是未拼接的双鱼眼原图。
/// 与其自己做鱼眼拼接，不如直接把预览视图逐帧截下来：画面是拼好、防抖过的，和使用者看到的一致。
/// 12 帧每秒足够表现行走中的动态，又不至于拖慢主线程。
@MainActor
final class ClipRecorder {

    private(set) var isRecording = false
    /// 开始录制时的墙钟毫秒，供时刻按时间切段
    private(set) var startedAtMs = 0

    private let framesPerSecond = 12
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var timer: Timer?
    private var startTime: CFTimeInterval = 0
    private var frameCount = 0
    private weak var view: UIView?
    private var outputURL: URL?

    func start(capturing view: UIView, to url: URL) {
        guard !isRecording, view.bounds.width > 0, view.bounds.height > 0 else { return }
        // 按 2 倍像素录，宽高取偶数，H.264 要求
        let width = Int(view.bounds.width * 2) / 2 * 2
        let height = Int(view.bounds.height * 2) / 2 * 2
        try? FileManager.default.removeItem(at: url)
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
            ])
            input.expectsMediaDataInRealTime = true
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? ClipComposeError.writerSetupFailed }
            writer.startSession(atSourceTime: .zero)
            self.writer = writer; self.input = input; self.adaptor = adaptor
        } catch {
            Log.error("录制预览失败：\(error)", category: .recording)
            return
        }
        self.view = view
        outputURL = url
        startTime = CACurrentMediaTime()
        startedAtMs = Int(Date().timeIntervalSince1970 * 1_000)
        frameCount = 0
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(framesPerSecond), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureFrame() }
        }
        Log.info("开始录制预览画面 \(width)x\(height)", category: .recording)
    }

    /// 停止并写完文件；返回文件与时长
    func stop() async -> (url: URL, durationMs: Int)? {
        guard isRecording, let writer, let input, let outputURL else { return nil }
        timer?.invalidate(); timer = nil
        isRecording = false
        let durationMs = Int((CACurrentMediaTime() - startTime) * 1_000)
        input.markAsFinished()
        await writer.finishWriting()
        self.writer = nil; self.input = nil; adaptor = nil
        guard writer.status == .completed, frameCount > 0 else {
            Log.warning("预览录制没有产出：\(writer.error.map { "\($0)" } ?? "无帧")", category: .recording)
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
        Log.info("预览录制完成：\(frameCount) 帧，\(durationMs) 毫秒", category: .recording)
        return (outputURL, durationMs)
    }

    private func captureFrame() {
        guard isRecording, let view, let input, let adaptor, input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)

        // 截取当前已经显示在屏幕上的那一帧（不等下一次刷新，避免阻塞渲染）
        let renderer = UIGraphicsImageRenderer(size: view.bounds.size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 2; return f }())
        let image = renderer.image { _ in view.drawHierarchy(in: view.bounds, afterScreenUpdates: false) }
        guard let cgImage = image.cgImage else { return }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let time = CMTime(seconds: CACurrentMediaTime() - startTime, preferredTimescale: 600)
        if adaptor.append(buffer, withPresentationTime: time) { frameCount += 1 }
    }
}
