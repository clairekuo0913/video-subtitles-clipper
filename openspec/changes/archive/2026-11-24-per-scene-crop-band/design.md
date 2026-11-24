# Design

## Context

- `ComposeList` 是扁平清單，`frame` 項目開新一幕，幕為衍生資料。
- 目前 `AppModel.band` 為單一全域值，經 `Stitcher.stitch(_:band:)`、`ComposeView`（列高計算與 `ItemRow`）、`AnnotationPreview`/`AnnotationLayer`（預覽快取 key）使用，並由 `SettingsStore` 持久化。
- 紅框 UI 已只出現在畫面項目上，拖曳呼叫 `onBand`。

## Goals / Non-Goals

**Goals:**
- 每幕可獨立紅框；沒調整時與現行行為逐像素相同。
- 邏輯放在 `StitchCore`，可單元測試。

**Non-Goals:**
- 不做每張字幕圖各自紅框。
- 不提供「重設為沿用前一幕」按鈕（可之後再加）。
- 不持久化每幕紅框（清單本身不持久化）。
- 不讓標記隨內容移動（既有限制）。

## Decisions

1. **覆寫存於 frame 項目：`ComposeItem.band: CropBand?`**（nil＝沿用）。
   - 理由：覆寫隨畫面項目走，拖曳排序、移除、類型切換自然維持；不需另一份「幕 ID → band」對照表去同步。
   - 替代：獨立 `[SceneID: CropBand]`——幕是衍生資料沒有穩定 ID，需額外維護，否決。
   - 替代：新增幕時「複製」前一幕的值——之後調整第一幕不會帶動後面，與「沒調整就等同原行為」不符，否決。
2. **生效紅框由 `ComposeList.effectiveBands(default:) -> [ComposeItem.ID: CropBand]` 計算**：依序掃描，遇 frame 取 `item.band ?? 前一幕生效值 ?? default`，subtitle 取其幕的生效值。`default` 為 `AppModel` 持有的全域預設（即現有 `band`）。
3. **`Stitcher.stitch(_:band:…)` 的 `band` 語意改為預設（第一幕）紅框**，內部用 `effectiveBands`。簽名不變，既有測試與無覆寫輸出不變。
4. **類型切換與移動維護覆寫**：`setKind` 轉為 subtitle 時清除 `band`；轉為 frame 時 `band = nil`。`move` 與 `remove` 不需動覆寫；`remove` 第一項後新首項被強制轉 frame 時 `band = nil`。
5. **寫入語意**：`AppModel` 持有 `defaultBand`（第一幕未自訂時的生效值，啟動時載入 `settings.band`）。使用者拖曳某幕紅框時：
   - 第一幕：同時更新 `defaultBand`（未自訂的後續幕因此跟隨）；
   - 其他幕：只寫該畫面項目的覆寫，`defaultBand` 不變（避免回頭改變前面未自訂的幕）；
   - 兩者都把本次範圍存入 `settings.band`，作為下次啟動的 `defaultBand`。
6. **UI**：`ItemRow` 的 `band` 傳入該項目的生效值；`rowHeights`、`AnnotationPreview` 的 `PreviewKey` 以各項目生效紅框陣列取代單一 band；`AppModel` 的縮圖列高計算同理。

## Risks / Trade-offs

- [使用者拖曳第二幕以為在全域調整] → 紅框僅出現在各畫面圖上，視覺上即「這幕的」；README 說明。
- [自訂後想退回沿用沒有按鈕] → 把該畫面切成字幕再切回畫面會清除覆寫（可行替代）；按鈕列為後續功能。
- [每幕紅框高度不同使長圖高度改變，標記相對內容偏移] → 沿用既有「先排好版再標記」限制並更新 README。
- [預覽快取 key 變大] → 以各項目 band 陣列比較，項目數有限（約 30），可接受。

## Open Questions

- 無。
