-- ============================================================
-- AA 分帳 — Supabase schema（公開版資料結構）
-- 用法：Supabase Dashboard → SQL Editor → 貼上整段 → Run。
-- 認證設計：LINE id token 由 Edge Function 驗證後，換發 Supabase JWT，
--           其 sub = app_users.id（uuid），讓 auth.uid() 正常運作。
-- 協作設計：聚會 id 不可猜 + share_token = 「知道連結的人」能讀寫（capability）。
-- ============================================================

create extension if not exists pgcrypto;

-- 1) 使用者：LINE userId ↔ 內部 uuid
create table if not exists app_users (
  id            uuid primary key default gen_random_uuid(),
  line_user_id  text unique not null,
  display_name  text,
  picture_url   text,
  created_at    timestamptz not null default now()
);

-- 2) 聚會：header 欄位可查詢，巢狀資料放 jsonb（一場聚會原子讀寫）
create table if not exists gatherings (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references app_users(id) on delete cascade,
  share_token   text not null default encode(gen_random_bytes(16), 'hex'),
  title         text,
  event_date    date,
  currency      text not null default 'TWD',
  status        text not null default 'open',          -- open | settled
  participants  jsonb not null default '[]'::jsonb,    -- [{id,name,lineUserId?}]
  items         jsonb not null default '[]'::jsonb,    -- [{id,name,amount,sharerIds[]}]
  payments      jsonb not null default '[]'::jsonb,    -- [{id,payerId,amount,isFull}]
  settlements   jsonb not null default '[]'::jsonb,    -- 之後做「誰已還錢」
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists gatherings_owner_idx on gatherings(owner_id);

-- updated_at 自動更新
create or replace function touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;
drop trigger if exists trg_gatherings_touch on gatherings;
create trigger trg_gatherings_touch before update on gatherings
  for each row execute function touch_updated_at();

-- 3) RLS：直接存取僅限 owner（auth.uid()）；協作者走下方 RPC
alter table app_users  enable row level security;
alter table gatherings enable row level security;

drop policy if exists "owner reads own user row" on app_users;
create policy "owner reads own user row" on app_users
  for select using (id = auth.uid());

drop policy if exists "owner full access" on gatherings;
create policy "owner full access" on gatherings
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- 4) 協作 RPC（SECURITY DEFINER：用 id + share_token 當連結鑰匙，繞過 RLS）
create or replace function get_gathering(p_id uuid, p_token text)
returns gatherings language sql security definer set search_path = public as $$
  select * from gatherings where id = p_id and share_token = p_token;
$$;

create or replace function save_gathering(
  p_id uuid, p_token text,
  p_title text, p_event_date date, p_currency text, p_status text,
  p_participants jsonb, p_items jsonb, p_payments jsonb, p_settlements jsonb
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
    payments     = coalesce(p_payments, payments),
    settlements  = coalesce(p_settlements, settlements)
  where id = p_id and share_token = p_token
  returning * into g;
  if not found then raise exception 'invalid gathering id or token'; end if;
  return g;
end; $$;

grant execute on function get_gathering(uuid, text) to anon, authenticated;
grant execute on function save_gathering(uuid, text, text, date, text, text, jsonb, jsonb, jsonb, jsonb) to anon, authenticated;
