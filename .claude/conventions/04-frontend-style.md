# 04 · 前端與風格

## 架構
- 單一 `index.html`：`<style>` + DOM + 一段 `<script>`。無框架、無建置。
- 儲存層做成 **`Store` adapter**（雲端 RPC；無金鑰時退回 localStorage），可抽換。
- 狀態：`view`（`list|edit|result`）、`current`（當前帳本物件）、`_locked`（已結清唯讀）、`IS_DEMO`（範例模式）。
- `rowToGathering(row)` 把後端 row 轉成前端 `current`（含 ownerId、fastPayUid 等）。

## XSS 安全（鐵則）
- **所有使用者可控字串插進 DOM 一律過 `esc()`**（跳脫 `& < > " '`）。名字、稱呼、標題、品名、備註、調整名、收款資訊、轉帳備註、history 都要。
- **圖片網址**：`validPicUrl`（https + 擋 `['"\\<>]`）、封面 `parseCover`（限 Supabase storage + 擋引號）。所有頭像/封面 url 都要過，無例外。
- **對話框用自家 `uiConfirm` / `uiPrompt`（`textContent`）**，不用原生 `confirm/alert/prompt`（LINE 內建瀏覽器會露網域）。`toast` 也用 textContent。
- 不要 `eval` / `new Function` / `javascript:` / 未跳脫的 `innerHTML` 插使用者輸入 / 未驗證的 `href=${url}`。
- 屬性內的 id/uid 都是 `uid()` 產生的 base36 或 server uuid（無引號可破），attribute 注入不成立；新加屬性插值仍以 esc 為準。

## UI 元件慣例
- **modal**：`.modal` + `.modal-card`（深色卡、圓角、max-height:90vh）。
- **編輯頁**：摘要卡（標題/日期/人數/總額/封面）→ 成員頭像名冊 `.members-strip` → quickbar（成員/邀請/算分帳）→ 帳目卡 → 轉帳卡 → 大「算分帳」CTA → 右下 `.fab`（新增帳目）。
- **功能性圖示用自繪 SVG**（`const ICONS`，stroke=currentColor、薄荷色圓角），**不要用 emoji 當功能鍵**；emoji 只用在語氣（🎉🔔🎁）。
- 成對按鈕 `.row > .btn{flex:1}` 等寬。
- 結果頁 `renderResult`：每人淨值 + 最少轉帳 + 結清進度 + 六道驗算；結算動作鈕依身分顯示（付款人標已付、收款人確認/我已收到）。

## 色彩與主題
- 用 **CSS 變數**，勿寫死色：`--accent`(主薄荷)、`--pay`(付/金額暖紅)、`--get`(收綠)、`--ink`/`--muted`/`--faint`、`--panel`/`--panel2`/`--line`、`--accent-soft`/`--accent-bd`、`--on-accent`、`--amount`、`--rc-bg` 等。
- 三主題：`html[data-theme=cool|warm|forest]`（個人設定切換、存 `aa_theme`、預設 cool；forest 需邀請解鎖）。head 早期 script 防閃爍。
- 字級 ≥ 11px、深色底要可讀。

## 品牌語氣 / 命名
- 繁中（台灣用語）、口語親切、精簡；技術名詞保留英文。
- 命名清楚就好，**只在「為什麼這樣做」不明顯時加註解**，不要解釋「這段在做什麼」。
- 不要為了「看起來完整」過度重構/加防呆/加文件。

## 範例帳本 / 引導 / 說明（維護注意）
- `?demo=1` → `enterDemo()` 載入範例帳本、用真 `renderEdit/renderResult` 渲染（免登入）。`IS_DEMO` 守 `persistCurrent` / 結算 trio / `saveProfile` / 上傳（範例不寫雲端）。
- **新手引導** `ONBOARD_STEPS` 用選擇器聚光：`#main .fab`(記一筆) / `.btn.block.calcbtn`(算分帳) / `.quickbar`(邀朋友)。**改這些控制項的 class/結構時，務必同步 `ONBOARD_STEPS`**。`obShow` 會 `scrollIntoView` 把目標捲到中央、`positionTip` 把說明框夾在 viewport 內。
- **使用說明** `GUIDE_ITEMS` → `#guideModal`，每張「看實際畫面」`guideDemo()` 跳範例真畫面。引導與說明共用範例帳本＝改一次兩邊同步、不怕截圖過期。
- 圖片上傳用 `downscaleImage(file, maxW, targetKB, startQ)`（封面 1280/200KB、頭像 256/60KB；逼近目標大小：先降畫質再縮尺寸）。

## 個人設定版面
- 緊湊但留呼吸：頭像選項單行（`avopts` nowrap + 需要時橫捲）、上下 padding 留白。預設頭像 4 款在選單（`PRESET_AVATAR_ORDER`，`smiley` 已移出選單但 `PRESET_AVATARS` 仍保留讓已選的人不壞）。
