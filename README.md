# BAKOU — Mon track record

Application personnelle de suivi de trades : statistiques, score, calendrier,
import MT5, bilans. Usage privé, non commercialisé.

🌐 https://aanniixss.github.io/tonpseudo.github.io/ (redirige vers `app.html`)

## Architecture

Application « sans build » : `app.html` contient tout. `index.html` ne fait que
rediriger vers elle. Déploiement automatique par GitHub Pages à chaque commit sur `main`.

- **Données** : Supabase (tables `accounts` et `trades`). La connexion se fait une
  seule fois par appareil, la session est ensuite conservée.
- **Stockage navigateur** : notes du Notebook, objectifs mensuels, préférences
  (non synchronisés entre appareils).
- **Sauvegarde** : bouton « Mon compte » → export JSON complet.
- `supabase/migrations/` : scripts SQL (RLS, réparation de comptes).
- `supabase/functions/parse-trade` : lecture de capture d'écran.
- Bibliothèques par CDN : Supabase JS, Chart.js, SheetJS, html2canvas, jsPDF.
