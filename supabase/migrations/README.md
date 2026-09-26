# Migrations Supabase — BAKOU

## `001_securite_rls.sql` — à exécuter en priorité absolue

### Pourquoi
La clé `anon` est publique : elle est visible dans le code source du site, ce qui est
normal et prévu par Supabase. La sécurité ne repose donc **pas** sur cette clé, mais
sur les règles *Row Level Security* (RLS) définies dans la base.

Sans RLS, n'importe qui peut ouvrir la console de son navigateur et lire, modifier
ou supprimer **les trades de tous les utilisateurs**. C'est rédhibitoire pour un
service payant, et c'est une violation du RGPD (art. 32 — sécurité du traitement).

### Comment l'exécuter
1. Ouvrir [supabase.com/dashboard](https://supabase.com/dashboard) → projet BAKOU
2. Menu de gauche → **SQL Editor** → **New query**
3. Coller le contenu de `001_securite_rls.sql`
4. Cliquer **Run**

### Vérifier que tout s'est bien passé
Le script se termine par trois contrôles. Lis leurs résultats :

| Contrôle | Résultat attendu |
|---|---|
| Lignes orphelines | `0` pour `accounts` **et** `trades` |
| Sécurité active | `true` pour les deux tables |
| Règles en place | **8 lignes** (4 par table) |

> ⚠️ Si des lignes orphelines subsistent, elles deviendront **invisibles** pour tout
> le monde (données antérieures à l'authentification). Ne les supprime pas : rattache-les
> d'abord au bon utilisateur, en récupérant son identifiant dans **Authentication → Users** :
>
> ```sql
> update public.accounts set owner_uuid = 'UUID-DE-L-UTILISATEUR' where owner_uuid is null;
> update public.trades   set owner_uuid = 'UUID-DE-L-UTILISATEUR' where owner_uuid is null;
> ```

### Tester concrètement
Crée deux comptes de test, ajoute un trade sur chacun, puis vérifie que le compte A
ne voit jamais le trade du compte B. Si c'est le cas, la base est correctement cloisonnée.

---

## `002_reparation_comptes.sql` — à exécuter après le 001

### Pourquoi
Un trade est rattaché à un compte de trading par `trades.user_id`. Si la ligne
correspondante dans `accounts` disparaît, les trades restent en base mais l'app n'a
plus aucun compte à sélectionner pour les afficher : ils deviennent **invisibles**
sans être perdus, et rien dans l'interface ne permet de les retrouver.

C'est exactement ce qui s'était produit sur le projet : **596 trades sur 700**
étaient dans ce cas.

La cause côté code (`deleteAccount`) est corrigée : supprimer un compte supprime
désormais ses trades, après avoir affiché leur nombre. Ce script répare les dégâts
déjà en base.

### Ce que fait le script
| Étape | Effet |
|---|---|
| 1 | Recrée les comptes manquants → les trades invisibles réapparaissent |
| 2 | Réécrit les 8 règles RLS en `(select auth.uid())` — même protection, sans ré-évaluation ligne par ligne |
| 3 | Supprime les index en double (chaque écriture devait en maintenir deux) |
| 4 | Affiche un tableau de vérification |
| 5 | **Rien** — la suppression des doublons est en commentaire, à toi de décider |

Aucun trade n'est supprimé. Le capital des comptes recréés est déduit des trades
eux-mêmes (`risk_amt ÷ risk_pct`) ; vérifie-le et corrige-le dans l'app si besoin.

### Comment l'exécuter
Dashboard Supabase → **SQL Editor** → **New query** → coller → **Run**.

### Vérifier
| Contrôle | Résultat attendu |
|---|---|
| Trades invisibles (sans compte) | `0` |
| Trades sans propriétaire | `0` |
| Sécurité active | `true` pour les deux tables |
| Règles en place | `8` |

Les comptes dont tous les trades portent le même horodatage sont nommés
`Import du JJ/MM` : c'est la signature d'un import CSV en un bloc. Si tu vois
plusieurs comptes avec le même nombre de trades et le même P&L, c'est le même
fichier importé plusieurs fois — tu peux les supprimer depuis l'app.
