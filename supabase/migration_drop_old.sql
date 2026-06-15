-- ============================================================
-- AA 分帳 — 砍舊 capability RPC — 已部署版（2026-06-15）
-- 早期「誰有 id+token 連結就能存取」的純 capability 函式（不驗身分）。
-- 已全面改用身分制 g_* RPC（用 LINE access token 驗證），前端不再呼叫這些，
-- 故 DROP 掉以關閉純 token 的存取後門。
-- 註：只刪函式，不動 gatherings 資料表與資料。
-- 用法：Supabase SQL Editor 貼上 → Run。
-- ============================================================

drop function if exists create_gathering(text, date, text);
drop function if exists get_gathering(uuid, text);
drop function if exists save_gathering(uuid, text, text, date, text, text, jsonb, jsonb, jsonb, jsonb);
drop function if exists delete_gathering(uuid, text);
