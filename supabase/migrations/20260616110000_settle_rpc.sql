-- ============================================================
-- AA 分帳 — 後端加固：逐筆結算 RPC g_settle（2026-06-16）
-- 把「誰能標記轉帳」的規則搬進後端驗證（不只前端藏按鈕）：
--   付款方才能 mark_paid / unmark_paid；收款方才能 confirm / unconfirm / received（直接結清）。
--   當事人是「沒綁 LINE 的預設名字」時，由「建立這本帳的人(owner)」代記。
--   非當事人（即使繞過前端直接打 API）一律擋。
-- 原子更新單一 settlement key（不再整包 g_save，順便解掉同時改互蓋）+ 附一筆 history。
-- 保留「收款人可直接 received 結清」（付款人轉了沒更新時，收款人自己按）。
-- ============================================================

create or replace function g_settle(p_access_token text, p_id uuid, p_from text, p_to text, p_op text)
returns gatherings language plpgsql security definer set search_path=public, extensions as $$
declare
  v_uid text; g gatherings; fromM jsonb; toM jsonb;
  from_uid text; to_uid text; is_owner boolean; payer_side boolean; payee_side boolean;
  k text; sett jsonb; cur jsonb; newval jsonb;
  from_name text; to_name text; actor_name text; action_text text; hist jsonb;
begin
  v_uid := line_uid(p_access_token);
  if v_uid is null then raise exception 'unauthorized'; end if;
  select * into g from gatherings where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not _is_member(g, v_uid) then raise exception 'forbidden'; end if;

  select elem into fromM from jsonb_array_elements(g.participants) elem where elem->>'id' = p_from;
  select elem into toM   from jsonb_array_elements(g.participants) elem where elem->>'id' = p_to;
  if fromM is null or toM is null then raise exception 'member not found'; end if;
  from_uid := fromM->>'uid'; to_uid := toM->>'uid';
  from_name := coalesce(fromM->>'name','?'); to_name := coalesce(toM->>'name','?');
  is_owner := (g.owner_id = v_uid);
  payer_side := (from_uid = v_uid) or (from_uid is null and is_owner);   -- 付款方（虛擬則 owner 代）
  payee_side := (to_uid = v_uid)   or (to_uid   is null and is_owner);   -- 收款方（虛擬則 owner 代）

  -- 權限：付款方改「已付」；收款方「確認 / 我已收到（直接結清）」
  if p_op in ('mark_paid','unmark_paid')        and not payer_side then raise exception 'not allowed'; end if;
  if p_op in ('confirm','unconfirm','received') and not payee_side then raise exception 'not allowed'; end if;

  -- settlements 正規化為物件（相容舊陣列＝視為已付已確認、null＝空）
  sett := coalesce(g.settlements, '{}'::jsonb);
  if jsonb_typeof(sett) = 'array' then
    select coalesce(jsonb_object_agg(e, jsonb_build_object('paid',true,'confirmed',true)),'{}'::jsonb)
      into sett from jsonb_array_elements_text(sett) e;
  elsif jsonb_typeof(sett) <> 'object' then sett := '{}'::jsonb; end if;

  k := p_from || '>' || p_to;
  cur := coalesce(sett->k, '{}'::jsonb);

  if p_op = 'mark_paid' then
    newval := jsonb_build_object('paid',true,'confirmed',false); action_text := '標記已付：'||from_name||'→'||to_name;
  elsif p_op = 'unmark_paid' then
    sett := sett - k; newval := null; action_text := '改回未付：'||from_name||'→'||to_name;
  elsif p_op = 'received' then
    newval := jsonb_build_object('paid',true,'confirmed',true); action_text := '收款人標記已收到：'||from_name||'→'||to_name;
  elsif p_op = 'confirm' then
    if not coalesce((cur->>'paid')::boolean,false) then raise exception 'not paid yet'; end if;
    newval := jsonb_build_object('paid',true,'confirmed',true); action_text := '確認收到：'||from_name||'→'||to_name;
  elsif p_op = 'unconfirm' then
    newval := jsonb_build_object('paid',coalesce((cur->>'paid')::boolean,false),'confirmed',false); action_text := '取消確認：'||from_name||'→'||to_name;
  else raise exception 'bad op';
  end if;

  if newval is not null then sett := sett || jsonb_build_object(k, newval); end if;

  -- 附一筆 history（actor 名字＝其在本帳的成員名）
  select elem->>'name' into actor_name from jsonb_array_elements(g.participants) elem where elem->>'uid' = v_uid limit 1;
  hist := coalesce(g.history,'[]'::jsonb) || jsonb_build_array(jsonb_build_object(
    'ts', (extract(epoch from now())*1000)::bigint, 'by', v_uid, 'byName', coalesce(actor_name,'?'), 'action', action_text));
  if jsonb_array_length(hist) > 200 then
    select jsonb_agg(e order by ord) into hist
    from jsonb_array_elements(hist) with ordinality t(e, ord)
    where ord > jsonb_array_length(hist) - 200;
  end if;

  update gatherings set settlements = sett, history = hist where id = p_id returning * into g;
  return g;
end; $$;
grant execute on function g_settle(text, uuid, text, text, text) to anon, authenticated;
