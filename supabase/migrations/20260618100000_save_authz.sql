-- ============================================================
-- AA 分帳 — g_save 權限收緊（2026-06-18）— 上線給陌生人前的後端加固
-- 背景：g_save 原本只驗「是不是成員」，成員就能整本覆寫。對朋友共筆 OK，
--       但對不熟的人有兩個問題，都在這支修掉（不改朋友間的順手度）：
--   1) 結算狀態被繞過：任何成員可直接打 g_save 蓋掉付/收款狀態，
--      繞過 g_settle 的「只有付款人能標已付、收款人能確認」逐筆驗身分。
--      → 修法：只有建立者(owner)能透過 g_save 改 settlements（owner 需要它做合併成員的 key 重映射）；
--        其他成員的 settlements 寫入一律忽略（沿用 DB 現值），結算只能走 g_settle。
--   2) 踢人沒鎖後端：前端已限「只有建立者能移除/合併成員」，但直接打 API 仍可繞過。
--      → 修法：非建立者送來的成員名單，若漏掉既有成員，依 id 自動補回（等於不准刪），
--        新增/改名/更新自己都正常；順帶吸收「成員清單過期造成的誤刪」。
-- 另：covers bucket 上傳上限 2MB→1.5MB（前端縮圖後遠低於此，正常上傳不受影響；
--     縮小被灌爆的單檔上限）。真正的「依成員身分擋上傳」需走 Edge Function 簽名上傳，另議。
-- 用法：supabase db push（或 SQL Editor 貼上 Run）。
-- ============================================================

create or replace function g_save(p_id uuid, p_access_token text, p_title text, p_event_date date, p_currency text, p_status text, p_participants jsonb, p_items jsonb, p_adjustments jsonb, p_settlements jsonb, p_history jsonb default null, p_cover text default null, p_transfers jsonb default null)
returns gatherings language plpgsql security definer set search_path = public, extensions as $$
declare uid text; g gatherings; v_owner boolean; v_parts jsonb; v_setts jsonb;
begin
  select * into g from gatherings where id = p_id;
  if not found then raise exception 'not found'; end if;
  uid := line_uid(p_access_token);
  if not _is_member(g, uid) then raise exception 'forbidden'; end if;
  v_owner := (g.owner_id is not distinct from uid);   -- uid 過了 _is_member 必非 null；owner_id 為 null（舊資料）視為非 owner（安全側）

  -- 結算：只有建立者能透過存整本改；其他人沿用現值（結算走 g_settle）
  v_setts := case when v_owner then coalesce(p_settlements, g.settlements) else g.settlements end;

  -- 成員：非建立者不可移除既有成員 → 把漏掉的既有成員依 id 補回
  v_parts := coalesce(p_participants, g.participants);
  if not v_owner then
    v_parts := v_parts || coalesce((
      select jsonb_agg(old)
      from jsonb_array_elements(g.participants) old
      where not exists (select 1 from jsonb_array_elements(v_parts) nw where nw->>'id' = old->>'id')
    ), '[]'::jsonb);
  end if;

  update gatherings set
    title=p_title, event_date=p_event_date, currency=coalesce(p_currency,'TWD'), status=coalesce(p_status,'open'),
    participants=v_parts, items=coalesce(p_items,items), adjustments=coalesce(p_adjustments,adjustments),
    settlements=v_setts, history=coalesce(p_history,history), cover=coalesce(p_cover,cover), transfers=coalesce(p_transfers,transfers)
    where id=p_id returning * into g;
  return g;
end; $$;
grant execute on function g_save(uuid,text,text,date,text,text,jsonb,jsonb,jsonb,jsonb,jsonb,text,jsonb) to anon, authenticated;

-- 封面上傳上限收緊（2MB → 1.5MB）
update storage.buckets set file_size_limit = 1572864 where id = 'covers';
