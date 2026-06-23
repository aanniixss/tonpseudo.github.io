// ════════════════════════════════════════════════════════════════
//  parse-trade — Supabase Edge Function (Deno)
//  Reçoit une capture d'écran de trade, la fait lire par Claude (vision)
//  et renvoie les champs structurés pour pré-remplir le formulaire.
//
//  La clé API Anthropic n'est JAMAIS dans le front : elle est lue ici
//  depuis le secret ANTHROPIC_API_KEY (configuré côté Supabase).
//
//  Déploiement :
//    supabase functions deploy parse-trade --no-verify-jwt
//    supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
// ════════════════════════════════════════════════════════════════

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Schéma de sortie structuré — Claude renvoie EXACTEMENT cette forme.
const SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    pair: { type: "string", description: "Symbole, ex: EURUSD, XAUUSD, BTCUSD, US30. Vide si illisible." },
    direction: { type: "string", enum: ["LONG", "SHORT", ""] },
    session: { type: "string", enum: ["London", "New York", "Tokyo / Asia", "Overlap Lon/NY", ""] },
    day: { type: "string", enum: ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", ""] },
    entry_time: { type: "string", description: "Heure d'entrée 24h HH:MM, vide si absente" },
    exit_time: { type: "string", description: "Heure de sortie 24h HH:MM, vide si absente" },
    lot_size: { type: "number", description: "Taille de lot, 0 si absente" },
    risk_pct: { type: "number", description: "% du capital risqué, 0 si absent" },
    rr: { type: "number", description: "Ratio risque/rendement réalisé, 0 si absent" },
    result: { type: "string", enum: ["WIN", "LOSS", "BE", ""] },
    gross_pnl: { type: "number", description: "Profit/CA AVANT commission (négatif si perte), 0 si absent" },
    commission: { type: "number", description: "Frais/commission (nombre positif), 0 si absent" },
    net_pnl: { type: "number", description: "Profit/perte NET final, 0 si absent" },
    notes: { type: "string", description: "Détails visibles utiles, sinon vide" },
  },
  required: [
    "pair", "direction", "session", "day", "entry_time", "exit_time",
    "lot_size", "risk_pct", "rr", "result", "gross_pnl", "commission",
    "net_pnl", "notes",
  ],
};

const PROMPT = `Tu extrais UN trade depuis une capture d'écran de plateforme de trading (MT4/MT5, TradingView, cTrader, dashboard prop-firm, etc.).
Lis les valeurs visibles et renvoie-les.
- direction: LONG pour un achat/buy, SHORT pour une vente/sell.
- result: WIN si le net est positif, LOSS si négatif, BE si ~0.
- gross_pnl: profit avant commission (négatif pour une perte). commission: frais (nombre positif). net_pnl: résultat net final.
- Heures au format 24h HH:MM.
- Si un champ n'est pas visible: chaîne vide pour le texte, 0 pour les nombres. N'invente jamais de valeur.`;

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  try {
    const { image, media_type } = await req.json();
    if (!image) return json({ error: "Champ 'image' (base64) manquant" }, 400);

    const key = Deno.env.get("ANTHROPIC_API_KEY");
    if (!key) {
      return json({ error: "ANTHROPIC_API_KEY non configurée (supabase secrets set)" }, 500);
    }

    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-opus-4-8",
        max_tokens: 1024,
        output_config: { format: { type: "json_schema", schema: SCHEMA } },
        messages: [{
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: media_type || "image/png", data: image } },
            { type: "text", text: PROMPT },
          ],
        }],
      }),
    });

    const data = await r.json();
    if (!r.ok) {
      return json({ error: data?.error?.message || "Erreur Anthropic", detail: data }, 502);
    }
    if (data.stop_reason === "refusal") {
      return json({ error: "Image refusée par le modèle (réessaie avec une capture plus claire)" }, 422);
    }

    const textBlock = (data.content || []).find((b: { type: string }) => b.type === "text");
    let trade: unknown = null;
    try {
      trade = JSON.parse(textBlock.text);
    } catch (_e) {
      return json({ error: "Lecture impossible", raw: textBlock?.text }, 502);
    }
    return json({ trade });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
