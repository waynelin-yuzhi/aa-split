# 05 · 工作流程（SOP）

## 開工前
- 先讀本專案 `CLAUDE.md`，動到哪塊讀對應 `0X` 細則。
- 多裝置協作：動 code 前 `git pull`（避免覆蓋）。

## 改前端
1. 編輯 `index.html`。
2. `preview_start`（port 8123）→ 用 **`?demo=1`** 跑真畫面驗證（免 LINE 登入）。
3. `preview_console_logs`(error) 確認無錯；`preview_screenshot` 截圖驗收（手機尺寸可 `preview_resize` 390×720）。
4. 涉及登入/邀請/presence/上傳 happy-path 的，只能 LINE 真機測（見下）。

## 改後端
1. 寫 `supabase/migrations/<timestamp>_name.sql`（檔頭寫清楚改什麼、為什麼）。
2. `~/.local/bin/supabase db push`（`db push` 成功＝Postgres 已驗證語法/函式體）。
3. 驗證：REST `curl .../rest/v1/rpc/<fn>`（壞 token 應回 unauthorized/401；簽名應一致）；Edge Function 用 `supabase functions deploy <name> --no-verify-jwt`。

## 部署
- `git commit` + `git push`（GitHub Pages 自動上線）。commit message 結尾加 `Co-Authored-By: Claude ...` trailer。
- 在預設分支上要動 code 前先開分支（除非 Wayne 指定直接 main；本專案目前直接推 main）。

## 版本號 + 更新紀錄（鐵則）
- **使用者看得到的改動上線 → bump `APP_VERSION` + `CHANGELOG` 加一筆**（白話、簡短，最新在最上）。
- 版本規則：新功能/明顯行為改變→中位數+1（v1.**1**.0）；小修正/版面優化→末位+1（v1.0.**2**）；純內部無感→不跳、併下次。
- 它是**手動維護**，交付前順手更新，別漏（這是有踩過的點）。

## 快取
- GitHub Pages HTML 約 10 分鐘 + LINE in-app 瀏覽器快取 → 推版後常看到舊版。提醒 Wayne：**完全關閉 LIFF 視窗 + 等幾分鐘再開**。

## 只能 LINE 真機測的清單
登入流程、邀請/加入/認領、即時在線 presence、**封面/頭像上傳的成功路徑**（簽名上傳需真 token）、shareTargetPicker 分享、跨裝置同步、推播相關、多人協作互動、徽章歸因。preview 只能驗到「函式正常、版面、單機計算」。

## 確認類動作（沿用全域偏好）
- 可逆/本地/讀取：直接做。
- 刪除/覆寫/批次改/外部動作（發信、上傳、推送、付費）：**先確認**。
- 不要編造檔名/API/路徑——查證或問。

## 上線前安全清單（狀態）
- ✅ 已完成：XSS 全面稽核、後端授權/RLS、結算防竄改、帳號刪除+隱私政策/PDPA、流量限制、內容審核（文字黑名單+檢舉）、上傳身分把關（Edge Function 簽名上傳）、封面壓縮。
- ⬜ 剩項（可選強化）：舊封面 service-role 清理 job、圖片 NSFW 偵測（需 vision API）、檢舉後台 UI、`banned_terms` 擴充。

## 記憶 vs 規範
- 跨 session 的「正在做什麼/待辦/踩雷」放 Claude 記憶（`aa_split_app.md`）。
- 「這個系統永遠要遵守的規則」放這份 repo 規範（版控、跟著專案走、換裝置/換 AI 都一致）。兩者互補，別混。
