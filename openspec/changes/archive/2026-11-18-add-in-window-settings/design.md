# Design

## Context

設定目前分散：存檔開關與資料夾在 `AppModel`，「浮在所有視窗之上」與快捷鍵註冊結果在 `AppDelegate`，只在右鍵選單顯示。See proposal.md for motivation。

## Goals / Non-Goals

**Goals:**
- 視窗內能完成右鍵選單的所有設定操作，且兩邊狀態一致。

**Non-Goals:**
- 不新增設定項目、不改行為。

## Decisions

1. **將「浮在所有視窗之上」與「快捷鍵是否註冊成功」移入 `AppModel`（`@Published`），`AppDelegate` 觀察變化後套用**
   讓視窗（SwiftUI）與選單（AppKit）讀寫同一來源。替代方案：兩邊各存一份再同步（易不一致）。
2. **視窗工具列加入 SwiftUI `Menu`（齒輪圖示）**，內容為 `Toggle`／`Button`，綁定 `AppModel`。
3. **右鍵選單在顯示前（`statusClicked`）依 `AppModel` 重新設定勾選狀態**，沿用現有做法。
4. **「離開」同時存在於兩處**，呼叫 `NSApp.terminate`。

## Risks / Trade-offs

- [模型與 AppDelegate 雙向依賴造成循環更新] → 單向：UI 改 model，delegate 以 `didSet`/Combine 套用視窗層級，不回寫 model。
- [工具列空間不足] → 設定收進一個齒輪選單，不增加獨立按鈕。
