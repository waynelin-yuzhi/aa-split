// 上傳身分把關：驗證 LINE token → （封面再驗成員）→ 用 service role 發「簽名上傳網址」
// 前端拿到後用 uploadToSignedUrl 上傳；bucket 的 anon 直接上傳已關閉，灌圖必須先過這關。
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
const rid = () => crypto.randomUUID().replace(/-/g, "");

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { accessToken, kind, gatheringId } = await req.json();
    if (!accessToken) return json({ error: "no token" }, 401);

    // 驗 LINE access token → 已驗證 userId
    const r = await fetch("https://api.line.me/oauth2/v2.1/userinfo", {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!r.ok) return json({ error: "invalid token" }, 401);
    const prof = await r.json();
    const uid = prof?.sub;
    if (!uid) return json({ error: "invalid token" }, 401);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    let path: string;
    if (kind === "avatar") {
      path = `avatars/${uid}/${rid()}.jpg`;
    } else {
      if (!gatheringId) return json({ error: "no gathering" }, 400);
      const { data: g } = await admin.from("gatherings")
        .select("owner_id, participants").eq("id", gatheringId).maybeSingle();
      if (!g) return json({ error: "gathering not found" }, 404);
      const parts = Array.isArray(g.participants) ? g.participants : [];
      const isMember = g.owner_id === uid || parts.some((p: any) => p && p.uid === uid);
      if (!isMember) return json({ error: "forbidden" }, 403);
      path = `${gatheringId}/${rid()}.jpg`;
    }

    const { data, error } = await admin.storage.from("covers").createSignedUploadUrl(path);
    if (error) return json({ error: error.message }, 500);
    return json({ path: data.path, token: data.token });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
