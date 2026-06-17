-- ============================================================
-- AA 分帳 — 帳號／個資刪除 RPC（2026-06-18）— PDPA 右刪除權（上線前合規）
-- 使用者可自行刪除帳號與個資。原則：移除一切可識別本人的資料，但保留共用帳本的
-- 分帳數字正確（成員 id 留著，只把本人那筆匿名化），避免刪掉成員讓別人的分帳算錯。
--   - 我在所有帳本的成員資料：移除 uid / pic / payInfo（收款資訊）、名字改「已刪除的成員」；
--     我建立的帳本 owner_id 清為 null。
--   - referrals（我邀的/邀我的）、user_prefs（排序+精選徽章）、app_users（元老登記）整列刪除。
--   - 我上傳的頭像檔（avatars/<uid>/...）盡力刪除（儲存權限不足則略過，不擋帳號刪除）。
-- 用法：supabase db push。
-- ============================================================

create or replace function g_delete_account(p_access_token text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare v_uid text;
begin
  v_uid := line_uid(p_access_token);
  if v_uid is null then raise exception 'unauthorized'; end if;

  -- 匿名化所有含我的帳本（移除可識別資訊、保留成員 id 讓分帳不壞）
  update gatherings g set
    owner_id = case when g.owner_id = v_uid then null else g.owner_id end,
    participants = coalesce((
      select jsonb_agg(
        case when e->>'uid' = v_uid
          then (e - 'uid' - 'pic' - 'payInfo') || jsonb_build_object('name','已刪除的成員')
          else e end)
      from jsonb_array_elements(g.participants) e), '[]'::jsonb)
  where g.owner_id = v_uid
     or g.participants @> jsonb_build_array(jsonb_build_object('uid', v_uid));

  delete from referrals where invitee_uid = v_uid or inviter_uid = v_uid;
  delete from user_prefs where uid = v_uid;
  delete from app_users where uid = v_uid;

  -- 我上傳的頭像檔；儲存層 RLS 可能擋 SQL 刪除，包起來不讓它擋住整個帳號刪除
  begin
    delete from storage.objects where bucket_id = 'covers' and name like 'avatars/' || v_uid || '/%';
  exception when others then null;
  end;
end; $$;
grant execute on function g_delete_account(text) to anon, authenticated;
