import Foundation

/// 設定的 UserDefaults 讀寫包裝（紅框範圍、輸出倍率）。
public struct SettingsStore {
    static let bandTopKey = "cropBandTop"
    static let bandBottomKey = "cropBandBottom"
    static let outputScaleKey = "outputScalePercent"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// 未儲存或值無效時回傳 `CropBand.default`；其餘經 CropBand 夾限。
    public var band: CropBand {
        get {
            guard let t = defaults.object(forKey: Self.bandTopKey) as? Double,
                  let b = defaults.object(forKey: Self.bandBottomKey) as? Double,
                  t.isFinite, b.isFinite else { return .default }
            return CropBand(top: t, bottom: b)
        }
        nonmutating set {
            defaults.set(newValue.top, forKey: Self.bandTopKey)
            defaults.set(newValue.bottom, forKey: Self.bandBottomKey)
        }
    }

    public var outputScale: OutputScale {
        get {
            (defaults.object(forKey: Self.outputScaleKey) as? Int).flatMap(OutputScale.init(rawValue:)) ?? .default
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.outputScaleKey) }
    }
}

/// 檢視縮放（只影響顯示）。
public enum ViewZoom {
    public static let min = 0.25
    public static let max = 4.0
    public static let `default` = 1.0
    public static let step = 1.25

    public static func clamp(_ z: Double) -> Double {
        guard z.isFinite else { return `default` }
        return Swift.min(Swift.max(z, min), max)
    }
    public static func zoomedIn(_ z: Double) -> Double { clamp(z * step) }
    public static func zoomedOut(_ z: Double) -> Double { clamp(z / step) }
}
