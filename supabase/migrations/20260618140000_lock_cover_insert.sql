-- ============================================================
-- AA 分帳 — 關閉 covers bucket 的 anon 直接上傳（2026-06-18）
-- 上傳一律改走 upload-url Edge Function（驗 LINE 身分、封面再驗成員）發的「簽名上傳網址」，
-- 簽名上傳由 service role 授權、不受此 RLS 限制，所以正常上傳不受影響。
-- 公開讀（covers read）保留。
-- 注意：GitHub Pages + LINE 內快取，舊版前端（仍走 anon 直接上傳）在快取更新前會上傳失敗；
--       若要臨時回退，重建 "covers insert" policy 即可。
-- ============================================================

drop policy if exists "covers insert" on storage.objects;
