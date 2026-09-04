# BAKOU — Journal de trading professionnel

Application web qui transforme chaque trade enregistré en statistiques exploitables :
espérance de gain, profit factor, cartes de performance, score de discipline,
détection du revenge trading, bilans exportables.

🌐 **En ligne :** https://aanniixss.github.io/tonpseudo.github.io/

---

## Architecture

Application « sans build » : trois fichiers HTML autonomes, aucune étape de
compilation, déploiement automatique par GitHub Pages à chaque commit sur `main`.

| Fichier | Rôle |
|---|---|
| `index.html` | Page de présentation publique (offre, tarifs, FAQ, SEO) |
| `app.html` | L'application complète — écran de connexion, journal, statistiques, rapports |
| `beta.html`, `home.html`, `preview.html`, `redesign.html` | Redirections conservées pour d'anciens liens |
| `cgu.html`, `confidentialite.html`, `mentions-legales.html` | Documents légaux |
| `legal-style.css` | Feuille de style commune aux pages légales |
| `assets/` | Logo et captures utilisées par la page de présentation |
| `supabase/migrations/` | Scripts SQL à exécuter sur la base |
| `supabase/functions/` | Fonctions serveur (Deno) |

### Bibliothèques (chargées par CDN, aucune installation)
Supabase JS 2 · Chart.js 4 · SheetJS (import MT5) · html2canvas + jsPDF (bilans PDF)

### Données
- **Supabase** (PostgreSQL, région Irlande) : tables `accounts` et `trades`, authentification par e-mail.
- **Stockage local du navigateur** : notes du Notebook, objectifs mensuels, préférences d'affichage.
  ⚠️ Ces données ne sont **pas** synchronisées entre appareils — voir la feuille de route.

---

## Mise en place d'un nouvel environnement

### 1. Sécuriser la base — **obligatoire**
Exécuter [`supabase/migrations/001_securite_rls.sql`](supabase/migrations/) dans
Supabase → SQL Editor. Sans ce script, la clé publique du site donne accès aux
données de tous les utilisateurs.

### 2. Déployer les fonctions serveur
```bash
supabase functions deploy delete-account          # suppression de compte (RGPD)
supabase functions deploy parse-trade --no-verify-jwt
supabase secrets set ANTHROPIC_API_KEY=sk-ant-... # pour la lecture de capture
```

### 3. Configurer l'authentification
Supabase → Authentication :
- **URL Configuration → Site URL** : l'adresse publique du site
- **Providers → Email** : pendant la bêta, désactiver « Confirm email »
  (le service d'envoi gratuit est limité à quelques messages par heure, ce qui
  empêche les inscriptions). Pour le passage en payant, configurer un SMTP dédié.

### 4. Compléter les mentions légales
Renseigner les champs signalés en orange dans `mentions-legales.html`, `cgu.html`
et `confidentialite.html` : identité de l'éditeur, SIRET, e-mail de contact,
médiateur de la consommation, prestataire de paiement.

---

## Développement

Aucune dépendance à installer. Servir le dossier et ouvrir l'application :

```bash
python3 -m http.server 8000
# puis http://localhost:8000/app.html
```

### Avant chaque commit
`app.html` contient trois blocs `<script>`. Vérifier leur syntaxe :

```bash
python3 - <<'PY'
import re
s = open('app.html').read()
for i, b in enumerate(re.findall(r'<script>(.*?)</script>', s, re.S)):
    open(f'/tmp/bloc{i}.js', 'w').write(b)
PY
for f in /tmp/bloc*.js; do node --check "$f" || echo "ERREUR: $f"; done
```

### Conventions
- Le français est la langue de l'interface et des commentaires.
- Les identifiants d'éléments sont courts et stables (`k-cap`, `md-kpis`, `lg-btn`) :
  ils sont référencés depuis le JavaScript, ne pas les renommer sans vérifier.
- Toute écriture en base doit être filtrée par `owner_uuid`, jamais par le seul
  identifiant de compte de trading.

---

## Feuille de route de commercialisation

Voir le rapport d'audit détaillé. Priorités :

| Priorité | Sujet | État |
|---|---|---|
| 🔴 1 | Sécuriser la base (script RLS) | Script prêt, **à exécuter** |
| 🔴 2 | Compléter les mentions légales | Modèles prêts, **à compléter** |
| 🔴 3 | Débloquer la création de compte (réglage e-mail Supabase) | **À faire** |
| 🟠 4 | Captures d'écran vers Supabase Storage plutôt qu'en base | À faire |
| 🟠 5 | Paiement et application des offres Free / Pro / Elite | À faire |
| 🟡 6 | Synchronisation des notes et objectifs entre appareils | À faire |

---

## Licence
Projet propriétaire. Tous droits réservés.
