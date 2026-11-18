import StitchCore
import SwiftUI

/// 標記模式的工具列與樣式面板。
struct AnnotationToolbar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("工具", selection: $model.tool) {
                Label("選取", systemImage: "cursorarrow").tag(AnnotationTool.select)
                Label("文字框", systemImage: "textformat").tag(AnnotationTool.text)
                Label("矩形", systemImage: "rectangle").tag(AnnotationTool.rectangle)
                Label("箭頭", systemImage: "arrow.up.right").tag(AnnotationTool.arrow)
                Label("馬賽克", systemImage: "checkerboard.rectangle").tag(AnnotationTool.mosaic)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .help("選取／文字框／矩形／箭頭／馬賽克（馬賽克不是加密）")
            .onChange(of: model.tool) { _, tool in
                if tool != .select { model.commitTextEdit(); model.annotationSelection = nil }
            }
            if let kind = model.styleKind { stylePanel(kind) }
        }
        .padding(.horizontal, 8).padding(.bottom, 6)
        .font(.caption)
    }

    @ViewBuilder
    private func stylePanel(_ kind: AnnotationKind) -> some View {
        if kind == .text {
            let s = model.currentTextStyle
            HStack(spacing: 10) {
                labeled("文字") { ColorRow(selected: s.textColor, allowNone: false) { c in
                    var n = s; n.textColor = c ?? s.textColor; model.setTextStyle(n)
                } }
                labeled("底色") { ColorRow(selected: s.fillColor, allowNone: true) { c in
                    var n = s; n.fillColor = c; model.setTextStyle(n)
                } }
            }
            HStack(spacing: 10) {
                Picker("字級", selection: Binding(get: { Self.nearest(Self.fontSizes.map(\.1), s.fontSize) },
                                                  set: { var n = s; n.fontSize = $0; model.setTextStyle(n) })) {
                    ForEach(Self.fontSizes, id: \.1) { Text($0.0).tag($0.1) }
                }
                .frame(width: 110)
                Toggle("粗體", isOn: Binding(get: { s.bold }, set: { var n = s; n.bold = $0; model.setTextStyle(n) }))
                Picker("邊框", selection: Binding(get: { s.border.map { Self.nearest(Self.widths.map(\.1), $0.width) } ?? 0 },
                                                  set: { w in
                    var n = s
                    n.border = w == 0 ? nil : BorderStyle(color: s.border?.color ?? .red, width: w)
                    model.setTextStyle(n)
                })) {
                    Text("無").tag(0.0)
                    ForEach(Self.widths, id: \.1) { Text($0.0).tag($0.1) }
                }
                .frame(width: 100)
                if let b = s.border {
                    ColorRow(selected: b.color, allowNone: false) { c in
                        var n = s; n.border = BorderStyle(color: c ?? b.color, width: b.width); model.setTextStyle(n)
                    }
                }
            }
        } else {
            let s = model.currentLineStyle
            HStack(spacing: 10) {
                labeled("顏色") { ColorRow(selected: s.color, allowNone: false) { c in
                    var n = s; n.color = c ?? s.color; model.setLineStyle(n)
                } }
                Picker("粗細", selection: Binding(get: { Self.nearest(Self.widths.map(\.1), s.width) },
                                                  set: { var n = s; n.width = $0; model.setLineStyle(n) })) {
                    ForEach(Self.widths, id: \.1) { Text($0.0).tag($0.1) }
                }
                .frame(width: 100)
            }
        }
    }

    private func labeled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 4) { Text(title); content() }
    }

    // 預設值（0.04／0.004）不在清單內時，取最接近的選項顯示。
    private static let fontSizes: [(String, Double)] = [("小", 0.025), ("中", 0.04), ("大", 0.06), ("特大", 0.09)]
    private static let widths: [(String, Double)] = [("細", 0.003), ("中", 0.006), ("粗", 0.012)]

    private static func nearest(_ options: [Double], _ v: Double) -> Double {
        options.min { abs($0 - v) < abs($1 - v) } ?? v
    }
}

/// 一排色塊（白、黑、紅、黃、藍）；`allowNone` 時多一個「無」。
private struct ColorRow: View {
    let selected: RGBAColor?
    let allowNone: Bool
    let onPick: (RGBAColor?) -> Void

    private static let palette: [RGBAColor] = [.white, .black, .red, .yellow, .blue]

    var body: some View {
        HStack(spacing: 4) {
            if allowNone {
                Button { onPick(nil) } label: {
                    Image(systemName: "nosign").frame(width: 16, height: 16)
                        .overlay(Circle().stroke(selected == nil ? Color.accentColor : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .help("無")
            }
            ForEach(Array(Self.palette.enumerated()), id: \.offset) { _, c in
                Button { onPick(c) } label: {
                    Circle().fill(Color(cgColor: c.cgColor))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.gray.opacity(0.6), lineWidth: 0.5))
                        .overlay(Circle().stroke(selected == c ? Color.accentColor : .clear, lineWidth: 2).padding(-2))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
