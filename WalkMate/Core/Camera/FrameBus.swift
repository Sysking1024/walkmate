import Foundation

/// 全景帧总线：把相机管线的帧同时分发给多个消费者。
///
/// `CameraPipeline` 只有一个代理，由避障线的 `CameraViewModel` 持有；
/// 场景描述线同样需要实时帧，但不该去争这个代理，也不该在两条线之间引入直接依赖。
/// 由代理在收到帧时向总线投递一次，其他消费者各自订阅即可。
///
/// 投递发生在解码线程，订阅者的处理必须足够轻，耗时工作自行切换队列。
final class FrameBus {

    static let shared = FrameBus()

    private let lock = NSLock()
    private var subscribers: [UUID: (PanoramicFrame) -> Void] = [:]

    private init() {}

    /// 订阅帧，返回用于退订的标识
    @discardableResult
    func subscribe(_ handler: @escaping (PanoramicFrame) -> Void) -> UUID {
        let id = UUID()
        lock.lock(); subscribers[id] = handler; lock.unlock()
        return id
    }

    func unsubscribe(_ id: UUID) {
        lock.lock(); subscribers[id] = nil; lock.unlock()
    }

    /// 由相机管线的代理在每帧到达时调用
    func publish(_ frame: PanoramicFrame) {
        lock.lock(); let handlers = Array(subscribers.values); lock.unlock()
        for handler in handlers { handler(frame) }
    }
}
