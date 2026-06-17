-- ============================================================
-- AA 分帳 — 成員臨場感 + 徽章系統 v2 migration（2026-06-16）
-- 1) 加入帳本時存 LINE 大頭貼：g_create / g_join / g_join_by_slug / g_claim_by_slug
--    各多吃 p_my_pic（預設 null＝非破壞；舊前端少帶一個參數仍可解析）；存進 participant.pic。
-- 2) 徽章精選：user_prefs 加 featured_badges（使用者選最多 3 個放主頁、有順序）；
--    g_set_featured 存；g_my_badges 多回 featured。
-- 3) g_member_badges：同一本帳的成員，回各自「公開」徽章（元老/分帳達人/揪團王）布林、
--    第一順位 top（要真的有解鎖才回）、以及「你跟他一起分帳幾次」mutual。
--    隱私：只回布林與關係數字，不外露別人的邀請數/總筆數/總花費；新朋友(friend) 不對外。
-- 用法：Supabase SQL Editor 貼上 → Run。
-- ============================================================

-- ---------- 1) 大頭貼：participant.pic ----------
-- participant 形狀沿用 {id,name,uid?}，多一個選填 pic。p_my_pic 為 null 時不寫 pic 欄位。

drop function if exists g_create(text,text,date,text,text,text);
create or replace function g_create(p_access_token text, p_title text, p_event_date date, p_currency text, p_my_name text, p_my_member_id text, p_my_pic text default null)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings; begin
  uid := line_uid(p_access_token);
  if uid is null then raise exception 'unauthorized'; end if;
  insert into gatherings(owner_id, title, event_date, currency, participants)
  values (uid, p_title, p_event_date, coalesce(p_currency,'TWD'),
          jsonb_build_array(jsonb_build_object('id', p_my_member_id, 'name', p_my_name, 'uid', uid)
            || case when p_my_pic is not null then jsonb_build_object('pic', p_my_pic) else '{}'::jsonb end))
  returning * into g; return g;
end; $$;
grant execute on function g_create(text,text,date,text,text,text,text) to anon, authenticated;

drop function if exists g_join(uuid,text,text,text,text);
create or replace function g_join(p_id uuid, p_token text, p_access_token text, p_my_name text, p_my_member_id text, p_my_pic text default null)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings; begin
  uid := line_uid(p_access_token);
  if uid is null then raise exception 'unauthorized'; end if;
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
grant execute on function g_join(uuid,text,text,text,text,text) to anon, authenticated;

drop function if exists g_join_by_slug(text,text,text,text);
create or replace function g_join_by_slug(p_slug text, p_access_token text, p_my_name text, p_my_member_id text, p_my_pic text default null)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings;
begin
  uid := line_uid(p_access_token);
  if uid is null then raise exception 'unauthorized'; end if;
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
grant execute on function g_join_by_slug(text,text,text,text,text) to anon, authenticated;

drop function if exists g_claim_by_slug(text,text,text);
create or replace function g_claim_by_slug(p_slug text, p_access_token text, p_member_id text, p_my_pic text default null)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings; target jsonb;
begin
  uid := line_uid(p_access_token);
  if uid is null then raise exception 'unauthorized'; end if;
  select * into g from gatherings where slug = p_slug;
  if not found then raise exception 'invalid invite'; end if;
  if g.participants @> jsonb_build_array(jsonb_build_object('uid', uid)) then
    return g;
  end if;
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
grant execute on function g_claim_by_slug(text,text,text,text) to anon, authenticated;

-- ---------- 2) 徽章精選 ----------
alter table user_prefs add column if not exists featured_badges jsonb not null default '[]'::jsonb;

create or replace function g_set_featured(p_access_token text, p_badges jsonb)
returns void language plpgsql security definer set search_path=public, extensions as $$
declare v_uid text;
begin
  v_uid := line_uid(p_access_token);
  if v_uid is null then raise exception 'unauthorized'; end if;
  insert into user_prefs(uid, featured_badges, updated_at) values (v_uid, coalesce(p_badges,'[]'::jsonb), now())
  on conflict (uid) do update set featured_badges=excluded.featured_badges, updated_at=now();
end; $$;
grant execute on function g_set_featured(text, jsonb) to anon, authenticated;

-- g_my_badges 多回 featured（同簽名 replace，非破壞）
create or replace function g_my_badges(p_access_token text)
returns jsonb language plpgsql security definer set search_path=public, extensions as $$
declare v_uid text; v_invited int; v_was boolean; v_first timestamptz; v_feat jsonb;
begin
  v_uid := line_uid(p_access_token);
  if v_uid is null then raise exception 'unauthorized'; end if;
  select count(*) into v_invited from referrals where inviter_uid = v_uid;
  select exists(select 1 from referrals where invitee_uid = v_uid) into v_was;
  select min(created_at) into v_first from gatherings where owner_id = v_uid;
  select featured_badges into v_feat from user_prefs where uid = v_uid;
  return jsonb_build_object('invited', v_invited, 'wasInvited', v_was, 'firstSeen', v_first,
                            'featured', coalesce(v_feat,'[]'::jsonb));
end; $$;

-- ---------- 3) 同帳本成員的公開徽章 + 第一順位 + 一起分帳次數 ----------
create or replace function g_member_badges(p_access_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path=public, extensions as $$
declare
  v_uid text; g gatherings; res jsonb := '[]'::jsonb; m record;
  v_invited int; v_first timestamptz; v_items bigint; v_feat jsonb; v_top text;
  v_elder boolean; v_master boolean; v_king boolean; v_mutual bigint;
  ELDER_CUTOFF constant date := '2026-09-01';
  MASTER_ITEMS constant int := 20;
  KING_INVITES constant int := 5;
begin
  v_uid := line_uid(p_access_token);
  if v_uid is null then raise exception 'unauthorized'; end if;
  select * into g from gatherings where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not _is_member(g, v_uid) then raise exception 'forbidden'; end if;

  for m in
    select distinct (elem->>'uid') as muid
    from jsonb_array_elements(g.participants) elem
    where elem->>'uid' is not null
  loop
    select count(*) into v_invited from referrals where inviter_uid = m.muid;
    select min(created_at) into v_first from gatherings where owner_id = m.muid;
    select coalesce(sum(jsonb_array_length(coalesce(items,'[]'::jsonb))),0) into v_items
      from gatherings
      where owner_id = m.muid or participants @> jsonb_build_array(jsonb_build_object('uid', m.muid));
    select featured_badges into v_feat from user_prefs where uid = m.muid;

    v_elder  := (v_first is not null and v_first < ELDER_CUTOFF);
    v_master := (v_items >= MASTER_ITEMS);
    v_king   := (v_invited >= KING_INVITES);

    -- 第一順位 top：使用者精選裡、且真的解鎖、且屬於公開徽章者，取最前面那個
    v_top := null;
    if v_feat is not null and jsonb_typeof(v_feat) = 'array' then
      select t.k into v_top
      from jsonb_array_elements_text(v_feat) with ordinality as t(k, ord)
      where (t.k='elder' and v_elder) or (t.k='master' and v_master) or (t.k='king' and v_king)
      order by t.ord limit 1;
    end if;

    -- 我與該成員「一起分帳」幾次（兩人都在內的帳本數）
    select count(*) into v_mutual from gatherings
      where (owner_id = v_uid   or participants @> jsonb_build_array(jsonb_build_object('uid', v_uid)))
        and (owner_id = m.muid  or participants @> jsonb_build_array(jsonb_build_object('uid', m.muid)));

    res := res || jsonb_build_array(jsonb_build_object(
      'uid', m.muid, 'elder', v_elder, 'master', v_master, 'king', v_king,
      'top', v_top, 'mutual', v_mutual));
  end loop;
  return res;
end; $$;
grant execute on function g_member_badges(text, uuid) to anon, authenticated;
