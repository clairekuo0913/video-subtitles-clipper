import AppKit
import StitchCore
import SwiftUI

enum EditMode: Hashable { case layout, annotate }
enum AnnotationTool: Hashable { case select, text, rectangle, arrow, mosaic }

/// 文字框編輯中的暫態。新建者尚未進入標記清單（提交且非空才加入，整段為一次撤銷）。
struct TextEdit {
    let id: UUID
    let isNew: Bool
    var pending: Annotation
    var text: String
}

@MainActor
final class AppModel: ObservableObject {
    private enum Key {
        static let saveEnabled = "saveEnabled"
        static let saveFolder = "saveFolder"
    }

    private let defaults = UserDefaults.standard
    private let settings = SettingsStore()

    @Published private(set) var list = ComposeList()
    @Published private(set) var thumbnails: [UUID: CGImage] = [:]
    @Published var selection: UUID?
    @Published var toast: Toast?
    @Published var band: CropBand {
        didSet { settings.band = band }
    }
    @Published var outputScale: OutputScale {
        didSet { settings.outputScale = outputScale }
    }
    @Published var saveEnabled: Bool {
        didSet { defaults.set(saveEnabled, forKey: Key.saveEnabled) }
    }
    @Published var saveFolder: String? {
        didSet { defaults.set(saveFolder, forKey: Key.saveFolder) }
    }

    // MARK: Annotations state
    @Published var mode: EditMode = .layout {
        didSet {
            guard mode != oldValue else { return }
            if mode == .annotate {
                show("標記不會跟著圖片移動，建議先排好版")
            } else {
                commitTextEdit()
                annotationSelection = nil
            }
        }
    }
    @Published var annotations = AnnotationList()
    @Published var annotationSelection: UUID?
    @Published var tool: AnnotationTool = .select
    @Published var textEdit: TextEdit?
    /// 標記內部剪貼簿；不寫入系統剪貼簿，僅記錄複製當下的 changeCount 以判斷之後系統剪貼簿是否被更新。
    private var annotationClipboard = AnnotationClipboard()
    private var clipboardChangeCount = 0
    let styleStore = AnnotationStyleStore()

    struct Toast: Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    init() {
        band = settings.band
        outputScale = settings.outputScale
        saveEnabled = defaults.bool(forKey: Key.saveEnabled)
        saveFolder = defaults.string(forKey: Key.saveFolder)
    }

    // MARK: - Toast

    func show(_ text: String, isError: Bool = false) {
        let t = Toast(text: text, isError: isError)
        toast = t
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self?.toast == t { self?.toast = nil }
        }
    }

    // MARK: - Import

    func importFiles(_ urls: [URL]) {
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { ImageLoading.load(urls: urls) }.value
            if loaded.isEmpty {
                show("沒有可匯入的圖片", isError: true)
            } else {
                add(loaded)
            }
        }
    }

    func importPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { importFiles(panel.urls) }
    }

    func pasteFromClipboard() {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            importFiles(urls)
            return
        }
        guard let cg = Self.clipboardImage(),
              let thumb = ImageLoading.thumbnail(of: cg)
        else {
            show("剪貼簿沒有圖片", isError: true)
            return
        }
        add([LoadedImage(name: "貼上的圖片", image: cg, thumbnail: thumb)])
    }

    private static func clipboardImage() -> CGImage? {
        NSImage(pasteboard: .general)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func add(_ images: [LoadedImage]) {
        for img in images {
            let item = list.append(image: img.image, name: img.name)
            thumbnails[item.id] = img.thumbnail
        }
    }

    // MARK: - Edit

    func toggleKind(_ id: UUID) {
        if case .failure(let e) = list.toggleKind(id: id) { reject(e) }
    }

    func removeSelected() {
        guard let id = selection else { return }
        if case .success = list.remove(id: id) {
            thumbnails[id] = nil
            selection = nil
        }
    }

    func clear() {
        list.clear()
        thumbnails = [:]
        selection = nil
        annotations.clear()
        annotationClipboard.clear()
        annotationSelection = nil
        textEdit = nil
    }

    /// SwiftUI `onMove` 的 destination 為插入前偏移，換算成移動後的最終索引。
    func move(from source: Int, destination: Int) {
        let to = source < destination ? destination - 1 : destination
        if case .failure(let e) = list.move(from: source, to: to) { reject(e) }
    }

    private func reject(_ e: ComposeError) {
        if e == .firstItemMustBeFrame { show("第一項必須是畫面", isError: true) }
    }

    // MARK: - Output

    func finish() {
        guard !list.items.isEmpty else {
            show("清單是空的", isError: true)
            return
        }
        commitTextEdit()
        let snapshot = list, band = band, scale = outputScale
        let marks = annotations.annotations
        let folder = saveEnabled ? saveFolder : nil
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (Data, Int, Int)? in
                guard let image = Stitcher.stitch(snapshot, band: band, outputScale: scale, annotations: marks),
                      let data = PNGOutput.encode(image) else { return nil }
                return (data, image.width, image.height)
            }.value
            guard let (png, w, h) = result else {
                show("輸出失敗", isError: true)
                return
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(png, forType: .png)
            let size = "\(w)×\(h)"
            var message = "已複製 \(size)"
            if let folder {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(PNGOutput.filename())
                do { try png.write(to: url); message = "已複製並存檔 \(size)" }
                catch { show("已複製，但存檔失敗", isError: true); return }
            } else if saveEnabled {
                show("已複製 \(size)（尚未選擇存檔資料夾）", isError: true)
                return
            }
            show(message)
        }
    }

    // MARK: - Annotations

    /// 長圖高 / 寬（各列等比縮到同寬後加總，與 Stitcher 及畫面列高一致）。
    var canvasHeightRatio: CGFloat {
        var sum = 0.0
        for item in list.items {
            guard let t = thumbnails[item.id], t.width > 0 else { continue }
            let rows = item.kind == .frame ? t.height : band.rows(imageHeight: t.height).count
            sum += Double(rows) / Double(t.width)
        }
        return CGFloat(sum)
    }

    /// 以目前工具與「上次樣式」建立（尚未加入清單的）標記。
    func makeAnnotation(tool: AnnotationTool, rect: CGRect, start: CGPoint, end: CGPoint) -> Annotation? {
        switch tool {
        case .text: return Annotation(shape: .text(rect: rect, text: "", style: styleStore.textStyle))
        case .rectangle: return Annotation(shape: .rectangle(rect: rect, style: styleStore.rectangleStyle))
        case .arrow: return Annotation(shape: .arrow(start: start, end: end, style: styleStore.arrowStyle))
        case .mosaic: return Annotation(shape: .mosaic(rect: rect))
        case .select: return nil
        }
    }

    /// 完成建立：文字框進入輸入，其餘直接加入並選取；之後回到選取工具。
    func finishCreating(_ annotation: Annotation) {
        tool = .select
        if case .text = annotation.shape {
            let clamped = annotation.clamped(canvasHeightRatio: canvasHeightRatio)
            textEdit = TextEdit(id: clamped.id, isNew: true, pending: clamped, text: "")
            annotationSelection = nil
        } else {
            let added = annotations.add(annotation, canvasHeightRatio: canvasHeightRatio)
            annotationSelection = added.id
        }
    }

    func beginEditText(id: UUID) {
        commitTextEdit()
        guard let a = annotations.annotation(id: id), case let .text(_, text, _) = a.shape else { return }
        annotationSelection = id
        textEdit = TextEdit(id: id, isNew: false, pending: a, text: text)
    }

    func commitTextEdit() {
        guard let te = textEdit else { return }
        textEdit = nil
        if te.isNew {
            guard !te.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            var a = te.pending
            if case let .text(r, _, s) = a.shape { a.shape = .text(rect: r, text: te.text, style: s) }
            annotationSelection = annotations.add(a, canvasHeightRatio: canvasHeightRatio).id
        } else if let cur = annotations.annotation(id: te.id), case let .text(_, old, _) = cur.shape, old != te.text {
            annotations.update(id: te.id) { a in
                if case let .text(r, _, s) = a.shape { a.shape = .text(rect: r, text: te.text, style: s) }
            }
        }
    }

    /// 標記模式 Cmd+V：剪貼簿有圖片 → 加入圖片標記於 `center`（正規化座標，通常為可視範圍中心），選取並回到選取工具。
    func pasteImageAnnotation(visibleCenter center: CGPoint) {
        commitTextEdit()
        guard !list.items.isEmpty else {
            show("請先匯入圖片", isError: true)
            return
        }
        guard let cg = Self.clipboardImage(), cg.width > 0, cg.height > 0 else {
            show("剪貼簿沒有圖片", isError: true)
            return
        }
        let ratio = canvasHeightRatio
        let rect = AnnotationImagePlacement.defaultRect(canvasHeightRatio: ratio, center: center,
                                                        aspect: CGFloat(cg.width) / CGFloat(cg.height))
        let added = annotations.add(Annotation(shape: .image(rect: rect, image: cg)), canvasHeightRatio: ratio)
        tool = .select
        annotationSelection = added.id
    }

    /// 標記模式 Cmd+C：有選取標記才複製到內部剪貼簿（不寫系統剪貼簿）；否則無作用。
    func copySelectedAnnotation() {
        guard textEdit == nil, let id = annotationSelection, let a = annotations.annotation(id: id) else { return }
        annotationClipboard.copy(a)
        clipboardChangeCount = NSPasteboard.general.changeCount
    }

    /// 標記模式 Cmd+V：內部有內容且系統剪貼簿自複製後未更新 → 貼標記副本（選取、回到選取工具）；否則貼剪貼簿圖片。
    func pasteAnnotation(visibleCenter center: CGPoint) {
        guard annotationClipboard.hasContent, NSPasteboard.general.changeCount == clipboardChangeCount,
              let copy = annotationClipboard.pasted(canvasHeightRatio: canvasHeightRatio) else {
            pasteImageAnnotation(visibleCenter: center)
            return
        }
        let added = annotations.add(copy, canvasHeightRatio: canvasHeightRatio)
        tool = .select
        annotationSelection = added.id
    }

    func deleteSelectedAnnotation() {
        guard let id = annotationSelection, textEdit == nil else { return }
        if annotations.remove(id: id) { annotationSelection = nil }
    }

    func undoAnnotation() {
        guard annotations.undo() else { return }
        if let id = annotationSelection, annotations.annotation(id: id) == nil { annotationSelection = nil }
    }

    /// 樣式面板的目標：編輯中的文字框，否則選取的標記。
    var styleTarget: Annotation? {
        if let te = textEdit { return te.isNew ? te.pending : annotations.annotation(id: te.id) }
        return annotationSelection.flatMap { annotations.annotation(id: $0) }
    }

    /// 樣式面板種類：有目標時看目標，否則看目前工具（馬賽克、選取無樣式）。
    var styleKind: AnnotationKind? {
        if let t = styleTarget { return t.kind == .mosaic || t.kind == .image ? nil : t.kind }
        switch tool {
        case .text: return .text
        case .rectangle: return .rectangle
        case .arrow: return .arrow
        case .select, .mosaic: return nil
        }
    }

    var currentTextStyle: TextStyle {
        if case let .text(_, _, s)? = styleTarget?.shape { return s }
        return styleStore.textStyle
    }

    var currentLineStyle: LineStyle {
        switch styleTarget?.shape {
        case let .rectangle(_, s)?, let .arrow(_, _, s)?: return s
        default: return styleKind == .arrow ? styleStore.arrowStyle : styleStore.rectangleStyle
        }
    }

    /// 修改樣式：即時套用於目標（進撤銷），並寫回「上次樣式」。
    /// `continuous`（調色盤連續拖曳）時，短時間內同一目標的連續更新合併為一個撤銷步驟。
    func setTextStyle(_ style: TextStyle, continuous: Bool = false) {
        styleStore.textStyle = style
        applyToTarget(continuous: continuous) { a in
            if case let .text(r, t, _) = a.shape { a.shape = .text(rect: r, text: t, style: style) }
        }
    }

    func setLineStyle(_ style: LineStyle, continuous: Bool = false) {
        if styleKind == .arrow { styleStore.arrowStyle = style } else { styleStore.rectangleStyle = style }
        applyToTarget(continuous: continuous) { a in
            switch a.shape {
            case let .rectangle(r, _): a.shape = .rectangle(rect: r, style: style)
            case let .arrow(s, e, _): a.shape = .arrow(start: s, end: e, style: style)
            default: break
            }
        }
    }

    private var lastContinuousStyle: (id: UUID, time: Date)?
    private static let continuousStyleWindow: TimeInterval = 0.6

    private func applyToTarget(continuous: Bool = false, _ body: (inout Annotation) -> Void) {
        if var te = textEdit, te.isNew {
            body(&te.pending)
            textEdit = te
        } else if let id = textEdit?.id ?? annotationSelection {
            var record = true
            if continuous {
                let now = Date()
                if let last = lastContinuousStyle, last.id == id, now.timeIntervalSince(last.time) < Self.continuousStyleWindow {
                    record = false
                }
                lastContinuousStyle = (id, now)
            } else {
                lastContinuousStyle = nil
            }
            annotations.update(id: id, recordUndo: record, body)
        }
        objectWillChange.send()
    }

    // MARK: - Save settings

    func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { saveFolder = url.path }
    }
}
