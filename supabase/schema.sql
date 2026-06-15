-- ============================================================
-- ⚠️ 已淘汰（HISTORICAL）：本檔的四個 capability RPC（create/get/save/delete_gathering）
--    已於 2026-06-15 DROP（見 migration_drop_old.sql）。線上實際存取一律走身分制
--    g_* RPC（見 schema_identity.sql + migration_slug.sql + migration_claim.sql）。
--    本檔保留的是 gatherings 資料表結構與當初的建表/RLS，供參考；勿再重跑下方函式段。
-- ============================================================
-- AA 分帳 — Supabase schema（Stage 2a：分享連結協作，尚未接 LINE 登入）
-- 用法：Supabase Dashboard → SQL Editor → 貼上整段 → Run。
-- 存取模型：聚會 id 不可猜（uuid）+ share_token = 「知道連結的人」可讀寫（capability）。
--           資料表 RLS 全鎖（直接查表一律拒絕），所有存取只能走下方 RPC。
-- LINE 登入 / 擁有權（owner）留待 Stage 2b 再疊上（owner_id 欄位已預留）。
-- ============================================================

create extension if not exists pgcrypto;

create table if not exists gatherings (
  id           uuid primary key default gen_random_uuid(),
  share_token  text not null default encode(gen_random_bytes(16), 'hex'),
  owner_id     text,                                   -- 預留：Stage 2b 接 LINE userId
  title        text,
  event_date   date,
  currency     text not null default 'TWD',
  status       text not null default 'open',           -- open | settled
  participants jsonb not null default '[]'::jsonb,      -- [{id,name,lineUserId?}]
  items        jsonb not null default '[]'::jsonb,      -- [{id,name,amount,payerId,sharerIds[]}]
  adjustments  jsonb not null default '[]'::jsonb,      -- [{id,name,kind,value,sign}]
  settlements  jsonb not null default '[]'::jsonb,      -- 之後做「誰已還錢」
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- updated_at 自動更新
create or replace function touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;
drop trigger if exists trg_gatherings_touch on gatherings;
create trigger trg_gatherings_touch before update on gatherings
  for each row execute function touch_updated_at();

-- RLS 全鎖：直接查表一律拒絕，只能透過下方 SECURITY DEFINER RPC 存取
alter table gatherings enable row level security;

-- 縱深防禦：撤掉資料表本身的權限，連 Supabase 自動產生的 REST API 都查不到這張表，
-- 只剩下方 RPC（SECURITY DEFINER、需正確 id+token）這一條存取路徑。
revoke all on table gatherings from anon, authenticated;

-- 建立聚會：回傳 id + share_token（呼叫端存進本機索引，當「我的聚會」清單）
create or replace function create_gathering(p_title text, p_event_date date, p_currency text)
returns gatherings language plpgsql security definer set search_path = public as $$
declare g gatherings;
begin
  insert into gatherings(title, event_date, currency)
  values (p_title, p_event_date, coalesce(p_currency, 'TWD'))
  returning * into g;
  return g;
end; $$;

-- 讀取：要 id + 正確 token
create or replace function get_gathering(p_id uuid, p_token text)
returns gatherings language sql security definer set search_path = public as $$
  select * from gatherings where id = p_id and share_token = p_token;
$$;

-- 整場覆寫（協作者編輯後存回）：要 id + 正確 token
create or replace function save_gathering(
  p_id uuid, p_token text,
  p_title text, p_event_date date, p_currency text, p_status text,
  p_participants jsonb, p_items jsonb, p_adjustments jsonb, p_settlements jsonb
) returns gatherings language plpgsql security definer set search_path = public as $$
declare g gatherings;
begin
  update gatherings set
    title        = p_title,
    event_date   = p_event_date,
    currency     = coalesce(p_currency, 'TWD'),
    status       = coalesce(p_status, 'open'),
    participants = coalesce(p_participants, participants),
    items        = coalesce(p_items, items),
    adjustments  = coalesce(p_adjustments, adjustments),
    settlements  = coalesce(p_settlements, settlements)
  where id = p_id and share_token = p_token
  returning * into g;
  if not found then raise exception 'invalid gathering id or token'; end if;
  return g;
end; $$;

-- 刪除：要 id + 正確 token
create or replace function delete_gathering(p_id uuid, p_token text)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from gatherings where id = p_id and share_token = p_token;
end; $$;

grant execute on function create_gathering(text, date, text)                                              to anon, authenticated;
grant execute on function get_gathering(uuid, text)                                                       to anon, authenticated;
grant execute on function save_gathering(uuid, text, text, date, text, text, jsonb, jsonb, jsonb, jsonb)  to anon, authenticated;
grant execute on function delete_gathering(uuid, text)                                                    to anon, authenticated;
