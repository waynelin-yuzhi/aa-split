-- ============================================================
-- AA 分帳 — 元老＝「全 App 最早加入的前 30 名」（2026-06-16）
-- 取代原本「9 月前加入」的時間規則。
-- app_users 記每個 LINE uid 的首次加入時間（回填現有資料、之後新使用者首次呼叫時補記），
-- 前 30 名（joined_at 最早、平手用 uid）永久是元老、固定不變。
-- 第一支用 Supabase CLI 部署的 migration（supabase db push）。
-- ============================================================

create table if not exists app_users (
  uid text primary key,
  joined_at timestamptz not null default now()
);
alter table app_users enable row level security;
revoke all on table app_users from anon, authenticated;

-- 回填：每個 uid 取最早出現時間（建/被加入帳本、被邀請）
insert into app_users(uid, joined_at)
select uid, min(ts) as joined_at from (
  select owner_id as uid, created_at as ts from gatherings where owner_id is not null
  union all
  select (p->>'uid') as uid, g.created_at as ts
    from gatherings g cross join lateral jsonb_array_elements(g.participants) p
    where p->>'uid' is not null
  union all
  select invitee_uid as uid, at as ts from referrals
) x
where uid is not null
group by uid
on conflict (uid) do update set joined_at = least(app_users.joined_at, excluded.joined_at);

-- 首次加入補記（給之後的新使用者）
create or replace function _touch_user(p_uid text)
returns void language sql security definer set search_path=public, extensions as $$
  insert into app_users(uid) values(p_uid) on conflict (uid) do nothing;
$$;

-- 是否為前 30 名加入（最早 joined_at、平手用 uid 定序，固定）
create or replace function _is_elder(p_uid text)
returns boolean language sql stable security definer set search_path=public, extensions as $$
  select exists(
    select 1 from (select uid from app_users order by joined_at, uid limit 30) e
    where e.uid = p_uid
  );
$$;

-- g_my_badges：補記本人 + 回傳 elder 布林（取代前端 firstSeen<cutoff 判定）
create or replace function g_my_badges(p_access_token text)
returns jsonb language plpgsql security definer set search_path=public, extensions as $$
declare v_uid text; v_invited int; v_was boolean; v_first timestamptz; v_feat jsonb;
begin
  v_uid := line_uid(p_access_token);
  if v_uid is null then raise exception 'unauthorized'; end if;
  perform _touch_user(v_uid);
  select count(*) into v_invited from referrals where inviter_uid = v_uid;
  select exists(select 1 from referrals where invitee_uid = v_uid) into v_was;
  select min(created_at) into v_first from gatherings where owner_id = v_uid;
  select featured_badges into v_feat from user_prefs where uid = v_uid;
  return jsonb_build_object('invited', v_invited, 'wasInvited', v_was, 'firstSeen', v_first,
                            'elder', _is_elder(v_uid),
                            'featured', coalesce(v_feat,'[]'::jsonb));
end; $$;

-- g_member_badges：元老改用前 30 名判定（其餘不變）
create or replace function g_member_badges(p_access_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path=public, extensions as $$
declare
  v_uid text; g gatherings; res jsonb := '[]'::jsonb; m record;
  v_invited int; v_items bigint; v_feat jsonb; v_top text;
  v_elder boolean; v_master boolean; v_king boolean; v_mutual bigint;
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
    select coalesce(sum(jsonb_array_length(coalesce(items,'[]'::jsonb))),0) into v_items
      from gatherings
      where owner_id = m.muid or participants @> jsonb_build_array(jsonb_build_object('uid', m.muid));
    select featured_badges into v_feat from user_prefs where uid = m.muid;

    v_elder  := _is_elder(m.muid);
    v_master := (v_items >= MASTER_ITEMS);
    v_king   := (v_invited >= KING_INVITES);

    v_top := null;
    if v_feat is not null and jsonb_typeof(v_feat) = 'array' then
      select t.k into v_top
      from jsonb_array_elements_text(v_feat) with ordinality as t(k, ord)
      where (t.k='elder' and v_elder) or (t.k='master' and v_master) or (t.k='king' and v_king)
      order by t.ord limit 1;
    end if;

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
