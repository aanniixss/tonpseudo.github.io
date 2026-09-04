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
