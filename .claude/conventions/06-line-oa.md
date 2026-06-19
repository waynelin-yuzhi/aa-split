# 06 · LINE 官方帳號（OA）

## 現況
- OA：**「欸！算一下」**，basicId `@108yglrx`，Messaging API 已啟用（與 LIFF 同 Provider「Check please」）。chatMode = bot。
- **圖文選單已上線**（2026-06-19）：richMenuId `richmenu-4887a5f060ebbb8afefd92651ff1ea75`，3 格指向 LIFF：
  - 開始分帳 → `?go=new`、我的帳本 → `?go=list`、揪朋友 → `?go=share`
- 前端 boot 已接 `?go=new/list/share`（從選單點進來直接落到對應動作，優先於首次引導；無 gid 時才作用）。
- 底圖產生器：`_richmenu/richmenu.html`（canvas 2500×843、用 App 同款薄荷 SVG 圖示、匯出精準尺寸 PNG）。改選單文字/圖示就改它、重新產圖、重新上傳。

## 設定/更新選單的完整指令與踩雷
走全域 skill **`line-oa-richmenu`**（含 token 換視窗會掉、多行貼卡 dquote、空 POST 要 `-d ''` 補 411 等實測雷）。aa-split 的值：LIFF_ID `2010401423-LXxOHE2H`、底圖 `_richmenu/richmenu.html` 產出。
- token 是機密，放 LINE Developers Console 自取、不進 repo/聊天；跑指令時留在本機終端機。

## 還沒做（下一步 OA 方向）
- **群組綁帳本 + 群組推播**：OA 加進 LINE 群組 → 綁一本帳 → 群裡推「有人記了一筆/已結清」。需 **webhook**（收 join/message/postback 事件）→ 可用 **Supabase Edge Function**（見 `03-backend.md`）當 webhook，token/secret 放 Edge Function 環境變數（`supabase secrets set`），**不進 repo**。
- 1:1 推播提醒（結清/催款/月報）：需對方加好友 + push API，易騷擾，緩做。
