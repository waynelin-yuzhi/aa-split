# 03 · 後端（Supabase）

## 專案
- ref `ytlakkxrbookftluulbo`、URL `https://ytlakkxrbookftluulbo.supabase.co`、Region Tokyo。
- 前端用 **publishable（anon）key**（公開、在 `index.html`）。
- **機密絕不外流**：service_role key / DB 密碼 / LINE channel secret 不進聊天、不進 repo。DB 密碼在 `~/.zshenv` 的 `SUPABASE_DB_PASSWORD`。

## 安全模型（鐵則）
- **每張資料表 `enable row level security` + `revoke all ... from anon, authenticated`**。連 PostgREST 自動 API 都查不到表。
- **唯一存取路徑＝`SECURITY DEFINER` 的 `g_*` RPC**，每支開頭用 `line_uid(p_access_token)` 換已驗證 LINE userId（打 `https://api.line.me/oauth2/v2.1/userinfo`），驗不過 raise `unauthorized`。
- 函式都帶 `set search_path = public, extensions`。
- 舊的純 token capability RPC（create/get/save/delete_gathering）**已 DROP**，不可復活（那是免身分後門）。

## 權限模型
- **讀**：`g_get` 成員或持正確 share_token 可讀；`g_list` 只回自己有份的；`g_get_by_slug` 持 slug 可讀。
- **寫**：`g_save` 需成員；但**結算狀態（settlements）只有 owner 能透過 g_save 改**，其他成員一律沿用 DB 現值——結算只能走 `g_settle`（逐筆驗付/收款人身分）；**非 owner 不能移除既有成員**（送來名單漏掉的依 id 自動補回）。
- **結算** `g_settle(token,id,from,to,op)`：付款方才能 `mark_paid/unmark_paid`、收款方才能 `confirm/unconfirm/received`、虛擬成員由 owner 代記；原子寫單一 key + 附 history。
- **刪整本** `g_delete`：只有 owner。
- **合併/移除成員**：前端限 owner（`iAmOwner`），後端 g_save 也擋非 owner 的移除。
- **帳號刪除** `g_delete_account`：匿名化本人在所有帳本的成員（移 uid/pic/payInfo、名改「已刪除的成員」、留 id 保分帳）、清 owner_id、刪 referrals/user_prefs/app_users 本人列、盡力刪頭像檔。

## 主要 RPC
`g_list / g_create / g_get / g_get_by_slug / g_join / g_join_by_slug / g_claim_by_slug / g_save / g_delete / g_settle / g_set_fastpay / g_get_prefs / g_set_order / g_set_featured / g_record_referral / g_my_badges / g_member_badges / g_report / g_delete_account`。
helper：`line_uid / _is_member / _is_elder / _elder_rank / _touch_user / _rate_ok / _check_content`。

## 徽章 / 元老
- 元老＝**最早加入前 30 名**（`app_users.joined_at`，`_is_elder` / `_elder_rank` 固定排序）。
- 徽章分級（銅/銀/金）：`g_member_badges` 回各公開徽章 tier + 第一順位 top + 一起分帳 mutual 次數；**只回布林/關係數，不外露別人的總筆數/邀請數/花費**（隱私）。
- 秒付俠：`gatherings.fast_pay_uid` + `g_set_fastpay`（first-wins）。

## Storage（covers bucket）
- public 讀；限 image jpeg/png/webp；單檔上限 **512KB**。
- **anon 直接上傳已關閉**。上傳一律走 `upload-url` Edge Function 發的簽名上傳網址 → `uploadToSignedUrl`。
- 封面路徑 `<gid>/<rand>.jpg`、頭像 `avatars/<uid>/<rand>.jpg`。前端上傳前 `downscaleImage` 縮圖＋重編碼（去 EXIF/GPS）。

## Edge Function
- `supabase/functions/upload-url/index.ts`：驗 LINE token（封面再用 service role 查成員）→ `createSignedUploadUrl`。
- 部署：`supabase functions deploy upload-url --no-verify-jwt`（Docker 沒開也能 deploy，遠端 bundling）。

## 限流 + 內容審核
- `_rate_ok(uid,action,max,window)` + `rate_limits` 表，套在 g_create(60/時)、g_join·join_by_slug·claim_by_slug(120/時)、g_report·g_delete_account。**g_save 不限**（不影響編輯手感）。
- `banned_terms` 表（廣告/詐騙字）+ `_check_content` 在 g_create/g_save 檢查標題+品名/備註/調整名，命中 raise `content rejected`。Wayne 可自行增刪字詞。
- `reports` 表 + `g_report`：使用者檢舉，後台（Supabase）人工審。

## Migration 流程
- 新 migration 放 `supabase/migrations/<timestamp>_name.sql` → `~/.local/bin/supabase db push`。
- CLI 在 `~/.local/bin/`（`supabase` + `supabase-go` 兩支都要）、已 login + link。
- **舊的手寫 `supabase/migration_*.sql`（根目錄、非 migrations/）不被 CLI 追蹤**，只當歷史參考；同名函式以最新一次 `create or replace` 為準。
- **新增欄位/參數用 `default null`、向後相容**（舊前端少帶參數仍可解析）。
