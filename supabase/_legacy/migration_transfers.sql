-- ============================================================
-- AA 分帳 — 轉帳/還款紀錄 migration — 已部署版（2026-06-15）
-- 除了支出，帳本可記「誰實際轉錢給誰」（還款）。每筆轉帳讓付款人淨值 +、收款人淨值 −（零和），
-- 分帳結果自動扣掉、算出「還要喬」的剩餘最少轉帳。
-- 作法：gatherings 加 transfers jsonb；g_save 多吃 p_transfers（預設 null＝沿用、非破壞）。
-- 用法：Supabase SQL Editor 貼上 → Run。
-- ============================================================

alter table gatherings add column if not exists transfers jsonb not null default '[]'::jsonb;

drop function if exists g_save(uuid,text,text,date,text,text,jsonb,jsonb,jsonb,jsonb,jsonb,text);
create or replace function g_save(p_id uuid, p_access_token text, p_title text, p_event_date date, p_currency text, p_status text, p_participants jsonb, p_items jsonb, p_adjustments jsonb, p_settlements jsonb, p_history jsonb default null, p_cover text default null, p_transfers jsonb default null)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings; begin
  select * into g from gatherings where id = p_id;
  if not found then raise exception 'not found'; end if;
  uid := line_uid(p_access_token);
  if not _is_member(g, uid) then raise exception 'forbidden'; end if;
  update gatherings set title=p_title, event_date=p_event_date, currency=coalesce(p_currency,'TWD'), status=coalesce(p_status,'open'),
    participants=coalesce(p_participants,participants), items=coalesce(p_items,items), adjustments=coalesce(p_adjustments,adjustments), settlements=coalesce(p_settlements,settlements), history=coalesce(p_history,history), cover=coalesce(p_cover,cover), transfers=coalesce(p_transfers,transfers)
    where id=p_id returning * into g;
  return g;
end; $$;
grant execute on function g_save(uuid,text,text,date,text,text,jsonb,jsonb,jsonb,jsonb,jsonb,text,jsonb) to anon, authenticated;
