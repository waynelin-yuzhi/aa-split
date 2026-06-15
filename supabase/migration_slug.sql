-- ============================================================
-- AA 分帳 — 短連結（slug）migration — 已部署版（2026-06-15）
-- 把分享連結從超長 id+token 換成 12 碼 hex slug（~48 bits，不可猜）。
-- slug 本身即 capability：持有短連結的人可讀、可加入（沿用邀請模型）。
-- 用法：Supabase SQL Editor 貼上 → Run。
-- ============================================================

alter table gatherings add column if not exists slug text;
update gatherings set slug = substr(replace(gen_random_uuid()::text,'-',''),1,12) where slug is null;
alter table gatherings alter column slug set default substr(replace(gen_random_uuid()::text,'-',''),1,12);
create unique index if not exists gatherings_slug_uk on gatherings(slug);

-- 短連結讀取：持有 slug 即可讀（查無此 slug 時回整列皆 null，前端以 row.id 判存在）
create or replace function g_get_by_slug(p_slug text, p_access_token text)
returns gatherings language sql security definer set search_path = public, extensions as $$
  select * from gatherings where slug = p_slug;
$$;

-- 短連結加入：正確 slug + 已登入 → 把我加進 participants
create or replace function g_join_by_slug(p_slug text, p_access_token text, p_my_name text, p_my_member_id text)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings;
begin
  uid := line_uid(p_access_token);
  if uid is null then raise exception 'unauthorized'; end if;
  select * into g from gatherings where slug = p_slug;
  if not found then raise exception 'invalid invite'; end if;
  if not (g.participants @> jsonb_build_array(jsonb_build_object('uid', uid))) then
    update gatherings set participants = participants || jsonb_build_array(jsonb_build_object('id', p_my_member_id, 'name', p_my_name, 'uid', uid))
      where id = g.id returning * into g;
  end if;
  return g;
end; $$;

grant execute on function g_get_by_slug(text, text)              to anon, authenticated;
grant execute on function g_join_by_slug(text, text, text, text) to anon, authenticated;
