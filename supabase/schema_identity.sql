-- ============================================================
-- AA 分帳 — 身分制 migration（Splitwise 式）
-- 在現有 gatherings 表上「加掛」身分驗證與新 RPC（不砍舊的，舊版仍可用）。
-- 身分驗證：用 LINE access token 打 LINE userinfo 端點 → 已驗證 userId（sub）。
--           不需 channel id / secret。
-- 沿用既有欄位：owner_id（存 owner 的 LINE userId）、participants（[{id,name,uid?}]）。
-- 用法：Supabase SQL Editor 貼上 → Run。
-- ============================================================

create extension if not exists pgcrypto;
create extension if not exists http with schema extensions;

-- 加速「我有份的聚會」查詢
create index if not exists gatherings_participants_gin on gatherings using gin (participants);

-- 用 LINE access token 換已驗證 userId（驗不過回 null）
create or replace function line_uid(p_token text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare r jsonb;
begin
  if p_token is null or length(p_token) < 10 then return null; end if;
  select (content::jsonb) into r
  from extensions.http((
    'GET',
    'https://api.line.me/oauth2/v2.1/userinfo',
    array[extensions.http_header('Authorization', 'Bearer ' || p_token)],
    null, null)::extensions.http_request);
  return r->>'sub';
exception when others then
  return null;
end; $$;

-- 是否為該聚會成員（owner 或 participants 內含我的 uid）
create or replace function _is_member(g gatherings, p_uid text)
returns boolean language sql immutable as $$
  select p_uid is not null and (
    g.owner_id = p_uid
    or g.participants @> jsonb_build_array(jsonb_build_object('uid', p_uid))
  );
$$;

-- 我的聚會清單（只回我有份的）
create or replace function list_my_gatherings(p_access_token text)
returns setof gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text;
begin
  uid := line_uid(p_access_token);
  if uid is null then raise exception 'unauthorized'; end if;
  return query
    select * from gatherings g
    where g.owner_id = uid
       or g.participants @> jsonb_build_array(jsonb_build_object('uid', uid))
    order by g.updated_at desc;
end; $$;

-- 建立：我＝owner＋第一位成員
create or replace function create_gathering(
  p_access_token text, p_title text, p_event_date date, p_currency text,
  p_my_name text, p_my_member_id text)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings;
begin
  uid := line_uid(p_access_token);
  if uid is null then raise exception 'unauthorized'; end if;
  insert into gatherings(owner_id, title, event_date, currency, participants)
  values (uid, p_title, p_event_date, coalesce(p_currency,'TWD'),
          jsonb_build_array(jsonb_build_object('id', p_my_member_id, 'name', p_my_name, 'uid', uid)))
  returning * into g;
  return g;
end; $$;

-- 讀取：成員可讀；或持有正確 share_token（邀請剛點開、還沒加入）可讀
create or replace function get_gathering(p_id uuid, p_token text, p_access_token text)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings;
begin
  select * into g from gatherings where id = p_id;
  if not found then return null; end if;
  uid := line_uid(p_access_token);
  if _is_member(g, uid) then return g; end if;
  if p_token is not null and g.share_token = p_token then return g; end if;
  raise exception 'forbidden';
end; $$;

-- 加入（邀請流程）：正確 token + 已登入 → 把我加進 participants
create or replace function join_gathering(
  p_id uuid, p_token text, p_access_token text, p_my_name text, p_my_member_id text)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings;
begin
  uid := line_uid(p_access_token);
  if uid is null then raise exception 'unauthorized'; end if;
  select * into g from gatherings where id = p_id and share_token = p_token;
  if not found then raise exception 'invalid invite'; end if;
  if not (g.participants @> jsonb_build_array(jsonb_build_object('uid', uid))) then
    update gatherings
      set participants = participants || jsonb_build_array(jsonb_build_object('id', p_my_member_id, 'name', p_my_name, 'uid', uid))
      where id = p_id returning * into g;
  end if;
  return g;
end; $$;

-- 存：僅成員可存
create or replace function save_gathering(
  p_id uuid, p_access_token text, p_title text, p_event_date date, p_currency text, p_status text,
  p_participants jsonb, p_items jsonb, p_adjustments jsonb, p_settlements jsonb)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings;
begin
  select * into g from gatherings where id = p_id;
  if not found then raise exception 'not found'; end if;
  uid := line_uid(p_access_token);
  if not _is_member(g, uid) then raise exception 'forbidden'; end if;
  update gatherings set
    title = p_title, event_date = p_event_date, currency = coalesce(p_currency,'TWD'),
    status = coalesce(p_status,'open'),
    participants = coalesce(p_participants, participants),
    items = coalesce(p_items, items),
    adjustments = coalesce(p_adjustments, adjustments),
    settlements = coalesce(p_settlements, settlements)
    where id = p_id returning * into g;
  return g;
end; $$;

-- 刪：僅 owner
create or replace function delete_gathering(p_id uuid, p_access_token text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings;
begin
  select * into g from gatherings where id = p_id;
  if not found then return; end if;
  uid := line_uid(p_access_token);
  if g.owner_id is distinct from uid then raise exception 'forbidden'; end if;
  delete from gatherings where id = p_id;
end; $$;

grant execute on function list_my_gatherings(text)                                                          to anon, authenticated;
grant execute on function create_gathering(text, text, date, text, text, text)                              to anon, authenticated;
grant execute on function get_gathering(uuid, text, text)                                                   to anon, authenticated;
grant execute on function join_gathering(uuid, text, text, text, text)                                      to anon, authenticated;
grant execute on function save_gathering(uuid, text, text, date, text, text, jsonb, jsonb, jsonb, jsonb)    to anon, authenticated;
grant execute on function delete_gathering(uuid, text)                                                      to anon, authenticated;
