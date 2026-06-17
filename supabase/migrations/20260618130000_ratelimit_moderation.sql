-- ============================================================
-- AA 分帳 — 流量限制 + 內容審核（2026-06-18）— 上線前整備
-- A) 流量限制：通用 _rate_ok(uid,action,max,window) 計數器，套在「會新增資料」的 RPC
--    （建立帳本、加入、認領、檢舉、刪帳號），擋自動化灌量。一般編輯(g_save)不限、不影響手感。
-- B) 內容審核：
--    (1) 預防＝banned_terms 黑名單（以「廣告/詐騙」字樣為主，誤判率低），g_create/g_save
--        檢查標題＋品名/備註/調整名，命中就擋下（content rejected）。Wayne 可自行增刪字詞。
--    (2) 反應＝reports 檢舉表 + g_report，使用者可檢舉帳本，Wayne 在 Supabase 後台審。
--    註：圖片 NSFF 偵測需 vision API（另計），本批先做文字＋檢舉＋上傳身分把關(Edge Function)。
-- ============================================================

-- ---------- A) 流量限制 ----------
create table if not exists rate_limits (
  uid text not null, action text not null,
  window_start timestamptz not null default now(), count int not null default 0,
  primary key (uid, action)
);
alter table rate_limits enable row level security;
revoke all on table rate_limits from anon, authenticated;

create or replace function _rate_ok(p_uid text, p_action text, p_max int, p_window_secs int)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_start timestamptz; v_count int;
begin
  if p_uid is null then return false; end if;
  select window_start, count into v_start, v_count from rate_limits where uid=p_uid and action=p_action for update;
  if not found then
    insert into rate_limits(uid,action,window_start,count) values(p_uid,p_action,now(),1)
      on conflict (uid,action) do update set window_start=now(), count=1;
    return true;
  end if;
  if now() - v_start > make_interval(secs => p_window_secs) then
    update rate_limits set window_start=now(), count=1 where uid=p_uid and action=p_action;
    return true;
  end if;
  if v_count >= p_max then return false; end if;
  update rate_limits set count=count+1 where uid=p_uid and action=p_action;
  return true;
end; $$;

-- ---------- B1) 內容黑名單 ----------
create table if not exists banned_terms ( term text primary key );
alter table banned_terms enable row level security;
revoke all on table banned_terms from anon, authenticated;
insert into banned_terms(term) values
  ('casino'),('viagra'),('porn'),('博弈'),('賭場'),('線上賭'),('代儲'),('刷單'),
  ('色情'),('援交'),('威而鋼'),('比特幣穩賺'),('usdt代'),('加賴'),('加我賴'),('套利保證')
  on conflict (term) do nothing;

create or replace function _check_content(p_title text, p_items jsonb, p_adjustments jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare blob text; bad text;
begin
  blob := coalesce(p_title,'');
  if p_items is not null and jsonb_typeof(p_items)='array' then
    blob := blob || ' ' || coalesce((select string_agg(coalesce(e->>'name','')||' '||coalesce(e->>'note',''),' ')
                                     from jsonb_array_elements(p_items) e),'');
  end if;
  if p_adjustments is not null and jsonb_typeof(p_adjustments)='array' then
    blob := blob || ' ' || coalesce((select string_agg(coalesce(e->>'name',''),' ') from jsonb_array_elements(p_adjustments) e),'');
  end if;
  select term into bad from banned_terms where blob ilike '%'||term||'%' limit 1;
  if bad is not null then raise exception 'content rejected'; end if;
end; $$;

-- ---------- B2) 檢舉 ----------
create table if not exists reports (
  id uuid primary key default gen_random_uuid(),
  gathering_id uuid, reporter_uid text not null, reason text,
  created_at timestamptz not null default now()
);
alter table reports enable row level security;
revoke all on table reports from anon, authenticated;

create or replace function g_report(p_access_token text, p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path=public, extensions as $$
declare v_uid text;
begin
  v_uid := line_uid(p_access_token);
  if v_uid is null then raise exception 'unauthorized'; end if;
  if not _rate_ok(v_uid,'report',20,3600) then raise exception 'rate limited'; end if;
  insert into reports(gathering_id, reporter_uid, reason) values (p_id, v_uid, left(coalesce(p_reason,''),500));
end; $$;
grant execute on function g_report(text, uuid, text) to anon, authenticated;

-- ---------- 套用到既有 RPC ----------
-- g_create：限流（60/時）＋ 標題審核
create or replace function g_create(p_access_token text, p_title text, p_event_date date, p_currency text, p_my_name text, p_my_member_id text, p_my_pic text default null)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings; begin
  uid := line_uid(p_access_token);
  if uid is null then raise exception 'unauthorized'; end if;
  if not _rate_ok(uid,'create',60,3600) then raise exception 'rate limited'; end if;
  perform _check_content(p_title, '[]'::jsonb, '[]'::jsonb);
  insert into gatherings(owner_id, title, event_date, currency, participants)
  values (uid, p_title, p_event_date, coalesce(p_currency,'TWD'),
          jsonb_build_array(jsonb_build_object('id', p_my_member_id, 'name', p_my_name, 'uid', uid)
            || case when p_my_pic is not null then jsonb_build_object('pic', p_my_pic) else '{}'::jsonb end))
  returning * into g; return g;
end; $$;

-- g_join / g_join_by_slug / g_claim_by_slug：限流（120/時）
create or replace function g_join(p_id uuid, p_token text, p_access_token text, p_my_name text, p_my_member_id text, p_my_pic text default null)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings; begin
  uid := line_uid(p_access_token);
  if uid is null then raise exception 'unauthorized'; end if;
  if not _rate_ok(uid,'join',120,3600) then raise exception 'rate limited'; end if;
  select * into g from gatherings where id = p_id and share_token = p_token;
  if not found then raise exception 'invalid invite'; end if;
  if not (g.participants @> jsonb_build_array(jsonb_build_object('uid', uid))) then
    update gatherings set participants = participants || jsonb_build_array(
        jsonb_build_object('id', p_my_member_id, 'name', p_my_name, 'uid', uid)
          || case when p_my_pic is not null then jsonb_build_object('pic', p_my_pic) else '{}'::jsonb end)
      where id = p_id returning * into g;
  end if;
  return g;
end; $$;

create or replace function g_join_by_slug(p_slug text, p_access_token text, p_my_name text, p_my_member_id text, p_my_pic text default null)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings;
begin
  uid := line_uid(p_access_token);
  if uid is null then raise exception 'unauthorized'; end if;
  if not _rate_ok(uid,'join',120,3600) then raise exception 'rate limited'; end if;
  select * into g from gatherings where slug = p_slug;
  if not found then raise exception 'invalid invite'; end if;
  if not (g.participants @> jsonb_build_array(jsonb_build_object('uid', uid))) then
    update gatherings set participants = participants || jsonb_build_array(
        jsonb_build_object('id', p_my_member_id, 'name', p_my_name, 'uid', uid)
          || case when p_my_pic is not null then jsonb_build_object('pic', p_my_pic) else '{}'::jsonb end)
      where id = g.id returning * into g;
  end if;
  return g;
end; $$;

create or replace function g_claim_by_slug(p_slug text, p_access_token text, p_member_id text, p_my_pic text default null)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings; target jsonb;
begin
  uid := line_uid(p_access_token);
  if uid is null then raise exception 'unauthorized'; end if;
  if not _rate_ok(uid,'join',120,3600) then raise exception 'rate limited'; end if;
  select * into g from gatherings where slug = p_slug;
  if not found then raise exception 'invalid invite'; end if;
  if g.participants @> jsonb_build_array(jsonb_build_object('uid', uid)) then return g; end if;
  select elem into target from jsonb_array_elements(g.participants) elem where elem->>'id' = p_member_id;
  if target is null then raise exception 'member not found'; end if;
  if (target ? 'uid') and (target->>'uid') is not null and (target->>'uid') <> uid then
    raise exception 'already claimed';
  end if;
  update gatherings
  set participants = (
    select jsonb_agg(
      case when (elem->>'id') = p_member_id
        then elem || jsonb_build_object('uid', uid)
                  || case when p_my_pic is not null then jsonb_build_object('pic', p_my_pic) else '{}'::jsonb end
        else elem end)
    from jsonb_array_elements(participants) elem)
  where id = g.id
  returning * into g;
  return g;
end; $$;

-- g_save：沿用「結算/踢人」權限收緊 + 加內容審核
create or replace function g_save(p_id uuid, p_access_token text, p_title text, p_event_date date, p_currency text, p_status text, p_participants jsonb, p_items jsonb, p_adjustments jsonb, p_settlements jsonb, p_history jsonb default null, p_cover text default null, p_transfers jsonb default null)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings; v_owner boolean; v_parts jsonb; v_setts jsonb;
begin
  select * into g from gatherings where id = p_id;
  if not found then raise exception 'not found'; end if;
  uid := line_uid(p_access_token);
  if not _is_member(g, uid) then raise exception 'forbidden'; end if;
  perform _check_content(p_title, p_items, p_adjustments);
  v_owner := (g.owner_id is not distinct from uid);

  v_setts := case when v_owner then coalesce(p_settlements, g.settlements) else g.settlements end;

  v_parts := coalesce(p_participants, g.participants);
  if not v_owner then
    v_parts := v_parts || coalesce((
      select jsonb_agg(old)
      from jsonb_array_elements(g.participants) old
      where not exists (select 1 from jsonb_array_elements(v_parts) nw where nw->>'id' = old->>'id')
    ), '[]'::jsonb);
  end if;

  update gatherings set
    title=p_title, event_date=p_event_date, currency=coalesce(p_currency,'TWD'), status=coalesce(p_status,'open'),
    participants=v_parts, items=coalesce(p_items,items), adjustments=coalesce(p_adjustments,adjustments),
    settlements=v_setts, history=coalesce(p_history,history), cover=coalesce(p_cover,cover), transfers=coalesce(p_transfers,transfers)
    where id=p_id returning * into g;
  return g;
end; $$;
