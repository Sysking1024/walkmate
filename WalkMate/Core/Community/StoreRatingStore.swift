import Foundation
import Observation

/// 一条店铺无障碍评分
struct StoreRating: Codable, Identifiable {
    var id = UUID()
    let storeID: String
    /// 1 到 5 星
    let score: Int
    let tags: [String]
    let comment: String
    let createdAt: Date
}

/// 店铺与评分，离线优先。
///
/// 启动时先用内置种子数据填充，再向后端拉取；提交评分先在本地生效并入队，
/// 后端可达时同步，同步成功后用后端返回的汇总覆盖本地估算。
@MainActor
@Observable
final class StoreRatingStore {

    static let shared = StoreRatingStore()

    private(set) var stores: [StoreSummary] = SeedData.stores
    private(set) var pending: [StoreRating] = []
    private(set) var isSyncing = false

    private let pendingKey = "walkmate.pendingReviews"
    private let backend = BackendClient.shared

    private init() {
        if let data = UserDefaults.standard.data(forKey: pendingKey),
           let saved = try? JSONDecoder().decode([StoreRating].self, from: data) {
            pending = saved
        }
    }

    func store(id: String) -> StoreSummary? { stores.first { $0.id == id } }

    /// 拉取最新店铺数据，并把积压的评分补发
    func refresh() async {
        guard backend.isConfigured, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await flushPending()
        do {
            stores = try await backend.fetchStores()
            Log.info("已从后端拉取 \(stores.count) 家店铺", category: .general)
        } catch {
            Log.warning("拉取店铺失败，沿用本地数据：\(error)", category: .general)
        }
    }

    /// 提交评分：本地立即生效，随后尝试同步
    func submit(_ rating: StoreRating) async {
        applyLocally(rating)
        pending.append(rating)
        persistPending()
        Log.info("已记录评分：\(rating.storeID) \(rating.score) 星", category: .ui)
        await flushPending()
    }

    /// 用本地评分更新店铺概要，作为后端不可达时的估算
    private func applyLocally(_ rating: StoreRating) {
        guard let index = stores.firstIndex(where: { $0.id == rating.storeID }) else { return }
        var store = stores[index]
        let total = store.averageScore * Double(store.visitorCount) + Double(rating.score)
        store.visitorCount += 1
        store.averageScore = (total / Double(store.visitorCount) * 10).rounded() / 10
        var tags = rating.tags
        for tag in store.tags where !tags.contains(tag) { tags.append(tag) }
        store.tags = Array(tags.prefix(4))
        stores[index] = store
    }

    private func flushPending() async {
        guard backend.isConfigured else { return }
        for rating in pending {
            do {
                let summary = try await backend.submitReview(storeID: rating.storeID, review: rating)
                if let index = stores.firstIndex(where: { $0.id == summary.id }) { stores[index] = summary }
                pending.removeAll { $0.id == rating.id }
                persistPending()
            } catch {
                Log.warning("评分同步失败，保留待发：\(error)", category: .general)
                return
            }
        }
    }

    private func persistPending() {
        if let data = try? JSONEncoder().encode(pending) { UserDefaults.standard.set(data, forKey: pendingKey) }
    }
}
