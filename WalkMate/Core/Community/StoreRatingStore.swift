import Foundation
import Observation

/// 一条店铺无障碍评分
struct StoreRating: Codable, Identifiable {
    var id = UUID()
    let storeName: String
    /// 1 到 5 星
    let score: Int
    let tags: [String]
    let comment: String
    let createdAt: Date
}

/// 店铺评分的本地存储。
///
/// 首期没有后端，评分存在本机；店铺卡片上的分数与人数由设计稿里的基线数据
/// 与本机评分合并计算，提交后能立刻看到变化。
@MainActor
@Observable
final class StoreRatingStore {

    static let shared = StoreRatingStore()

    private(set) var ratings: [StoreRating] = []
    private let storageKey = "walkmate.storeRatings"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([StoreRating].self, from: data) {
            ratings = saved
        }
    }

    func add(_ rating: StoreRating) {
        ratings.append(rating)
        if let data = try? JSONEncoder().encode(ratings) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        Log.info("已保存店铺评分：\(rating.storeName) \(rating.score) 星，标签 \(rating.tags.count) 个", category: .ui)
    }

    /// 本机评分与基线人数、基线分数合并后的平均分
    func averageScore(for store: String, fallback: Double, fallbackCount: Int = 36) -> Double {
        let local = ratings.filter { $0.storeName == store }
        guard !local.isEmpty else { return fallback }
        let total = fallback * Double(fallbackCount) + Double(local.reduce(0) { $0 + $1.score })
        return total / Double(fallbackCount + local.count)
    }

    func visitorCount(for store: String, fallback: Int) -> Int {
        fallback + ratings.filter { $0.storeName == store }.count
    }

    /// 展示用标签：本机评分里提到最多的在前，不足四个用基线标签补齐
    func topTags(for store: String, fallback: [String]) -> [String] {
        var frequency: [String: Int] = [:]
        for rating in ratings where rating.storeName == store {
            for tag in rating.tags { frequency[tag, default: 0] += 1 }
        }
        let local = frequency.sorted { $0.value > $1.value }.map(\.key)
        var merged: [String] = []
        for tag in local + fallback where !merged.contains(tag) {
            merged.append(tag)
            if merged.count == 4 { break }
        }
        return merged
    }
}
