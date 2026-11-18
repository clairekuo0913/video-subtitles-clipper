import AppKit
import StitchCore
import SwiftUI

/// 疊在長圖列表上的標記層：與列表同一個縮放／捲動內容，大小 = 長圖（寬 = baseWidth×zoom）。
/// 排版模式只顯示標記；標記模式處理建立、選取、移動、縮放與文字輸入。座標一律以正規化座標與 canvasWidth 換算。
struct AnnotationLayer: View {
    @ObservedObject var model: AppModel
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat
    let focusList: () -> Void

    @StateObject private var preview = AnnotationPreview()
    @State private var active: Active?
    @State private var draft: Annotation?
    @FocusState private var editorFocused: Bool

    private enum Active {
        case idle
        case creating(tool: AnnotationTool, start: CGPoint)
        case moving(original: Annotation, start: CGPoint, checkpointed: Bool)
        case resizing(original: Annotation, handle: AnnotationHandle, checkpointed: Bool)
    }

    private var annotating: Bool { model.mode == .annotate }
    private var tolerance: CGFloat { 8 / max(canvasWidth, 1) }

    private struct PreviewKey: Equatable {
        let base: AnnotationPreview.BaseKey
        let annotations: [Annotation]
        let excluded: UUID?
    }

    private var excludedID: UUID? {
        if let te = model.textEdit, !te.isNew { return te.id }
        return nil
    }

    private var previewKey: PreviewKey {
        PreviewKey(base: .init(ids: model.list.items.map(\.id), kinds: model.list.items.map(\.kind), band: model.band),
                   annotations: model.annotations.annotations, excluded: excludedID)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let img = preview.overlay {
                Image(decorative: img, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: canvasWidth, height: canvasHeight)
                    .allowsHitTesting(false)
            }
            if annotating {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { v in doubleTap(v.location) })
                selectionOverlay.allowsHitTesting(false)
                draftOverlay.allowsHitTesting(false)
                textEditor
            }
        }
        .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
        .onChange(of: previewKey, initial: true) { _, _ in requestPreview() }
    }

    private func requestPreview() {
        let items = model.list.items
        let thumbs = items.compactMap { model.thumbnails[$0.id] }
        guard thumbs.count == items.count else { return }
        let marks = model.annotations.annotations.filter { $0.id != excludedID }
        preview.request(.init(key: previewKey.base, thumbs: thumbs, ratio: model.canvasHeightRatio, annotations: marks))
    }

    // MARK: Coordinates

    private func norm(_ p: CGPoint) -> CGPoint { AnnotationGeometry.normalize(p, canvasWidth: canvasWidth) }
    private func px(_ p: CGPoint) -> CGPoint { AnnotationGeometry.denormalize(p, canvasWidth: canvasWidth) }
    private func px(_ r: CGRect) -> CGRect { AnnotationGeometry.denormalize(r, canvasWidth: canvasWidth) }

    // MARK: Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if active == nil { begin(at: norm(v.startLocation)) }
                update(to: norm(v.location), translation: v.translation)
            }
            .onEnded { v in
                finish(at: norm(v.location), translation: v.translation)
                active = nil
                draft = nil
            }
    }

    private func begin(at p: CGPoint) {
        focusList()
        model.commitTextEdit()
        guard model.tool == .select else {
            active = .creating(tool: model.tool, start: p)
            model.annotationSelection = nil
            return
        }
        if let id = model.annotationSelection, let sel = model.annotations.annotation(id: id),
           let h = AnnotationGeometry.hitHandle(sel, at: p, tolerance: tolerance) {
            active = .resizing(original: sel, handle: h, checkpointed: false)
        } else if let id = AnnotationGeometry.hitTest(model.annotations.annotations, at: p, tolerance: tolerance),
                  let a = model.annotations.annotation(id: id) {
            model.annotationSelection = id
            active = .moving(original: a, start: p, checkpointed: false)
        } else {
            model.annotationSelection = nil
            active = .idle
        }
    }

    private func update(to p: CGPoint, translation: CGSize) {
        let moved = hypot(translation.width, translation.height) > 2
        let ratio = model.canvasHeightRatio
        switch active {
        case let .creating(tool, start)?:
            guard moved else { return }
            draft = model.makeAnnotation(tool: tool, rect: AnnotationGeometry.rect(from: start, to: p), start: start, end: p)?
                .clamped(canvasHeightRatio: ratio)
        case let .moving(original, start, done)?:
            guard moved || done else { return }
            if !done { model.annotations.checkpoint(); active = .moving(original: original, start: start, checkpointed: true) }
            model.annotations.update(id: original.id, recordUndo: false) {
                $0 = original.moved(dx: p.x - start.x, dy: p.y - start.y, canvasHeightRatio: ratio)
            }
        case let .resizing(original, handle, done)?:
            guard moved || done else { return }
            if !done { model.annotations.checkpoint(); active = .resizing(original: original, handle: handle, checkpointed: true) }
            if case let .arrow(s, e, _) = original.shape {
                model.annotations.resize(id: original.id, start: handle == .arrowStart ? p : s,
                                         end: handle == .arrowEnd ? p : e, canvasHeightRatio: ratio, recordUndo: false)
            } else if original.kind == .image {
                model.annotations.resize(id: original.id,
                                         to: AnnotationImagePlacement.resizedRect(original.bounds, dragging: handle, to: p,
                                                                                  canvasHeightRatio: ratio),
                                         canvasHeightRatio: ratio, recordUndo: false)
            } else {
                model.annotations.resize(id: original.id,
                                         to: AnnotationGeometry.resizedRect(original.bounds, dragging: handle, to: p),
                                         canvasHeightRatio: ratio, recordUndo: false)
            }
        case .idle?, nil:
            break
        }
    }

    private func finish(at p: CGPoint, translation: CGSize) {
        guard case let .creating(tool, start)? = active, hypot(translation.width, translation.height) >= 4,
              let a = model.makeAnnotation(tool: tool, rect: AnnotationGeometry.rect(from: start, to: p), start: start, end: p)
        else { return }
        model.finishCreating(a)
    }

    private func doubleTap(_ location: CGPoint) {
        guard model.tool == .select,
              let id = AnnotationGeometry.hitTest(model.annotations.annotations, at: norm(location), tolerance: tolerance),
              model.annotations.annotation(id: id)?.kind == .text else { return }
        active = nil
        model.beginEditText(id: id)
    }

    // MARK: Overlays

    @ViewBuilder
    private var selectionOverlay: some View {
        if model.textEdit == nil, let id = model.annotationSelection, let a = model.annotations.annotation(id: id) {
            ZStack(alignment: .topLeading) {
                if a.kind != .arrow {
                    let r = px(a.bounds)
                    Rectangle().stroke(Color.accentColor, lineWidth: 1.5)
                        .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                }
                ForEach(Array(AnnotationGeometry.handles(for: a).enumerated()), id: \.offset) { _, h in
                    let p = px(h.point)
                    Rectangle().fill(Color.white)
                        .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1.5))
                        .frame(width: 9, height: 9)
                        .position(p)
                }
            }
        }
    }

    @ViewBuilder
    private var draftOverlay: some View {
        if let d = draft {
            switch d.shape {
            case let .arrow(s, e, _):
                Path { $0.move(to: px(s)); $0.addLine(to: px(e)) }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            default:
                let r = px(d.bounds)
                Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
            }
        }
    }

    @ViewBuilder
    private var textEditor: some View {
        if let te = model.textEdit, let a = model.styleTarget, case let .text(_, _, style) = a.shape {
            let r = px(a.bounds)
            TextEditor(text: Binding(get: { model.textEdit?.text ?? "" }, set: { model.textEdit?.text = $0 }))
                .scrollContentBackground(.hidden)
                .font(.system(size: max(style.fontSize * canvasWidth, 1), weight: style.bold ? .bold : .regular))
                .foregroundStyle(Color(cgColor: style.textColor.cgColor))
                .background(style.fillColor.map { Color(cgColor: $0.cgColor) } ?? Color.clear)
                .overlay(Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
                .id(te.id)
                .focused($editorFocused)
                .onAppear { editorFocused = true }
                .onExitCommand {
                    model.commitTextEdit()
                    focusList()
                }
        }
    }
}
