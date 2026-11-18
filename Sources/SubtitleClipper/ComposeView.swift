import AppKit
import StitchCore
import SwiftUI
import UniformTypeIdentifiers

struct ComposeView: View {
    @ObservedObject var model: AppModel
    @State private var dropTargeted = false
    @State private var zoom = ViewZoom.default
    @State private var magnifyBase: Double?
    @State private var drag: DragState?
    @State private var scrollAccess = ScrollAccess()
    @State private var autoScroller = AutoScroller()
    @FocusState private var listFocused: Bool

    private static let viewportSpace = "reorder-viewport"

    /// 拖曳中的暫態：游標位置為「可視區座標」（不隨捲動改變），內容座標 = 可視區 y + 捲動偏移。
    private struct DragState {
        let id: UUID
        let from: Int
        var cursor: CGPoint
        var viewportHeight: CGFloat
        var heights: [Double]
        /// nil 代表落點非法（不顯示插入線）。
        var insertion: Int?
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            modeBar
            // 常駐固定高度：排版模式保留同高度空白，避免切換模式時長圖位移。
            AnnotationToolbar(model: model)
                .opacity(model.mode == .annotate ? 1 : 0)
                .allowsHitTesting(model.mode == .annotate)
                .accessibilityHidden(model.mode != .annotate)
            Divider()
            content
        }
        .frame(minWidth: 360, minHeight: 400)
        .overlay(alignment: .bottom) { toastView }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3).padding(2) } }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
        .background(shortcuts)
        .animation(.easeInOut(duration: 0.15), value: model.toast)
    }

    // MARK: Toolbar

    /// 視窗內設定（選單列被隱藏時使用）；項目與選單列右鍵選單一致。
    private var settingsMenu: some View {
        Menu {
            Toggle("同時存檔到資料夾", isOn: $model.saveEnabled)
            Button(model.saveFolder.map { "存檔資料夾：\(($0 as NSString).lastPathComponent)…" } ?? "選擇存檔資料夾…") {
                model.chooseSaveFolder()
            }
            Toggle("浮在所有視窗之上", isOn: $model.floatsOverAll)
            Divider()
            Button(model.hotKeyRegistered
                   ? "快捷鍵 ⌃⌥Space：開關視窗"
                   : "⚠︎ 快捷鍵 ⌃⌥Space 無法使用（可能被其他 App 佔用）") {}
                .disabled(true)
            Divider()
            Button("離開") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("設定")
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button("匯入…") { model.importPanel() }
            Button("清空") { model.clear() }.disabled(model.list.items.isEmpty)
            Spacer()
            settingsMenu
            Picker("輸出倍率", selection: $model.outputScale) {
                ForEach(OutputScale.allCases, id: \.self) { Text("\($0.percent)%").tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            .help("輸出解析度倍率（不影響預覽）")
            Button("完成") { model.finish() }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .padding(8)
    }

    private var modeBar: some View {
        HStack {
            Picker("模式", selection: $model.mode) {
                Text("排版").tag(EditMode.layout)
                Text("標記").tag(EditMode.annotate)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)
            .help("排版：排序與紅框；標記：在長圖上加文字框、矩形、箭頭、馬賽克")
            Spacer()
        }
        .padding(.horizontal, 8).padding(.bottom, 6)
    }

    // 隱藏按鈕承接快捷鍵（選單列 App 沒有主選單）。
    private var shortcuts: some View {
        ZStack {
            // 文字框編輯中交給輸入框（按鈕停用時快捷鍵不攔截）。
            Button("") { paste() }.keyboardShortcut("v", modifiers: .command)
                .disabled(model.textEdit != nil)
            // 標記模式且有選取（非文字輸入）才攔截 Cmd+C；其餘交給系統／輸入框。
            Button("") { model.copySelectedAnnotation() }.keyboardShortcut("c", modifiers: .command)
                .disabled(model.mode != .annotate || model.annotationSelection == nil || model.textEdit != nil)
            Button("") { zoom = ViewZoom.zoomedIn(zoom) }.keyboardShortcut("=", modifiers: .command)
            Button("") { zoom = ViewZoom.zoomedOut(zoom) }.keyboardShortcut("-", modifiers: .command)
            Button("") { zoom = ViewZoom.default }.keyboardShortcut("0", modifiers: .command)
            Button("") { model.undoAnnotation() }.keyboardShortcut("z", modifiers: .command)
                .disabled(model.mode != .annotate || model.textEdit != nil)
        }
        .opacity(0).frame(width: 0, height: 0)
    }

    /// 標記模式貼上標記副本或圖片標記（置於可視範圍中心），排版模式維持匯入。
    private func paste() {
        if model.mode == .annotate {
            model.pasteAnnotation(visibleCenter: scrollAccess.visibleCenter())
        } else {
            model.pasteFromClipboard()
        }
    }

    // MARK: List

    @ViewBuilder
    private var content: some View {
        if model.list.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle.angled").font(.largeTitle)
                Text("拖入截圖、按「匯入…」或 Cmd+V 貼上").font(.callout)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geo in
                let baseWidth = geo.size.width
                ScrollView(.horizontal) {
                    list(baseWidth: baseWidth, viewportHeight: geo.size.height)
                        .frame(width: baseWidth * zoom, height: geo.size.height)
                        // 縮小時內容比視窗窄，外層至少撐滿視窗寬度，讓內容置中。
                        .frame(minWidth: geo.size.width)
                }
                .defaultScrollAnchor(.center)
                .background(Color.black)
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let base = magnifyBase ?? zoom
                            magnifyBase = base
                            zoom = ViewZoom.clamp(base * value.magnification)
                        }
                        .onEnded { _ in magnifyBase = nil }
                )
                .overlay(alignment: .bottomTrailing) {
                    Text("\(Int((zoom * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.black.opacity(0.65), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// 各列實際顯示高度（隨縮放，與 ItemRow 的顯示尺寸一致；不依賴 LazyVStack 是否已載入）。
    private func rowHeights(baseWidth: CGFloat) -> [Double] {
        let w = Double(baseWidth * zoom)
        return model.list.items.map { item in
            guard let t = model.thumbnails[item.id], t.width > 0 else { return 60 }
            let rows = item.kind == .frame ? t.height : model.band.rows(imageHeight: t.height).count
            return w * Double(rows) / Double(t.width)
        }
    }

    private func list(baseWidth: CGFloat, viewportHeight: CGFloat) -> some View {
        let sceneIndex = sceneNumbers()
        let heights = rowHeights(baseWidth: baseWidth)
        let items = model.list.items
        return ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    ItemRow(item: item,
                            thumbnail: model.thumbnails[item.id],
                            band: model.band,
                            zoom: zoom,
                            baseWidth: baseWidth,
                            scene: sceneIndex[item.id] ?? 1,
                            isSelected: model.selection == item.id,
                            isDragging: drag?.id == item.id,
                            onToggle: { model.toggleKind(item.id) },
                            onBand: { model.band = $0 })
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.selection = item.id
                            listFocused = true
                        }
                        .gesture(reorderGesture(for: item.id, heights: heights, viewportHeight: viewportHeight))
                        // 標記模式停用排序、紅框把手與徽章點擊。
                        .allowsHitTesting(model.mode == .layout)
                }
            }
            .frame(height: heights.reduce(0, +), alignment: .top)
            .background(ScrollAccessView(access: scrollAccess))
            .overlay(alignment: .topLeading) { insertionLine(heights: heights) }
            .overlay(alignment: .topLeading) {
                AnnotationLayer(model: model, canvasWidth: baseWidth * zoom,
                                canvasHeight: CGFloat(heights.reduce(0, +)),
                                focusList: { listFocused = true })
            }
        }
        .coordinateSpace(name: Self.viewportSpace)
        .background(Color.black)
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onDeleteCommand {
            if model.mode == .annotate { model.deleteSelectedAnnotation() } else { model.removeSelected() }
        }
        .overlay(alignment: .topLeading) { dragPreview(baseWidth: baseWidth) }
    }

    // MARK: Reorder

    @ViewBuilder
    private func insertionLine(heights: [Double]) -> some View {
        if let d = drag, let ins = d.insertion {
            let y = heights.prefix(ins).reduce(0, +)
            Rectangle()
                .fill(Color.yellow)
                .frame(height: 3)
                .shadow(color: .black, radius: 1)
                .offset(y: y - 1.5)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func dragPreview(baseWidth: CGFloat) -> some View {
        if let d = drag, let t = model.thumbnails[d.id] {
            Image(decorative: t, scale: 1)
                .resizable()
                .aspectRatio(CGFloat(t.width) / CGFloat(t.height), contentMode: .fit)
                .frame(width: min(baseWidth * zoom, 240))
                .opacity(0.6)
                .shadow(radius: 6)
                .position(d.cursor)
                .allowsHitTesting(false)
        }
    }

    private func reorderGesture(for id: UUID, heights: [Double], viewportHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.viewportSpace))
            .onChanged { value in
                if drag == nil {
                    guard let from = model.list.items.firstIndex(where: { $0.id == id }) else { return }
                    drag = DragState(id: id, from: from, cursor: value.location,
                                     viewportHeight: viewportHeight, heights: heights, insertion: nil)
                    model.selection = id
                    autoScroller.start { tickAutoScroll() }
                }
                drag?.cursor = value.location
                drag?.viewportHeight = viewportHeight
                drag?.heights = heights
                updateInsertion()
            }
            .onEnded { _ in
                autoScroller.stop()
                if let d = drag, let ins = d.insertion ?? invalidInsertion(d) {
                    model.move(from: d.from, destination: ins)
                }
                drag = nil
            }
    }

    /// 非法落點放開時仍交給 model.move，由既有路徑拒絕並顯示提示。
    private func invalidInsertion(_ d: DragState) -> Int? {
        ReorderLogic.insertionIndex(forY: Double(d.cursor.y) + scrollAccess.offset, rowHeights: d.heights)
    }

    private func updateInsertion() {
        guard var d = drag else { return }
        let y = Double(d.cursor.y) + scrollAccess.offset
        let ins = ReorderLogic.insertionIndex(forY: y, rowHeights: d.heights)
        let kinds = model.list.items.map(\.kind)
        d.insertion = ReorderLogic.resolveDrop(insertion: ins, from: d.from, kinds: kinds).isValid ? ins : nil
        drag = d
    }

    private func tickAutoScroll() {
        guard let d = drag else { return }
        let speed = ReorderLogic.edgeScrollSpeed(cursorY: Double(d.cursor.y), viewportHeight: Double(d.viewportHeight))
        guard speed != 0 else { return }
        scrollAccess.scroll(by: speed / 60)
        updateInsertion()
    }

    private func sceneNumbers() -> [UUID: Int] {
        var map: [UUID: Int] = [:]
        for (i, scene) in model.list.scenes.enumerated() {
            for item in scene { map[item.id] = i + 1 }
        }
        return map
    }

    // MARK: Toast

    @ViewBuilder
    private var toastView: some View {
        if let toast = model.toast {
            Text(toast.text)
                .font(.callout)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(toast.isError ? Color.red.opacity(0.9) : Color.green.opacity(0.9), in: Capsule())
                .foregroundStyle(.white)
                .padding(.bottom, 12)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    // MARK: Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "drop.collect")
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    queue.sync { urls.append(url) }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { model.importFiles(urls) }
        }
        return true
    }
}

private struct ItemRow: View {
    let item: ComposeItem
    let thumbnail: CGImage?
    let band: CropBand
    let zoom: Double
    let baseWidth: CGFloat
    let scene: Int
    let isSelected: Bool
    let isDragging: Bool
    let onToggle: () -> Void
    let onBand: (CropBand) -> Void

    private var isFrame: Bool { item.kind == .frame }
    private var space: String { "img-\(item.id.uuidString)" }

    /// 縮放 1.0 時（寬 = baseWidth）的顯示高度；紅框換算以此搭配 zoom。
    private var displayHeight: Double {
        guard let t = thumbnail, t.width > 0 else { return 60 }
        return Double(baseWidth) * Double(t.height) / Double(t.width)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            displayImage
            if isFrame, thumbnail != nil { bandOverlay }
            badge
        }
        .coordinateSpace(name: space)
        .frame(width: baseWidth * zoom, alignment: .topLeading)
        .overlay { if isSelected { Rectangle().stroke(Color.accentColor, lineWidth: 2) } }
        .opacity(isDragging ? 0.3 : 1)
    }

    private var badge: some View {
        Button(action: onToggle) {
            Text(isFrame ? "第 \(scene) 幕 · 畫面" : "字幕")
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(isFrame ? Color.accentColor : Color.orange, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .padding(6)
        .help("點擊切換畫面／純字幕")
    }

    @ViewBuilder
    private var displayImage: some View {
        if let thumbnail {
            let shown = isFrame ? thumbnail : (SubtitleCrop.crop(thumbnail, band: band) ?? thumbnail)
            Image(decorative: shown, scale: 1)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(CGFloat(shown.width) / CGFloat(shown.height), contentMode: .fit)
                .frame(width: baseWidth * zoom)
        } else {
            Color.gray.opacity(0.2).frame(width: baseWidth * zoom, height: 60)
        }
    }

    private func y(_ ratio: Double) -> CGFloat {
        CGFloat(CropBandGeometry.y(forRatio: ratio, displayHeight: displayHeight, zoom: zoom))
    }

    private func ratio(_ y: CGFloat) -> Double {
        CropBandGeometry.ratio(forY: Double(y), displayHeight: displayHeight, zoom: zoom)
    }

    private var bandOverlay: some View {
        let top = y(band.top), bottom = y(band.bottom)
        let grip: CGFloat = 14
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.red.opacity(0.15))
                .overlay(Rectangle().stroke(Color.red, lineWidth: 2))
                .frame(width: baseWidth * zoom, height: max(bottom - top, 1))
                .offset(y: top)
                .allowsHitTesting(false)
            handle(height: grip)
                .offset(y: top - 4)
                .gesture(drag { onBand(band.movingTop(to: ratio($0))) })
            handle(height: grip)
                .offset(y: bottom - grip + 4)
                .gesture(drag { onBand(band.movingBottom(to: ratio($0))) })
        }
    }

    private func handle(height: CGFloat) -> some View {
        Color.red.opacity(0.001)
            .frame(width: baseWidth * zoom, height: height)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
    }

    private func drag(_ update: @escaping (CGFloat) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { update($0.location.y) }
    }
}

// MARK: - Scroll helpers

/// 取得內層垂直 NSScrollView，以像素為單位讀寫捲動偏移（SwiftUI 無對應 API）。
@MainActor
final class ScrollAccess {
    weak var scrollView: NSScrollView?

    var offset: Double { Double(scrollView?.contentView.bounds.origin.y ?? 0) }

    /// 目前可視範圍中心（長圖寬度正規化座標）。長圖寬 = 垂直捲動內容寬；水平以外層捲動視窗換算（內容比視窗窄時為 0.5）。
    /// 取不到捲動視窗時退回 (0.5, 0)。
    func visibleCenter() -> CGPoint {
        guard let sv = scrollView, let doc = sv.documentView, doc.frame.width > 0 else { return CGPoint(x: 0.5, y: 0) }
        let w = Double(doc.frame.width)
        let clip = sv.contentView.bounds
        var x = 0.5
        if let outer = sv.enclosingScrollView, w > Double(outer.contentView.bounds.width) + 0.5 {
            x = Double(outer.contentView.bounds.midX) / w
        }
        return CGPoint(x: min(max(x, 0), 1), y: (Double(clip.origin.y) + Double(clip.height) / 2) / w)
    }

    func scroll(by dy: Double) {
        guard let sv = scrollView, let doc = sv.documentView else { return }
        let clip = sv.contentView
        let maxY = max(doc.frame.height - clip.bounds.height, 0)
        let y = min(max(Double(clip.bounds.origin.y) + dy, 0), Double(maxY))
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        sv.reflectScrolledClipView(clip)
    }
}

private struct ScrollAccessView: NSViewRepresentable {
    let access: ScrollAccess

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            if let sv = nsView?.enclosingScrollView { access.scrollView = sv }
        }
    }
}

/// 拖曳期間以 60Hz 計時器驅動邊緣自動捲動。
@MainActor
final class AutoScroller {
    private var timer: Timer?

    func start(_ tick: @escaping @MainActor () -> Void) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
