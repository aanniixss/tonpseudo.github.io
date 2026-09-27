// ════════════════════════════════════════════════════════════════
//  parse-trade — Supabase Edge Function (Deno)
//  Reçoit une capture d'écran de trade, la fait lire par Claude (vision)
//  et renvoie les champs structurés pour pré-remplir le formulaire.
//
//  La clé API Anthropic n'est JAMAIS dans le front : elle est lue ici
//  depuis le secret ANTHROPIC_API_KEY (configuré côté Supabase).
//
//  Déploiement :
//    supabase functions deploy parse-trade
//    supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//
//  ⚠️  La fonction exige un jeton utilisateur valide (verify_jwt).
//      Sans ça, n'importe qui sur Internet pourrait consommer les
//      crédits Anthropic du projet.
// ════════════════════════════════════════════════════════════════

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Modèle : Sonnet lit très bien une capture de plateforme et coûte une
// fraction d'Opus — ce qui compte quand chaque client déclenche des appels.
const MODEL = "claude-sonnet-5";

// Taille max d'image acceptée (base64). Au-delà, l'API Anthropic refuse
// de toute façon, autant répondre clairement tout de suite.
const MAX_B64 = 6 * 1024 * 1024;

const MEDIA_OK = ["image/png", "image/jpeg", "image/gif", "image/webp"];

// Schéma de sortie — Claude renvoie EXACTEMENT cette forme.
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
Lis les valeurs visibles et renvoie-les via l'outil enregistrer_trade.
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
    if (!image || typeof image !== "string") {
      return json({ error: "Champ 'image' (base64) manquant" }, 400);
    }
    if (image.length > MAX_B64) {
      return json({ error: "Capture trop lourde — réduis-la avant d'envoyer" }, 413);
    }
    const mt = MEDIA_OK.includes(media_type) ? media_type : "image/png";

    const key = Deno.env.get("ANTHROPIC_API_KEY");
    if (!key) {
      return json({ error: "ANTHROPIC_API_KEY non configurée (Supabase → Edge Functions → Secrets)" }, 500);
    }

    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 1024,
        // Outil forcé : Claude est obligé de répondre selon le schéma,
        // donc pas de texte libre à re-parser au hasard.
        tools: [{
          name: "enregistrer_trade",
          description: "Enregistre les champs du trade lus sur la capture.",
          input_schema: SCHEMA,
        }],
        tool_choice: { type: "tool", name: "enregistrer_trade" },
        messages: [{
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: mt, data: image } },
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

    const block = (data.content || []).find(
      (b: { type: string; name?: string }) => b.type === "tool_use" && b.name === "enregistrer_trade",
    );
    if (!block?.input) {
      return json({ error: "Lecture impossible — capture trop floue ou sans données de trade" }, 502);
    }
    return json({ trade: block.input });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
