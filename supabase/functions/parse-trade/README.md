# parse-trade — Remplissage de trade par photo (IA)

Fonction Edge Supabase qui lit une capture d'écran de trade avec Claude (vision)
et renvoie les champs structurés pour pré-remplir le formulaire du journal.

**La clé API Anthropic reste secrète côté serveur** — elle n'est jamais dans la page.

## Déploiement (une seule fois)

Prérequis : [Supabase CLI](https://supabase.com/docs/guides/cli) installé et connecté.

```bash
# 1. Se lier au projet
supabase link --project-ref nogfrvpvknaqlgfnrjol

# 2. Déposer ta clé API Anthropic comme SECRET (jamais dans le code/chat)
supabase secrets set ANTHROPIC_API_KEY=sk-ant-xxxxxxxx

# 3. Déployer la fonction (publique, sans JWT)
supabase functions deploy parse-trade --no-verify-jwt
```

URL finale :
`https://nogfrvpvknaqlgfnrjol.supabase.co/functions/v1/parse-trade`

## Alternative sans CLI (dashboard)

1. Supabase → **Edge Functions** → **Deploy a new function** → nom `parse-trade`,
   colle le contenu de `index.ts`, décoche « Verify JWT ».
2. Supabase → **Project Settings → Edge Functions → Secrets** →
   ajoute `ANTHROPIC_API_KEY` = ta clé.

## Test rapide

```bash
curl -X POST https://nogfrvpvknaqlgfnrjol.supabase.co/functions/v1/parse-trade \
  -H "content-type: application/json" \
  -d '{"image":"<base64-png>","media_type":"image/png"}'
```

Réponse : `{ "trade": { "pair": "...", "direction": "...", ... } }`

## Modèle

Utilise `claude-opus-4-8` (vision + structured outputs). Pour réduire le coût
par photo, tu peux remplacer le model par `claude-sonnet-4-6` dans `index.ts`.
