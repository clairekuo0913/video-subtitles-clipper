import CoreGraphics
import Foundation

/// 與 AppKit 無關的 sRGB 色彩（分量 0–1）。
public struct RGBAColor: Codable, Equatable {
    public var r: Double, g: Double, b: Double, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public static let red = RGBAColor(r: 1, g: 0, b: 0)
    public static let blue = RGBAColor(r: 0, g: 0, b: 1)
    public static let yellow = RGBAColor(r: 1, g: 1, b: 0)
    public static let white = RGBAColor(r: 1, g: 1, b: 1)
    public static let black = RGBAColor(r: 0, g: 0, b: 0)

    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// 邊框（粗細相對長圖寬度）。
public struct BorderStyle: Codable, Equatable {
    public var color: RGBAColor
    public var width: Double
    public init(color: RGBAColor, width: Double) { self.color = color; self.width = width }
}

/// 文字框樣式。`fillColor == nil` 為無底色；`border == nil` 為無邊框；`fontSize` 相對長圖寬度。
public struct TextStyle: Codable, Equatable {
    public var textColor: RGBAColor
    public var fillColor: RGBAColor?
    public var fontSize: Double
    public var bold: Bool
    public var border: BorderStyle?

    public init(textColor: RGBAColor, fillColor: RGBAColor?, fontSize: Double, bold: Bool, border: BorderStyle?) {
        self.textColor = textColor; self.fillColor = fillColor
        self.fontSize = fontSize; self.bold = bold; self.border = border
    }

    public static let `default` = TextStyle(textColor: .red, fillColor: nil, fontSize: 0.04, bold: false, border: nil)
}

/// 矩形與箭頭樣式；`width` 相對長圖寬度。
public struct LineStyle: Codable, Equatable {
    public var color: RGBAColor
    public var width: Double
    public init(color: RGBAColor, width: Double) { self.color = color; self.width = width }

    public static let `default` = LineStyle(color: .red, width: 0.004)
}

/// 「上次選用樣式」的 UserDefaults 讀寫；資料缺漏或損毀時回傳預設值。
public struct AnnotationStyleStore {
    static let textKey = "annotationTextStyle"
    static let rectangleKey = "annotationRectangleStyle"
    static let arrowKey = "annotationArrowStyle"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var textStyle: TextStyle {
        get { read(Self.textKey) ?? .default }
        nonmutating set { write(newValue, Self.textKey) }
    }
    public var rectangleStyle: LineStyle {
        get { read(Self.rectangleKey) ?? .default }
        nonmutating set { write(newValue, Self.rectangleKey) }
    }
    public var arrowStyle: LineStyle {
        get { read(Self.arrowKey) ?? .default }
        nonmutating set { write(newValue, Self.arrowKey) }
    }

    private func read<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
    private func write<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
