-- ============================================================
-- AA 分帳 — 帳本編輯歷史 migration — 已部署版（2026-06-16）
-- 每本帳本存一份編輯歷史（時間戳記、是誰、做了什麼）。
-- 作法：gatherings 加 history jsonb；g_save 多吃 p_history（預設 null＝沿用舊值，
--       讓尚未更新的前端 10 參數呼叫仍可運作、不會清掉 history）。
-- 注意：history 與其他欄位一樣是整包 last-write-wins；兩人同時編輯仍可能漏記，
--       要根治需逐項原子更新（append-only）——列為後續硬化項。
-- 用法：Supabase SQL Editor 貼上 → Run。
-- ============================================================

alter table gatherings add column if not exists history jsonb not null default '[]'::jsonb;

drop function if exists g_save(uuid,text,text,date,text,text,jsonb,jsonb,jsonb,jsonb);

create or replace function g_save(p_id uuid, p_access_token text, p_title text, p_event_date date, p_currency text, p_status text, p_participants jsonb, p_items jsonb, p_adjustments jsonb, p_settlements jsonb, p_history jsonb default null)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings; begin
  select * into g from gatherings where id = p_id;
  if not found then raise exception 'not found'; end if;
  uid := line_uid(p_access_token);
  if not _is_member(g, uid) then raise exception 'forbidden'; end if;
  update gatherings set title=p_title, event_date=p_event_date, currency=coalesce(p_currency,'TWD'), status=coalesce(p_status,'open'),
    participants=coalesce(p_participants,participants), items=coalesce(p_items,items), adjustments=coalesce(p_adjustments,adjustments), settlements=coalesce(p_settlements,settlements), history=coalesce(p_history,history)
    where id=p_id returning * into g;
  return g;
end; $$;

grant execute on function g_save(uuid,text,text,date,text,text,jsonb,jsonb,jsonb,jsonb,jsonb) to anon, authenticated;
