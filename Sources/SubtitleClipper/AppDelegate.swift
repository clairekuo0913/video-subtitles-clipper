import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var statusMenu: NSMenu!
    private var saveToggleItem: NSMenuItem!
    private var folderItem: NSMenuItem!
    private var floatItem: NSMenuItem!
    private var panel: NSPanel!
    private var hotKey: GlobalHotKey?
    private var hotKeyRegistered = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        // 浮動面板：可出現在其他 App 的全螢幕 Space 之上並可直接拖動。
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 680),
                            styleMask: [.titled, .closable, .resizable, .miniaturizable],
                            backing: .buffered, defer: false)
        panel.hidesOnDeactivate = false
        applyFloating()
        window = panel
        window.title = "字幕拼接"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ComposeView(model: model))
        window.setFrameAutosaveName("ComposeWindow")
        window.center()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "字幕拼接")
            button.title = " 字幕"
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // 全域快捷鍵 ⌃⌥Space 開關視窗；失敗時於選單顯示警示。
        hotKey = GlobalHotKey { [weak self] in
            MainActor.assumeIsolated { self?.toggleWindow() }
        }
        hotKeyRegistered = hotKey?.register(keyCode: kVK_Space, modifiers: controlKey | optionKey) ?? false
        buildMenu()

        // 選單列空間不足時圖示可能被隱藏，啟動與重新開啟時直接顯示視窗作為保險。
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    /// 「浮在所有視窗之上」開關（預設開）：開＝浮動面板且可出現在全螢幕 Space；關＝一般視窗。
    private var floatsOverAll: Bool {
        get { UserDefaults.standard.object(forKey: "floatsOverAll") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "floatsOverAll") }
    }

    private func applyFloating() {
        if floatsOverAll {
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            panel.isFloatingPanel = false
            panel.level = .normal
            panel.collectionBehavior = []
        }
    }

    @objc private func toggleFloating() {
        floatsOverAll.toggle()
        applyFloating()
    }

    private func buildMenu() {
        statusMenu = NSMenu()
        let hotKeyInfo = hotKeyRegistered
            ? "快捷鍵 ⌃⌥Space：開關視窗"
            : "⚠︎ 快捷鍵 ⌃⌥Space 無法使用（可能被其他 App 佔用）"
        let hotKeyItem = statusMenu.addItem(withTitle: hotKeyInfo, action: nil, keyEquivalent: "")
        hotKeyItem.isEnabled = false
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "匯入…", action: #selector(importImages), keyEquivalent: "").target = self
        statusMenu.addItem(withTitle: "清空", action: #selector(clearAll), keyEquivalent: "").target = self
        statusMenu.addItem(.separator())
        saveToggleItem = statusMenu.addItem(withTitle: "同時存檔到資料夾", action: #selector(toggleSave), keyEquivalent: "")
        saveToggleItem.target = self
        folderItem = statusMenu.addItem(withTitle: "選擇存檔資料夾…", action: #selector(chooseFolder), keyEquivalent: "")
        folderItem.target = self
        statusMenu.addItem(.separator())
        floatItem = statusMenu.addItem(withTitle: "浮在所有視窗之上", action: #selector(toggleFloating), keyEquivalent: "")
        floatItem.target = self
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "離開", action: #selector(quit), keyEquivalent: "q").target = self
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            saveToggleItem.state = model.saveEnabled ? .on : .off
            floatItem.state = floatsOverAll ? .on : .off
            folderItem.title = model.saveFolder.map { "存檔資料夾：\(($0 as NSString).lastPathComponent)…" } ?? "選擇存檔資料夾…"
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggleWindow()
        }
    }

    private func toggleWindow() {
        if window.isVisible && window.isKeyWindow {
            window.orderOut(nil)
        } else {
            showWindow()
        }
    }

    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func importImages() { showWindow(); model.importPanel() }
    @objc private func clearAll() { model.clear() }
    @objc private func toggleSave() { model.saveEnabled.toggle() }
    @objc private func chooseFolder() {
        model.chooseSaveFolder()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
