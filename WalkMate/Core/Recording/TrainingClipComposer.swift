import AVFoundation
import CoreGraphics
import CoreText
import Foundation

/// 训练短片合成器：把关键帧、字幕与背景音乐合成为一段可分享的竖屏视频。
///
/// 实现取舍：字幕不走 `AVVideoCompositionCoreAnimationTool`，
/// 而是与画面一起逐帧绘制进 `CGContext`。前者依赖图层树与时间轴的隐式约定，
/// 调试困难且难以离线验证；后者是纯粹的像素输出，结果可预测、可在命令行下直接跑通。
enum TrainingClipComposer {

    /// 输出帧率。24 帧足够承载静帧缓慢平移的观感，同时把绘制开销压到最低。
    static let frameRate: Int32 = 24
    /// 竖屏输出尺寸，对齐主流短视频平台
    static let renderSize = CGSize(width: 1080, height: 1920)
    /// 从全景图纵向截取的比例。取中间 62% 的水平带，避开等矩形投影上下两极的拉伸畸变。
    static let verticalFieldRatio: CGFloat = 0.62

    /// 一个画面片段：一张关键帧及其占用的时长
    struct FrameSegment {
        let imageURL: URL
        let durationMs: Int
    }

    /// 合成短片。
    ///
    /// - Parameters:
    ///   - segments: 按时间顺序排列的关键帧片段
    ///   - cues: 已排布好的字幕时间轴
    ///   - musicURL: 背景音乐，传 nil 则输出无声视频
    ///   - outputURL: 输出文件路径，若已存在会被覆盖
    static func compose(
        segments: [FrameSegment],
        cues: [SubtitleCue],
        musicURL: URL?,
        outputURL: URL
    ) async throws {
        guard !segments.isEmpty else { throw ClipComposeError.emptyInput }

        // 先渲染出无声视频，再按需混入音乐，两步分离便于定位问题
        let silentURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("silent_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: silentURL) }

        try await renderVideo(segments: segments, cues: cues, to: silentURL)

        guard let musicURL else {
            try replaceItem(at: outputURL, with: silentURL)
            return
        }
        try await mux(videoURL: silentURL, musicURL: musicURL, to: outputURL)
    }

    // MARK: - 视频渲染

    /// 逐帧绘制画面与字幕，写出无声 MP4
    private static func renderVideo(segments: [FrameSegment], cues: [SubtitleCue], to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(renderSize.width),
                kCVPixelBufferHeightKey as String: Int(renderSize.height),
            ]
        )

        guard writer.canAdd(input) else { throw ClipComposeError.writerSetupFailed }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ClipComposeError.writerSetupFailed }
        writer.startSession(atSourceTime: .zero)

        // 关键帧一次性解码后复用，避免每帧重复读盘
        let images = try segments.map { try loadImage(at: $0.imageURL) }
        let totalMs = segments.reduce(0) { $0 + $1.durationMs }
        let totalFrames = max(1, totalMs * Int(frameRate) / 1_000)

        for frameIndex in 0..<totalFrames {
            let timeMs = frameIndex * 1_000 / Int(frameRate)
            guard let position = segmentPosition(forTimeMs: timeMs, segments: segments) else { break }

            let buffer = try makePixelBuffer()
            draw(
                image: images[position.index],
                progress: position.progress,
                subtitle: activeSubtitle(atTimeMs: timeMs, cues: cues),
                into: buffer
            )

            // 写入端有背压，必须等其就绪后再投递，否则缓冲区会被丢弃
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: frameRate)
            guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? ClipComposeError.frameAppendFailed(frameIndex)
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? ClipComposeError.writerSetupFailed }
    }

    /// 定位某一时刻落在第几个片段，以及在该片段内的进度（0 到 1）
    private static func segmentPosition(forTimeMs timeMs: Int, segments: [FrameSegment]) -> (index: Int, progress: Double)? {
        var elapsed = 0
        for (index, segment) in segments.enumerated() {
            if timeMs < elapsed + segment.durationMs {
                let progress = Double(timeMs - elapsed) / Double(max(1, segment.durationMs))
                return (index, progress)
            }
            elapsed += segment.durationMs
        }
        return nil
    }

    /// 取出该时刻应当显示的字幕
    private static func activeSubtitle(atTimeMs timeMs: Int, cues: [SubtitleCue]) -> String? {
        cues.first { timeMs >= $0.startMs && timeMs < $0.endMs }?.text
    }

    // MARK: - 单帧绘制

    /// 把关键帧按进度平移裁切后绘制，再在底部叠加字幕。
    ///
    /// 全景图是 2 比 1 的扁长画幅，直接塞进竖屏会严重变形，
    /// 因此裁出一个竖向窗口并随时间缓慢横移，既规避变形又让静帧有运镜感。
    private static func draw(image: CGImage, progress: Double, subtitle: String?, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(renderSize.width),
            height: Int(renderSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return }

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: renderSize))

        // 等矩形全景的上下两极被严重拉伸，只取中间一条水平带，
        // 既避开畸变区，也让横向可推移的范围更长、运镜更明显
        let bandHeight = CGFloat(image.height) * verticalFieldRatio
        let bandOriginY = (CGFloat(image.height) - bandHeight) / 2

        // 裁切窗口的宽度由输出宽高比决定，横向位置随进度从左向右缓慢推移
        let windowWidth = bandHeight * renderSize.width / renderSize.height
        let travel = max(0, CGFloat(image.width) - windowWidth)
        let originX = travel * CGFloat(progress)
        let cropRect = CGRect(x: originX, y: bandOriginY, width: windowWidth, height: bandHeight)

        if let cropped = image.cropping(to: cropRect) {
            context.draw(cropped, in: CGRect(origin: .zero, size: renderSize))
        }

        if let subtitle { drawSubtitle(subtitle, in: context) }
    }

    /// 在画面底部绘制字幕。加一条半透明衬底，保证浅色画面上文字依然清晰。
    private static func drawSubtitle(_ text: String, in context: CGContext) {
        let fontSize: CGFloat = 52
        let font = CTFontCreateWithName("PingFangSC-Semibold" as CFString, fontSize, nil)
        // 使用 CoreText 原生属性键而非 UIKit/AppKit 的便捷常量，
        // 使本文件在 iOS 与 macOS 下都能编译，便于脱离模拟器做命令行验证
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)

        // 按可用宽度排版，得到实际占用的高度后再反推衬底与起绘位置
        let horizontalInset: CGFloat = 72
        let maxWidth = renderSize.width - horizontalInset * 2
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil
        )

        let bottomInset: CGFloat = 200
        let textRect = CGRect(
            x: horizontalInset,
            y: bottomInset,
            width: maxWidth,
            height: ceil(suggested.height)
        )

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
        context.fill(textRect.insetBy(dx: -24, dy: -20))

        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
    }

    // MARK: - 音轨混合

    /// 把背景音乐混入无声视频。音乐短于视频时保持原长，长于视频时按视频时长截断。
    private static func mux(videoURL: URL, musicURL: URL, to outputURL: URL) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let musicAsset = AVURLAsset(url: musicURL)

        let videoDuration = try await videoAsset.load(.duration)

        guard
            let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
            let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ClipComposeError.writerSetupFailed }
        try compositionVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)

        if let musicTrack = try await musicAsset.loadTracks(withMediaType: .audio).first,
           let compositionAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let musicDuration = try await musicAsset.load(.duration)
            let usable = CMTimeMinimum(musicDuration, videoDuration)
            try compositionAudio.insertTimeRange(CMTimeRange(start: .zero, duration: usable), of: musicTrack, at: .zero)
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ClipComposeError.exportSetupFailed
        }
        try? FileManager.default.removeItem(at: outputURL)
        export.outputURL = outputURL
        export.outputFileType = .mp4
        await export.export()

        if export.status != .completed { throw export.error ?? ClipComposeError.exportSetupFailed }
    }

    // MARK: - 辅助

    private static func loadImage(at url: URL) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ClipComposeError.imageLoadFailed(url) }
        return image
    }

    private static func makePixelBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(renderSize.width), Int(renderSize.height),
            kCVPixelFormatType_32ARGB,
            [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { throw ClipComposeError.pixelBufferCreateFailed }
        return buffer
    }

    private static func replaceItem(at destination: URL, with source: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }
}

/// 短片合成过程中的可预期错误
enum ClipComposeError: Error {
    case emptyInput
    case imageLoadFailed(URL)
    case pixelBufferCreateFailed
    case writerSetupFailed
    case frameAppendFailed(Int)
    case exportSetupFailed
}
