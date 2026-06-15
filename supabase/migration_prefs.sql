-- ============================================================
-- AA 分帳 — 個人偏好（跨裝置排序）migration — 已部署版（2026-06-16）
-- 記每位使用者的首頁帳本排序，讓拖移順序跟著帳號跨裝置同步。
-- RLS 全鎖，只走帶 LINE access token 的 SECURITY DEFINER RPC（依 line_uid 綁本人）。
-- 用法：Supabase SQL Editor 貼上 → Run。
-- ============================================================

create table if not exists user_prefs (
  uid text primary key,
  gathering_order jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);
alter table user_prefs enable row level security;
revoke all on table user_prefs from anon, authenticated;

create or replace function g_get_prefs(p_access_token text)
returns jsonb language plpgsql security definer set search_path=public, extensions as $$
declare v_uid text; o jsonb;
begin
  v_uid := line_uid(p_access_token);
  if v_uid is null then raise exception 'unauthorized'; end if;
  select gathering_order into o from user_prefs where uid = v_uid;
  return coalesce(o, '[]'::jsonb);
end; $$;

create or replace function g_set_order(p_access_token text, p_order jsonb)
returns void language plpgsql security definer set search_path=public, extensions as $$
declare v_uid text;
begin
  v_uid := line_uid(p_access_token);
  if v_uid is null then raise exception 'unauthorized'; end if;
  insert into user_prefs(uid, gathering_order, updated_at) values (v_uid, coalesce(p_order,'[]'::jsonb), now())
  on conflict (uid) do update set gathering_order=excluded.gathering_order, updated_at=now();
end; $$;

grant execute on function g_get_prefs(text) to anon, authenticated;
grant execute on function g_set_order(text, jsonb) to anon, authenticated;
