# 「欸，算一下！」/ Let's Split — 專案規範

朋友間**單次聚會** AA 分帳的 LINE LIFF web app（不是 Splitwise 式累積帳本）。
單一 `index.html`（純前端）+ Supabase（Postgres / RPC / Storage / Edge Function）+ LINE LIFF + GitHub Pages。

這份 `CLAUDE.md` 只放**鐵則 + 索引**。動到某一塊前，先讀對應的細則（在 `.claude/conventions/`）。

## 鐵則（不可違反）

1. **計算永遠走 `computeSplit`（aa.py 的忠實移植）淨值法**——絕不口算、絕不用「欠 A 減欠 B」。改計算邏輯前必對照參考案例、六道驗算要過。→ `02-calc.md`
2. **身分制**：LINE 登入、各看各的、被邀請才加入；不是一人幫所有人輸入。
3. **隱私 by default**：最小蒐集、capability token、token 放 hash、noindex、HTTPS；新功能預設就要想「會不會被窺探」。
4. **後端資料表全 RLS 鎖死 + revoke**，只能走 `SECURITY DEFINER` 的 `g_*` RPC（`line_uid` 驗身分）。→ `03-backend.md`
5. **所有使用者輸入插進畫面必過 `esc()`**；圖片網址過 `validPicUrl`/`parseCover`；對話框用自家 `uiConfirm/uiPrompt`（不用原生 confirm/alert，會露網域）。→ `04-frontend-style.md`
6. **單一 `index.html` 架構**，不要拆檔、不要引入框架/建置流程。
7. **後端改動走 migration**：`supabase/migrations/<timestamp>_name.sql` → `supabase db push`。→ `03-backend.md`、`05-process.md`
8. **使用者看得到的改動上線，就 bump `APP_VERSION` + 加一筆 `CHANGELOG`**（功能→中位數+1；修正/優化→末位+1）。→ `05-process.md`
9. **動 UI 結構時**（`.fab` / `.btn.block.calcbtn` / `.quickbar` 等），同步檢查 `ONBOARD_STEPS` 的選擇器；範例帳本動作用 `IS_DEMO` 擋。→ `04-frontend-style.md`
10. **可逆/本地/讀取**直接做；**刪除/覆寫/批次/外部動作（發信、上傳、推送、付費）先確認**。
11. 預覽驗證用 `?demo=1`（免登入跑真畫面）；推版後提醒**快取**（GitHub Pages + LINE in-app）。→ `05-process.md`

## 分類規範索引（`.claude/conventions/`）

- **`01-core.md`** — 系統定位、品牌、技術棧、資料模型、身分模型、公開識別值、不可違反原則。
- **`02-calc.md`** — 分帳計算與六道驗算：淨值法、最少轉帳、零頭、多幣別、服務費；`computeSplit` 介面與不變量。
- **`03-backend.md`** — Supabase：RLS、`g_*` RPC 與權限模型、migration 流程、Edge Function、Storage、限流、內容審核、非破壞慣例。
- **`04-frontend-style.md`** — 前端架構、XSS 安全、UI 元件慣例、色彩變數與主題、品牌語氣、命名、範例帳本/引導維護。
- **`05-process.md`** — 工作流程：開工前、前後端改動驗證、部署、版本/更新紀錄、快取、LINE 真機測試清單、上線安全清單。

## 公開識別值（非機密，前端本來就有）

- LIFF_ID：`2010401423-LXxOHE2H`
- Supabase：`https://ytlakkxrbookftluulbo.supabase.co`、publishable key 在 `index.html`
- Repo / 站台：`waynelin-yuzhi/aa-split`、`https://waynelin-yuzhi.github.io/aa-split/`
- 本機預覽：port `8123`（`?demo=1` 免登入）
- **機密（service key / DB 密碼 / channel secret）絕不進聊天或 repo**；DB 密碼在 `~/.zshenv` 的 `SUPABASE_DB_PASSWORD`。

## 回覆風格（沿用 Wayne 全域偏好）

繁體中文（台灣用語）、技術名詞保留英文；簡單問題簡答、複雜任務再展開；不要每段自動加「總結」；命名清楚就好，只在「為什麼這樣做」不明顯時加註。
