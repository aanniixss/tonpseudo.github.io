// ════════════════════════════════════════════════════════════════════
//  delete-account — Supabase Edge Function (Deno)
//
//  Supprime définitivement le compte de l'utilisateur AUTHENTIFIÉ et
//  toutes ses données (trades, comptes de trading, compte d'accès).
//  Obligation RGPD : droit à l'effacement (art. 17).
//
//  Sécurité : l'utilisateur est identifié à partir de SON jeton. Il ne
//  peut donc supprimer que son propre compte — jamais celui d'un autre.
//
//  Déploiement :
//    supabase functions deploy delete-account
//  (SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont fournis automatiquement)
// ════════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST uniquement" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    // 1. Identifier l'appelant à partir de SON jeton (jamais d'un id fourni par le client)
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return json({ error: "Authentification requise" }, 401);
    }
    const asUser = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
    const { data: { user }, error: userErr } = await asUser.auth.getUser();
    if (userErr || !user) return json({ error: "Session invalide ou expirée" }, 401);

    // 2. Supprimer les données avec les droits d'administration
    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

    const { error: tErr } = await admin.from("trades").delete().eq("owner_uuid", user.id);
    if (tErr) return json({ error: "Suppression des trades : " + tErr.message }, 500);

    const { error: aErr } = await admin.from("accounts").delete().eq("owner_uuid", user.id);
    if (aErr) return json({ error: "Suppression des comptes : " + aErr.message }, 500);

    // 3. Supprimer le compte d'accès lui-même
    const { error: dErr } = await admin.auth.admin.deleteUser(user.id);
    if (dErr) return json({ error: "Suppression du compte : " + dErr.message }, 500);

    return json({ ok: true, deleted: user.id });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
