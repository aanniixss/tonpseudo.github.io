# `delete-account` — suppression définitive du compte (RGPD art. 17)

Supprime, pour l'utilisateur **authentifié uniquement** :
1. tous ses trades,
2. tous ses comptes de trading,
3. son compte d'accès (`auth.users`).

## Sécurité
L'identité vient du jeton d'authentification envoyé dans l'en-tête `Authorization`,
jamais d'un identifiant transmis par le navigateur. Un utilisateur ne peut donc
supprimer que son propre compte.

## Déploiement
```bash
supabase functions deploy delete-account
```
Aucun secret à configurer : `SUPABASE_URL`, `SUPABASE_ANON_KEY` et
`SUPABASE_SERVICE_ROLE_KEY` sont injectés automatiquement par Supabase.

> ⚠️ Ne pas déployer avec `--no-verify-jwt` : la vérification du jeton est
> précisément ce qui empêche un tiers de supprimer le compte de quelqu'un d'autre.

## Comportement côté application
Si la fonction n'est pas encore déployée, l'application efface malgré tout toutes
les données de l'utilisateur (trades et comptes) puis le déconnecte, et l'informe
que l'identifiant de connexion doit être supprimé manuellement. Le droit à
l'effacement reste donc exerçable même avant déploiement.
