-- ============================================================
-- AA 分帳 — 帳本封面底圖 migration — 已部署版（2026-06-16）
-- 成員可上傳自己的照片當帳本封面。圖存 Supabase Storage，檔名前端產生（不可猜）。
-- 作法：gatherings 加 cover text；g_save 多吃 p_cover（預設 null＝沿用、非破壞）；
--       covers bucket 公開讀、限圖片、2MB；anon 可上傳（封面歸屬仍由 g_save 驗成員）。
-- 隱私：前端上傳前以 canvas 縮圖＋重新編碼（去除 EXIF/GPS）；檔名隨機；cover 網址只存在
--       帳本資料內（僅成員/持 slug 者讀得到）；前端只認自家 storage 網址、擋 style 注入。
-- 用法：Supabase SQL Editor 貼上 → Run。
-- ============================================================

alter table gatherings add column if not exists cover text;

drop function if exists g_save(uuid,text,text,date,text,text,jsonb,jsonb,jsonb,jsonb,jsonb);
create or replace function g_save(p_id uuid, p_access_token text, p_title text, p_event_date date, p_currency text, p_status text, p_participants jsonb, p_items jsonb, p_adjustments jsonb, p_settlements jsonb, p_history jsonb default null, p_cover text default null)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings; begin
  select * into g from gatherings where id = p_id;
  if not found then raise exception 'not found'; end if;
  uid := line_uid(p_access_token);
  if not _is_member(g, uid) then raise exception 'forbidden'; end if;
  update gatherings set title=p_title, event_date=p_event_date, currency=coalesce(p_currency,'TWD'), status=coalesce(p_status,'open'),
    participants=coalesce(p_participants,participants), items=coalesce(p_items,items), adjustments=coalesce(p_adjustments,adjustments), settlements=coalesce(p_settlements,settlements), history=coalesce(p_history,history), cover=coalesce(p_cover,cover)
    where id=p_id returning * into g;
  return g;
end; $$;
grant execute on function g_save(uuid,text,text,date,text,text,jsonb,jsonb,jsonb,jsonb,jsonb,text) to anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('covers','covers', true, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=excluded.public, file_size_limit=excluded.file_size_limit, allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "covers read" on storage.objects;
create policy "covers read" on storage.objects for select to anon, authenticated using (bucket_id='covers');
drop policy if exists "covers insert" on storage.objects;
create policy "covers insert" on storage.objects for insert to anon, authenticated with check (bucket_id='covers');
