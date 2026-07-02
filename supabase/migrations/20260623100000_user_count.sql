-- ============================================================
-- AA 分帳 — 首頁「使用人數」計數（2026-06-23）
-- g_my_badges 多回 userCount＝app_users 總數（每個登入過的 LINE 帳號都會被 _touch_user 登記，
-- 正是「用過這個 App 的人數」）。搭進 boot 既有呼叫、零多餘請求；只回聚合數字、無個資。
-- ============================================================

create or replace function g_my_badges(p_access_token text)
returns jsonb language plpgsql security definer set search_path=public, extensions as $$
declare v_uid text; v_invited int; v_was boolean; v_first timestamptz; v_feat jsonb; v_users bigint;
begin
  v_uid := line_uid(p_access_token);
  if v_uid is null then raise exception 'unauthorized'; end if;
  perform _touch_user(v_uid);
  select count(*) into v_invited from referrals where inviter_uid = v_uid;
  select exists(select 1 from referrals where invitee_uid = v_uid) into v_was;
  select min(created_at) into v_first from gatherings where owner_id = v_uid;
  select featured_badges into v_feat from user_prefs where uid = v_uid;
  select count(*) into v_users from app_users;
  return jsonb_build_object('invited', v_invited, 'wasInvited', v_was, 'firstSeen', v_first,
                            'elder', _is_elder(v_uid), 'elderRank', _elder_rank(v_uid),
                            'featured', coalesce(v_feat,'[]'::jsonb),
                            'userCount', v_users);
end; $$;
