-- ============================================================
-- AA 分帳 — 徽章分級後端 + 秒付俠（2026-06-16）
-- 1) _elder_rank：回傳「最早加入」排名（<=30 才回，否則 null）→ 元老分級(前30/20/10)。
-- 2) g_my_badges 加 elderRank；g_member_badges 回 elder/master/king 的「等級(tier)」+ top/topTier，
--    讓別人（頭像角徽、結算結果卡截圖）看得到你的徽章是第幾級。
-- 3) 秒付俠：gatherings 加 fast_pay_uid（每本帳「第一個把自己該付的付清」的人），
--    g_set_fastpay first-wins（前端偵測誰先付清、後端只在還沒記過時寫入）。
-- ============================================================

-- 元老排名（依 joined_at, uid 排序；非前 30 回 null）
create or replace function _elder_rank(p_uid text)
returns int language sql stable security definer set search_path=public, extensions as $$
  with me as (select joined_at, uid from app_users where uid = p_uid)
  select r from (
    select (select count(*) from app_users a where (a.joined_at, a.uid) < (m.joined_at, m.uid)) + 1 as r
    from me m
  ) x where r <= 30;
$$;

-- g_my_badges：加 elderRank（沿用 elder 布林）
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
                            'elder', _is_elder(v_uid), 'elderRank', _elder_rank(v_uid),
                            'featured', coalesce(v_feat,'[]'::jsonb));
end; $$;

-- g_member_badges：回各公開徽章的等級 + top/topTier
create or replace function g_member_badges(p_access_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path=public, extensions as $$
declare
  v_uid text; g gatherings; res jsonb := '[]'::jsonb; m record;
  v_invited int; v_items bigint; v_feat jsonb; v_top text; v_top_tier int;
  v_rank int; v_elder_t int; v_master_t int; v_king_t int; v_mutual bigint;
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
      from gatherings where owner_id = m.muid or participants @> jsonb_build_array(jsonb_build_object('uid', m.muid));
    select featured_badges into v_feat from user_prefs where uid = m.muid;
    v_rank := _elder_rank(m.muid);

    v_elder_t  := case when v_rank is null then 0 when v_rank<=10 then 3 when v_rank<=20 then 2 else 1 end;
    v_master_t := case when v_items>=200 then 3 when v_items>=80 then 2 when v_items>=20 then 1 else 0 end;
    v_king_t   := case when v_invited>=30 then 3 when v_invited>=15 then 2 when v_invited>=5 then 1 else 0 end;

    v_top := null; v_top_tier := 0;
    if v_feat is not null and jsonb_typeof(v_feat) = 'array' then
      select t.k into v_top
      from jsonb_array_elements_text(v_feat) with ordinality as t(k, ord)
      where (t.k='elder' and v_elder_t>0) or (t.k='master' and v_master_t>0) or (t.k='king' and v_king_t>0)
      order by t.ord limit 1;
      v_top_tier := case v_top when 'elder' then v_elder_t when 'master' then v_master_t when 'king' then v_king_t else 0 end;
    end if;

    select count(*) into v_mutual from gatherings
      where (owner_id = v_uid   or participants @> jsonb_build_array(jsonb_build_object('uid', v_uid)))
        and (owner_id = m.muid  or participants @> jsonb_build_array(jsonb_build_object('uid', m.muid)));

    res := res || jsonb_build_array(jsonb_build_object(
      'uid', m.muid,
      'elder',  v_elder_t>0,  'elderTier',  v_elder_t,
      'master', v_master_t>0, 'masterTier', v_master_t,
      'king',   v_king_t>0,   'kingTier',   v_king_t,
      'top', v_top, 'topTier', v_top_tier, 'mutual', v_mutual));
  end loop;
  return res;
end; $$;

-- 秒付俠：每本帳「第一個付清」的人（first-wins，前端偵測、後端只在還沒記過時寫）
alter table gatherings add column if not exists fast_pay_uid text;
create or replace function g_set_fastpay(p_access_token text, p_id uuid, p_uid text)
returns void language plpgsql security definer set search_path=public, extensions as $$
declare v_uid text; g gatherings;
begin
  v_uid := line_uid(p_access_token);
  if v_uid is null then raise exception 'unauthorized'; end if;
  select * into g from gatherings where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not _is_member(g, v_uid) then raise exception 'forbidden'; end if;
  if g.fast_pay_uid is null and exists(select 1 from jsonb_array_elements(g.participants) e where e->>'uid' = p_uid) then
    update gatherings set fast_pay_uid = p_uid where id = p_id and fast_pay_uid is null;
  end if;
end; $$;
grant execute on function g_set_fastpay(text, uuid, text) to anon, authenticated;
