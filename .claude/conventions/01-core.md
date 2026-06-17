# 01 · 核心

## 定位
- 「欸，算一下！」/ Let's Split：**朋友間單次聚會的 AA 分帳工具**。場景是 LINE 群組裡「每次聚會建一張單次分帳單」，**不是** Splitwise 式跨次累積帳本。
- 已定案目標＝**真・公開產品**（所有 LINE 用戶、任意群組可用、會推廣）。
- 核心使用模式：建立帳本 → 邀朋友加入 → **每人各自記自己的支出** → 系統彙整算出最少轉帳。不是單一 host 幫所有人輸入。

## 品牌
- 中文「欸，算一下！」、英文「Let's Split」（2026-06-15 定）。頁籤、標題列、隱私/條款頁一致。
- 語氣：口語、親切、台灣用語、精簡。可用 emoji 點綴語氣（🎉、🔔），但**功能性圖示用自繪 SVG**（見 `04`）。

## 技術棧
- **前端**：單一 `index.html`，純前端 + LIFF SDK。無框架、無建置流程。
- **後端**：Supabase（Postgres + PostgREST RPC + Storage + Edge Functions）。
- **登入/身分**：LINE LIFF（LINE Login channel）。用 access token 打 LINE userinfo 換已驗證 userId。
- **託管**：GitHub Pages（`waynelin-yuzhi/aa-split`）。
- **計算引擎**：`aa-split` skill 的 `aa.py` 之 **JS 忠實移植**（`computeSplit`）。

## 資料模型（單一 expense 模型，已定案、不再變動）
`gatherings` 一列 = 一場聚會（帳本）。主要欄位：
- `id` (uuid)、`slug`(短連結 capability)、`share_token`、`owner_id`(建立者 LINE uid)。
- `title`、`event_date`、`currency`(結算幣固定 TWD)、`cover`(封面圖 url，可帶 `#p=` 位置)。
- `participants` jsonb：`[{id, name, uid?, pic?, payInfo?}]`。`id` 是本機產生的 base36（`uid()`）；`uid` 是 LINE userId（認領後才有）；沒綁 LINE 的是「預設名字」。
- `items` jsonb：`[{id, name, amount, payerId, sharerIds[], at, currency, rate, note?, cat?}]`。**每筆 = 一個人先付、分給某些人**（不再拆獨立 payments 層）。
- `adjustments` jsonb：服務費/折扣 `[{id, name, kind:'pct'|'amt', value, sign}]`。
- `settlements` jsonb：`{"from>to": {paid, confirmed}}`（相容舊的字串陣列＝視為已付已確認）。
- `transfers` jsonb：實際轉帳/還款紀錄 `[{id, from, to, amount, note?}]`。
- `history` jsonb：編輯紀錄 `[{ts, by, byName, action}]`（上限 200）。

其他表：`app_users`(uid, joined_at 元老判定)、`referrals`(邀請歸因)、`user_prefs`(排序+精選徽章)、`rate_limits`、`banned_terms`、`reports`。詳見 `03-backend.md`。

## 身分模型
- **owner**＝建立者（`g_create` 時的第一位成員，`owner_id`）。權限最高（刪整本、合併/移除成員、改結算狀態）。
- **member**＝在 `participants` 且有 `uid`，或 owner。可協作編輯。
- **認領**：沒綁 LINE 的「預設名字」可被某人用 `g_claim_by_slug` 綁定（一人一名、先搶先贏、不能搶已認領）。
- **slug = capability**：持有短連結者可讀/可加入（沿用邀請模型）。
- 前端 `iAmOwner()`：優先 `current.ownerId===MY_UID`，否則退回 `members[0]`。

## 不可違反的核心原則
1. 計算只走 `computeSplit`（淨值法），不口算。
2. 身分制（各看各的）、隱私 by default。
3. 單一檔案前端、無框架。
4. 後端全 RLS 鎖、只走 `g_*` RPC。
5. 新增欄位/RPC 參數用 `default null` 等非破壞做法，舊呼叫仍可用。
