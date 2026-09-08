import Foundation

enum FoodPresetOrdering {
    static func sortedByRecentUse(_ presets: [FoodPreset]) -> [FoodPreset] {
        presets.sorted { lhs, rhs in
            switch (lhs.lastUsedAt, rhs.lastUsedAt) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }
}
