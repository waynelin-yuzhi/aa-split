-- ============================================================
-- AA 分帳 — 認領名字 migration — 已部署版（2026-06-15）
-- 受邀者用短連結加入時，可「認領」host 預建、尚未有人認領的名字，
-- 把自己的 LINE uid 綁到該成員，避免名單出現重複的人。
-- 用法：Supabase SQL Editor 貼上 → Run。
-- ============================================================

create or replace function g_claim_by_slug(p_slug text, p_access_token text, p_member_id text)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings; target jsonb;
begin
  uid := line_uid(p_access_token);
  if uid is null then raise exception 'unauthorized'; end if;
  select * into g from gatherings where slug = p_slug;
  if not found then raise exception 'invalid invite'; end if;
  -- 我已是成員 → 不用認領，直接回
  if g.participants @> jsonb_build_array(jsonb_build_object('uid', uid)) then
    return g;
  end if;
  select elem into target from jsonb_array_elements(g.participants) elem where elem->>'id' = p_member_id;
  if target is null then raise exception 'member not found'; end if;
  -- 已被別人認領（有 uid 且不是我）→ 拒絕，不能搶
  if (target ? 'uid') and (target->>'uid') is not null and (target->>'uid') <> uid then
    raise exception 'already claimed';
  end if;
  update gatherings
  set participants = (
    select jsonb_agg(
      case when (elem->>'id') = p_member_id
        then elem || jsonb_build_object('uid', uid)
        else elem end)
    from jsonb_array_elements(participants) elem)
  where id = g.id
  returning * into g;
  return g;
end; $$;

grant execute on function g_claim_by_slug(text, text, text) to anon, authenticated;
