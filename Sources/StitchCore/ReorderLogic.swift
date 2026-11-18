import Foundation

/// 垂直拖曳排序的純邏輯（不依賴 AppKit/SwiftUI）。
public enum ReorderLogic {
    public struct Drop: Equatable {
        public let isValid: Bool
        /// 傳給 `ComposeList.move(from:to:)` 的移動後最終索引。
        public let to: Int
        public init(isValid: Bool, to: Int) { self.isValid = isValid; self.to = to }
    }

    public static let edgeZone: Double = 60
    /// 最大捲動速度（pt/秒）。
    public static let maxScrollSpeed: Double = 1200

    /// 游標 y（內容座標）→ 插入索引 0...count。落在項目上半部插其前，下半部插其後。
    public static func insertionIndex(forY y: Double, rowHeights: [Double]) -> Int {
        var top = 0.0
        for (i, h) in rowHeights.enumerated() {
            if y < top + h / 2 { return i }
            top += h
        }
        return rowHeights.count
    }

    /// 插入索引（移除前的間隙位置）+ 來源索引 → 合法性與最終索引。
    public static func resolveDrop(insertion: Int, from: Int, kinds: [ItemKind]) -> Drop {
        guard kinds.indices.contains(from) else { return Drop(isValid: false, to: from) }
        let ins = min(max(insertion, 0), kinds.count)
        let to = from < ins ? ins - 1 : ins
        var reordered = kinds
        let moved = reordered.remove(at: from)
        reordered.insert(moved, at: to)
        return Drop(isValid: reordered[0] == .frame, to: to)
    }

    /// 游標相對可視區上緣的 y（0 = 上緣、viewportHeight = 下緣）→ 捲動速度（pt/秒）。
    /// 上緣為負、下緣為正；邊緣區內越近越快，上限 `maxScrollSpeed`，離開邊緣區為 0。
    public static func edgeScrollSpeed(cursorY: Double, viewportHeight: Double) -> Double {
        let zone = min(edgeZone, viewportHeight / 2)
        guard zone > 0 else { return 0 }
        let intoTop = (zone - cursorY) / zone
        if intoTop > 0 { return -maxScrollSpeed * min(intoTop, 1) }
        let intoBottom = (cursorY - (viewportHeight - zone)) / zone
        if intoBottom > 0 { return maxScrollSpeed * min(intoBottom, 1) }
        return 0
    }
}
