import CoreGraphics
import Foundation

public enum ItemKind: Equatable {
    case frame
    case subtitle
}

public struct ComposeItem: Identifiable {
    public let id: UUID
    public let image: CGImage
    public var kind: ItemKind
    public var name: String

    public init(id: UUID = UUID(), image: CGImage, kind: ItemKind, name: String) {
        self.id = id
        self.image = image
        self.kind = kind
        self.name = name
    }
}

public enum ComposeError: Error, Equatable {
    /// 操作會使第一項成為純字幕。
    case firstItemMustBeFrame
    case itemNotFound
    case indexOutOfRange
}

/// 有序平面清單；每個 frame 開新一幕，其後連續的 subtitle 屬於該幕。
public struct ComposeList {
    public private(set) var items: [ComposeItem] = []

    public init() {}

    /// 空清單的首項為 frame，其餘為 subtitle。回傳加入的項目。
    @discardableResult
    public mutating func append(image: CGImage, name: String) -> ComposeItem {
        let item = ComposeItem(image: image,
                               kind: items.isEmpty ? .frame : .subtitle,
                               name: name)
        items.append(item)
        return item
    }

    public var scenes: [[ComposeItem]] {
        var result: [[ComposeItem]] = []
        for item in items {
            if item.kind == .frame || result.isEmpty {
                result.append([item])
            } else {
                result[result.count - 1].append(item)
            }
        }
        return result
    }

    public mutating func setKind(id: ComposeItem.ID, to kind: ItemKind) -> Result<Void, ComposeError> {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return .failure(.itemNotFound)
        }
        if index == 0 && kind == .subtitle { return .failure(.firstItemMustBeFrame) }
        items[index].kind = kind
        return .success(())
    }

    public mutating func toggleKind(id: ComposeItem.ID) -> Result<Void, ComposeError> {
        guard let item = items.first(where: { $0.id == id }) else { return .failure(.itemNotFound) }
        return setKind(id: id, to: item.kind == .frame ? .subtitle : .frame)
    }

    /// 移除項目；若新的第一項為 subtitle 則自動轉為 frame。
    public mutating func remove(id: ComposeItem.ID) -> Result<Void, ComposeError> {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return .failure(.itemNotFound)
        }
        items.remove(at: index)
        if !items.isEmpty { items[0].kind = .frame }
        return .success(())
    }

    public mutating func clear() {
        items.removeAll()
    }

    /// 將 `from` 位置的項目移動到「移動後」的索引 `to`（先移除再插入）。
    /// 若結果使第一項為 subtitle，則拒絕且順序不變。
    public mutating func move(from: Int, to: Int) -> Result<Void, ComposeError> {
        guard items.indices.contains(from), items.indices.contains(to) else {
            return .failure(.indexOutOfRange)
        }
        if from == to { return .success(()) }
        var reordered = items
        let moved = reordered.remove(at: from)
        reordered.insert(moved, at: to)
        if reordered[0].kind != .frame { return .failure(.firstItemMustBeFrame) }
        items = reordered
        return .success(())
    }
}

/// 自然排序（`shot 2` < `shot 10`）。
public func naturalSorted(_ names: [String]) -> [String] {
    names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

public func naturalSorted<T>(_ values: [T], by key: (T) -> String) -> [T] {
    values.sorted { key($0).localizedStandardCompare(key($1)) == .orderedAscending }
}
