# supabase/_legacy — 歷史 SQL（不被 CLI 追蹤）

這裡是**早期手動部署**的 SQL：`schema.sql` / `schema_identity.sql`（基礎建表、`line_uid`、`_is_member`、基礎 `g_*` RPC）與一批 `migration_*.sql`（slug、認領、轉帳、封面、歷史、偏好、邀請、成員臨場感等）。它們在還沒導入 `supabase db push` 流程前，是透過 Supabase SQL Editor（瀏覽器）或早期 CLI 跑上線的。

**現行真相＝`supabase/migrations/`**（timestamp 命名、`supabase db push` 追蹤）。本資料夾的檔案：
- **不**被 `supabase db push` 掃描或重跑。
- 同名函式以最新一次 `create or replace`（多在 `migrations/`）為準。
- 保留作為**歷史參考**，以及目前線上 schema 的**地基**（`migrations/` 只含後期增量）。

## 重現/災難復原注意
因為「地基在這裡、增量在 migrations/」，對**全新資料庫**單跑 `supabase db push` 會缺地基、無法一鍵重建。目前線上 DB 已存在、Supabase 有自動備份，故不急。若日後要達到「全新 DB 一鍵重建」，需把這裡的地基也補成 `migrations/` 最前面的正式 migration（見 `.claude/conventions/05-process.md` 的進階項）。
