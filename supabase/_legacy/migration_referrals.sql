-- ============================================================
-- AA 分帳 — 邀請歸因 / 徽章 migration — 已部署版（2026-06-16）
-- referrals 表記「誰邀請了誰」：invitee 一人一次（第一個邀請者勝）、擋自刷。RLS 全鎖，只走帶身分 RPC。
-- 邀請連結帶 ?by=<inviter uid>；對方開 App 登入後 boot 呼叫 g_record_referral。
-- g_my_badges 回 {invited 成功邀請數, wasInvited 我是否被邀, firstSeen 我最早建立帳本時間（元老判定）}。
-- 用法：Supabase SQL Editor 貼上 → Run。
-- ============================================================

create table if not exists referrals (
  invitee_uid text primary key,
  inviter_uid text not null,
  at timestamptz not null default now()
);
alter table referrals enable row level security;
revoke all on table referrals from anon, authenticated;

create or replace function g_record_referral(p_access_token text, p_inviter text)
returns void language plpgsql security definer set search_path=public, extensions as $$
declare v_uid text;
begin
  v_uid := line_uid(p_access_token);
  if v_uid is null then raise exception 'unauthorized'; end if;
  if p_inviter is null or length(p_inviter) < 3 or p_inviter = v_uid then return; end if;
  insert into referrals(invitee_uid, inviter_uid) values (v_uid, p_inviter)
  on conflict (invitee_uid) do nothing;
end; $$;

create or replace function g_my_badges(p_access_token text)
returns jsonb language plpgsql security definer set search_path=public, extensions as $$
declare v_uid text; v_invited int; v_was boolean; v_first timestamptz;
begin
  v_uid := line_uid(p_access_token);
  if v_uid is null then raise exception 'unauthorized'; end if;
  select count(*) into v_invited from referrals where inviter_uid = v_uid;
  select exists(select 1 from referrals where invitee_uid = v_uid) into v_was;
  select min(created_at) into v_first from gatherings where owner_id = v_uid;
  return jsonb_build_object('invited', v_invited, 'wasInvited', v_was, 'firstSeen', v_first);
end; $$;

grant execute on function g_record_referral(text, text) to anon, authenticated;
grant execute on function g_my_badges(text) to anon, authenticated;
