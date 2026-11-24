# Tasks

## 1. StitchCore：每幕紅框邏輯

- [x] 1.1 `ComposeItem` 加入可選 `band: CropBand?`（預設 nil）；`ComposeList.setBand(_:forFrame:)` 設定畫面項目的覆寫，對字幕或不存在的 id 回傳錯誤。驗證：`ComposeListTests` 新增案例通過。
- [x] 1.2 `ComposeList.effectiveBands(default:)`：frame 取覆寫或前一幕生效值，字幕取所屬幕生效值，第一幕無覆寫取 default。驗證：測試涵蓋「全未自訂＝全為 default」「第二幕自訂不影響第一幕」「第三幕跟隨第二幕」「第一幕變動帶動未自訂幕、不影響已自訂幕」。
- [x] 1.3 `setKind`／`toggleKind` 轉字幕時清除 `band`、轉畫面時 `band = nil`；`remove` 使新首項被轉為 frame 時清除其 `band`；`move` 保留覆寫。驗證：對應單元測試通過。
- [x] 1.4 `Stitcher.stitch` 逐項使用 `effectiveBands(default: band)`。驗證：`StitchTests` 新增兩幕不同紅框的輸出像素高度與內容測試；無覆寫時與既有輸出逐像素相同（既有測試全過）。

## 2. App：資料流與 UI

- [x] 2.1 `AppModel`：新增依畫面項目寫入覆寫的方法；第一幕拖曳更新 `default` 並存 `settings.band`，非第一幕只寫覆寫並存 `settings.band` 為最近調整值。提供 `effectiveBands` 給 UI 與預覽、輸出使用；`finish` 與縮圖列高計算（`AppModel.swift` 約 187、224 行）改用生效紅框。驗證：`swift build` 成功，`SettingsTests` 涵蓋記住最近一次調整值。
- [x] 2.2 `ComposeView`：`ItemRow` 傳入該項目生效紅框，紅框拖曳呼叫各畫面項目自己的寫入；`rowHeights` 使用各項目生效紅框。`AnnotationPreview`／`AnnotationLayer` 的 `PreviewKey` 與 `Stitcher.stitch` 呼叫改用各項目生效紅框。驗證：`swift build` 成功、`swift test` 全過；UI 行為留待 2.3。
- [x] 2.3 手動驗證（由使用者操作）：兩幕以上，調第二幕紅框不影響第一幕；調第一幕時未自訂的幕跟隨；畫面切字幕再切回會回到沿用；複製到剪貼簿的長圖與預覽一致。

## 3. 文件

- [x] 3.1 README「字幕列範圍（紅框）」與「已知限制」更新為每幕各自一組，補上沿用規則與標記偏移提醒。驗證：`openspec validate per-scene-crop-band --strict` 通過且 README 無「整張長圖共用一組」字樣（`grep` 確認）。

## Workflow follow-up

- 使用者完成 2.3 後勾選並歸檔（`/opsx:archive`）。
