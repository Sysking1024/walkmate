import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import VideoToolbox

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

    /// 一个画面片段：画面来源、在成片中占用的时长，以及取景方向。
    struct FrameSegment {
        /// 画面来源
        enum Source {
            /// 一张静态全景图
            case image(URL)
            /// 一段全景视频的某个区间（秒）。区间会被匀速拉伸或压缩到片段时长，
            /// 素材帧率足够高时即为平滑的慢动作。
            case video(URL, start: Double, end: Double)
        }

        let source: Source
        let durationMs: Int
        /// 取景窗口中心在全景图横向上的位置（0 到 1，0.5 为相机正前方），
        /// 片段播放过程中从下界平移到上界。为 nil 时横扫整幅画面。
        ///
        /// 需要这个参数的原因：手持拍摄时持相机的人本身处在画面正中，
        /// 剪片时要让取景避开他，只拍周围的环境。
        let viewRange: ClosedRange<CGFloat>?

        init(source: Source, durationMs: Int, viewRange: ClosedRange<CGFloat>? = nil) {
            self.source = source
            self.durationMs = durationMs
            self.viewRange = viewRange
        }

        /// 静帧片段的便捷构造，横扫整幅画面
        init(imageURL: URL, durationMs: Int) {
            self.init(source: .image(imageURL), durationMs: durationMs)
        }
    }

    /// 一段配音：音频文件及其在成片时间轴上的起点
    struct SpeechTrack {
        let audioURL: URL
        let startMs: Int
    }

    /// 背景音乐相对语音的音量。语音是主体，音乐只做衬底，压到两成避免盖住朗读。
    static let musicVolume: Float = 0.2
    /// 背景音乐在片尾的淡出时长（秒）
    static let musicFadeOutSeconds: Double = 2

    /// 合成短片。
    ///
    /// - Parameters:
    ///   - segments: 按时间顺序排列的关键帧片段
    ///   - cues: 已排布好的字幕时间轴
    ///   - speeches: 场景描述的配音轨。成片必须带朗读，否则视障受众拿到的等于空白
    ///   - musicURL: 背景音乐，传 nil 则只有语音
    ///   - outputURL: 输出文件路径，若已存在会被覆盖
    static func compose(
        segments: [FrameSegment],
        cues: [SubtitleCue],
        speeches: [SpeechTrack],
        musicURL: URL?,
        outputURL: URL
    ) async throws {
        guard !segments.isEmpty else { throw ClipComposeError.emptyInput }

        // 先渲染出无声视频，再混入音轨，两步分离便于定位问题
        let silentURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("silent_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: silentURL) }

        try await renderVideo(segments: segments, cues: cues, to: silentURL)

        guard !speeches.isEmpty || musicURL != nil else {
            try replaceItem(at: outputURL, with: silentURL)
            return
        }
        try await mux(videoURL: silentURL, speeches: speeches, musicURL: musicURL, to: outputURL)
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

        // 静帧一次性解码后复用；视频片段按需顺序解码，不整段读入内存
        var providers: [FrameProvider] = []
        for segment in segments {
            providers.append(try await makeFrameProvider(for: segment))
        }
        let totalMs = segments.reduce(0) { $0 + $1.durationMs }
        let totalFrames = max(1, totalMs * Int(frameRate) / 1_000)

        for frameIndex in 0..<totalFrames {
            let timeMs = frameIndex * 1_000 / Int(frameRate)
            guard let position = segmentPosition(forTimeMs: timeMs, segments: segments) else { break }

            let segment = segments[position.index]
            guard let image = try providers[position.index].image(atProgress: position.progress) else { continue }

            let buffer = try makePixelBuffer()
            draw(
                image: image,
                viewCenter: viewCenter(for: segment, progress: position.progress),
                sweepProgress: position.progress,
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

    /// 该时刻取景窗口的中心位置。未指定取景范围时返回 nil，表示横扫整幅画面。
    private static func viewCenter(for segment: FrameSegment, progress: Double) -> CGFloat? {
        guard let range = segment.viewRange else { return nil }
        return range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(progress)
    }

    /// 取出该时刻应当显示的字幕
    private static func activeSubtitle(atTimeMs timeMs: Int, cues: [SubtitleCue]) -> String? {
        cues.first { timeMs >= $0.startMs && timeMs < $0.endMs }?.text
    }

    // MARK: - 单帧绘制

    /// 从全景图中裁出竖向取景窗口绘制，再在底部叠加字幕。
    ///
    /// 全景图是 2 比 1 的扁长画幅，直接塞进竖屏会严重变形，
    /// 因此裁出一个竖向窗口，随时间缓慢横移，既规避变形又让画面有运镜感。
    ///
    /// - Parameter viewCenter: 窗口中心的横向位置（0 到 1）。为 nil 时由 `sweepProgress` 决定，横扫整幅画面。
    private static func draw(image: CGImage, viewCenter: CGFloat?, sweepProgress: Double = 0, subtitle: String?, into buffer: CVPixelBuffer) {
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

        // 裁切窗口的宽度由输出宽高比决定；指定了中心时围绕中心取景，否则按进度横扫
        let windowWidth = bandHeight * renderSize.width / renderSize.height
        let travel = max(0, CGFloat(image.width) - windowWidth)
        let originX: CGFloat
        if let viewCenter {
            originX = min(max(viewCenter * CGFloat(image.width) - windowWidth / 2, 0), travel)
        } else {
            originX = travel * CGFloat(sweepProgress)
        }
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

    /// 把配音与背景音乐混入无声视频。
    ///
    /// 语音各段按各自起点插入同一条音轨；音乐单独占一条轨并通过 `AVMutableAudioMix`
    /// 压低音量，确保朗读始终清晰。音乐短于视频时保持原长，不做循环。
    private static func mux(videoURL: URL, speeches: [SpeechTrack], musicURL: URL?, to outputURL: URL) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let videoDuration = try await videoAsset.load(.duration)

        guard
            let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
            let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ClipComposeError.writerSetupFailed }
        try compositionVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)

        // 配音轨：各段语音按起点依次插入同一条轨道
        if !speeches.isEmpty,
           let speechTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            for speech in speeches.sorted(by: { $0.startMs < $1.startMs }) {
                let asset = AVURLAsset(url: speech.audioURL)
                guard let source = try await asset.loadTracks(withMediaType: .audio).first else { continue }
                let duration = try await asset.load(.duration)
                let startTime = CMTime(value: CMTimeValue(speech.startMs), timescale: 1_000)
                // 超出视频末尾的片段直接跳过，避免成片被音轨拉长
                guard startTime < videoDuration else { continue }
                let usable = CMTimeMinimum(duration, CMTimeSubtract(videoDuration, startTime))
                try speechTrack.insertTimeRange(CMTimeRange(start: .zero, duration: usable), of: source, at: startTime)
            }
        }

        // 音乐轨：单独一条，便于用 audioMix 单独压低音量
        var audioMix: AVMutableAudioMix?
        if let musicURL,
           let musicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let musicAsset = AVURLAsset(url: musicURL)
            if let source = try await musicAsset.loadTracks(withMediaType: .audio).first {
                let musicDuration = try await musicAsset.load(.duration)
                let usable = CMTimeMinimum(musicDuration, videoDuration)
                try musicTrack.insertTimeRange(CMTimeRange(start: .zero, duration: usable), of: source, at: .zero)

                let parameters = AVMutableAudioMixInputParameters(track: musicTrack)
                parameters.setVolume(musicVolume, at: .zero)
                // 音乐通常比成片长，在片尾截断会像被突然掐掉，收尾前留出一段淡出
                let fadeDuration = CMTimeMinimum(CMTime(seconds: musicFadeOutSeconds, preferredTimescale: 600), usable)
                parameters.setVolumeRamp(
                    fromStartVolume: musicVolume,
                    toEndVolume: 0,
                    timeRange: CMTimeRange(start: CMTimeSubtract(usable, fadeDuration), duration: fadeDuration)
                )
                let mix = AVMutableAudioMix()
                mix.inputParameters = [parameters]
                audioMix = mix
            }
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ClipComposeError.exportSetupFailed
        }
        try? FileManager.default.removeItem(at: outputURL)
        export.outputURL = outputURL
        export.outputFileType = .mp4
        export.audioMix = audioMix
        await export.export()

        if export.status != .completed { throw export.error ?? ClipComposeError.exportSetupFailed }
    }

    // MARK: - 辅助

    /// 为片段准备画面提供者
    private static func makeFrameProvider(for segment: FrameSegment) async throws -> FrameProvider {
        switch segment.source {
        case .image(let url):
            return .still(try loadImage(at: url))
        case .video(let url, let start, let end):
            return .video(try await VideoFrameReader(url: url, start: start, end: end))
        }
    }

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

/// 按片段进度提供画面：静帧始终返回同一张，视频按进度映射到素材时间取帧
private enum FrameProvider {
    case still(CGImage)
    case video(VideoFrameReader)

    func image(atProgress progress: Double) throws -> CGImage? {
        switch self {
        case .still(let image): return image
        case .video(let reader): return try reader.image(atProgress: progress)
        }
    }
}

/// 顺序解码全景视频的一个区间，按进度取帧。
///
/// 只支持时间单调前进的读取，这正是逐帧合成的访问方式；
/// 解码是流式的，任意时刻内存里只保留当前一帧。
private final class VideoFrameReader {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let start: Double
    private let end: Double

    /// 最近读到的一帧及其素材时间
    private var latestBuffer: CVPixelBuffer?
    private var latestTime = -Double.infinity
    /// 已转换好的画面，同一帧被多次取用时直接复用
    private var cachedImage: CGImage?
    private var cachedTime = -Double.infinity
    private var exhausted = false

    init(url: URL, start: Double, end: Double) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ClipComposeError.videoTrackMissing(url)
        }
        reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ClipComposeError.videoTrackMissing(url) }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ClipComposeError.videoTrackMissing(url) }
        self.start = start
        self.end = end
    }

    /// 取片段进度对应的那一帧：把进度映射到素材时间，读到第一个不早于它的帧为止
    func image(atProgress progress: Double) throws -> CGImage? {
        let target = start + (end - start) * progress

        while latestTime < target, !exhausted {
            guard let sample = output.copyNextSampleBuffer() else {
                // 读到区间末尾，此后一直沿用最后一帧
                exhausted = true
                break
            }
            if let buffer = CMSampleBufferGetImageBuffer(sample) {
                latestBuffer = buffer
                latestTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            }
        }

        if latestTime == cachedTime, let cachedImage { return cachedImage }
        guard let latestBuffer else { return nil }

        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(latestBuffer, options: nil, imageOut: &image)
        cachedImage = image
        cachedTime = latestTime
        return image
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
    /// 素材中找不到视频轨
    case videoTrackMissing(URL)
}
