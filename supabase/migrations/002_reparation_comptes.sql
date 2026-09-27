-- ════════════════════════════════════════════════════════════════════════
--  BAKOU — Réparation des comptes de trading + optimisation
--  À exécuter dans : Supabase → SQL Editor → New query → coller → Run
--
--  Ce script est idempotent : tu peux le relancer sans risque.
--  Il ne SUPPRIME AUCUN trade. La partie suppression (doublons) est
--  volontairement laissée en commentaire à la fin — à toi de décider.
-- ════════════════════════════════════════════════════════════════════════


-- ───────────────────────────────────────────────────────────────────────
-- ÉTAPE 1 — Récupérer les trades devenus invisibles
--
--   Le problème : un trade pointe vers un compte de trading par
--   trades.user_id. Si la ligne correspondante dans accounts a disparu
--   (compte supprimé, bug forceRecover, import raté), les trades restent
--   en base mais l'app n'a plus aucun compte à sélectionner pour les
--   afficher. Ils deviennent invisibles sans être perdus.
--
--   La réparation : pour chaque groupe de trades orphelins, on recrée le
--   compte manquant. Le capital est déduit des trades eux-mêmes
--   (risk_amt / risk_pct), la date de création est celle du plus ancien
--   trade pour que l'ordre dans la barre latérale reste logique.
-- ───────────────────────────────────────────────────────────────────────
insert into public.accounts (id, owner_id, name, capital, risk, color, created_at, owner_uuid)
select t.user_id,
       -- owner_id historique : repris d'un autre compte du même
       -- propriétaire, sinon reconstruit depuis l'identifiant
       -- ('user_cmqlipot4_ftmo1782…' → 'user_cmqlipot4').
       coalesce(
         (select a2.owner_id from public.accounts a2
           where a2.owner_uuid = t.owner_uuid limit 1),
         split_part(t.user_id, '_', 1) || '_' || split_part(t.user_id, '_', 2)
       ),
       -- Nom lisible, renommable dans l'app ensuite :
       --   · tous les trades enregistrés à la même seconde = import CSV
       --     en un bloc → « Import du JJ/MM » (permet de repérer d'un
       --     coup d'œil un même fichier importé plusieurs fois) ;
       --   · sinon on déduit du suffixe : 'acc1' → Compte récupéré,
       --     'ftmo1782795906273' → FTMO.
       case
         when count(distinct t.created_at) = 1
           then 'Import du ' || to_char(min(t.created_at), 'DD/MM')
         when regexp_replace(regexp_replace(t.user_id, '^[^_]+_[^_]+_', ''), '[0-9]+$', '') in ('acc', '')
           then 'Compte récupéré'
         else upper(regexp_replace(regexp_replace(t.user_id, '^[^_]+_[^_]+_', ''), '[0-9]+$', ''))
       end,
       -- Capital déduit : risque en $ ÷ risque en % (0 si indéductible)
       coalesce(round(avg(
         case when t.risk_pct > 0 and t.risk_amt > 0
              then t.risk_amt / (t.risk_pct / 100.0) end
       )::numeric, 0), 0),
       coalesce(round(avg(nullif(t.risk_pct, 0))::numeric, 2), 1),
       '#6366f1',
       min(t.created_at),
       t.owner_uuid
  from public.trades t
 where t.owner_uuid is not null
   and not exists (select 1 from public.accounts a where a.id = t.user_id)
 group by t.user_id, t.owner_uuid
on conflict (id) do nothing;


-- ───────────────────────────────────────────────────────────────────────
-- ÉTAPE 2 — Règles de sécurité : même protection, mais rapides
--
--   auth.uid() écrit tel quel est ré-évalué UNE FOIS PAR LIGNE. Sur 700
--   trades ça ne se voit pas ; sur 200 clients à 2 000 trades, chaque
--   chargement de page fait ramer la base. Entouré de (select ...),
--   Postgres l'évalue une seule fois par requête.
--   La protection est EXACTEMENT la même : chacun ne voit que ses données.
-- ───────────────────────────────────────────────────────────────────────
do $$
declare r record;
begin
  for r in select policyname, tablename from pg_policies
            where schemaname = 'public' and tablename in ('accounts','trades')
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

create policy "accounts_select_own" on public.accounts
  for select to authenticated using ((select auth.uid()) = owner_uuid);
create policy "accounts_insert_own" on public.accounts
  for insert to authenticated with check ((select auth.uid()) = owner_uuid);
create policy "accounts_update_own" on public.accounts
  for update to authenticated using ((select auth.uid()) = owner_uuid)
                               with check ((select auth.uid()) = owner_uuid);
create policy "accounts_delete_own" on public.accounts
  for delete to authenticated using ((select auth.uid()) = owner_uuid);

create policy "trades_select_own" on public.trades
  for select to authenticated using ((select auth.uid()) = owner_uuid);
create policy "trades_insert_own" on public.trades
  for insert to authenticated with check ((select auth.uid()) = owner_uuid);
create policy "trades_update_own" on public.trades
  for update to authenticated using ((select auth.uid()) = owner_uuid)
                             with check ((select auth.uid()) = owner_uuid);
create policy "trades_delete_own" on public.trades
  for delete to authenticated using ((select auth.uid()) = owner_uuid);


-- ───────────────────────────────────────────────────────────────────────
-- ÉTAPE 3 — Index en double
--
--   Deux index identiques sur la même colonne : la lecture n'est pas plus
--   rapide, mais CHAQUE écriture doit mettre les deux à jour. On garde un
--   seul index par colonne.
-- ───────────────────────────────────────────────────────────────────────
drop index if exists public.accounts_owner_uuid_idx;
drop index if exists public.trades_owner_uuid_idx;

create index if not exists idx_accounts_owner_uuid on public.accounts(owner_uuid);
create index if not exists idx_trades_owner_uuid   on public.trades(owner_uuid);
create index if not exists idx_trades_user_id      on public.trades(user_id);
create index if not exists idx_trades_owner_year   on public.trades(owner_uuid, trade_year);


-- ───────────────────────────────────────────────────────────────────────
-- ÉTAPE 3 bis — Suppression en cascade
--
--   Les clés étrangères vers auth.users ont été créées SANS « on delete
--   cascade ». Conséquence : supprimer un utilisateur depuis
--   Authentication → Users échoue avec une erreur de contrainte, parce
--   que ses trades le référencent encore. Avec la cascade, supprimer le
--   compte d'accès efface automatiquement ses comptes et ses trades —
--   c'est ce qu'exige le RGPD (art. 17, droit à l'effacement).
-- ───────────────────────────────────────────────────────────────────────
alter table public.trades   drop constraint if exists trades_owner_uuid_fkey;
alter table public.accounts drop constraint if exists accounts_owner_uuid_fkey;

alter table public.trades
  add constraint trades_owner_uuid_fkey
  foreign key (owner_uuid) references auth.users(id) on delete cascade;
alter table public.accounts
  add constraint accounts_owner_uuid_fkey
  foreign key (owner_uuid) references auth.users(id) on delete cascade;


-- ───────────────────────────────────────────────────────────────────────
-- ÉTAPE 4 — Vérification (un seul tableau : l'éditeur SQL n'affiche que
--            le résultat de la DERNIÈRE requête)
-- ───────────────────────────────────────────────────────────────────────
select controle, objet, valeur from (
  select 1 as ordre, 'Trades invisibles — doit etre 0' as controle, 'sans compte' as objet,
         count(*)::text as valeur
    from public.trades t
   where not exists (select 1 from public.accounts a where a.id = t.user_id)
  union all
  select 2, 'Trades invisibles — doit etre 0', 'sans proprietaire', count(*)::text
    from public.trades where owner_uuid is null
  union all
  select 3, 'Securite active — doit etre true', relname::text, relrowsecurity::text
    from pg_class where relname in ('accounts','trades') and relnamespace = 'public'::regnamespace
  union all
  select 4, 'Regles en place — doit etre 8', 'total', count(*)::text
    from pg_policies where schemaname = 'public' and tablename in ('accounts','trades')
  union all
  select 5, 'Cascade RGPD — doit etre 2', 'cles en cascade', count(*)::text
    from pg_constraint
   where conname in ('trades_owner_uuid_fkey','accounts_owner_uuid_fkey')
     and confdeltype = 'c'
  union all
  select 6, 'Volume', 'comptes', count(*)::text from public.accounts
  union all
  select 7, 'Volume', 'trades', count(*)::text from public.trades
) x order by ordre, objet;


-- ════════════════════════════════════════════════════════════════════════
--  ÉTAPE 5 — DOUBLONS  ⚠️  NE RIEN LANCER ICI SANS AVOIR LU
--
--  Un même import CSV a été enregistré 3 fois sous 3 comptes différents :
--  102 trades identiques × 3, soit 204 lignes en trop. Contenu vérifié
--  ligne par ligne : ce sont bien des copies exactes (même paire, même
--  direction, même résultat, même P&L, même mois).
--
--  Pour les VOIR avant de décider — lance uniquement cette requête :
--
--    select user_id, count(*) as nb, min(created_at) as importe_le,
--           round(sum(pnl_amt)::numeric,2) as pnl
--      from public.trades
--     where user_id in ('user_cmqlipot4_acc1782769597713',
--                       'user_cmqlipot4_acc1782770873689',
--                       'user_cmqlipot4_acc1782790960891')
--     group by user_id order by importe_le;
--
--  Pour les SUPPRIMER — décommente les 3 lignes ci-dessous. On garde
--  'acc1782769597713' (le compte « 100k », l'import d'origine) et on
--  supprime les deux copies. C'EST DÉFINITIF.
--
--  delete from public.trades
--   where user_id in ('user_cmqlipot4_acc1782770873689',
--                     'user_cmqlipot4_acc1782790960891');
--
--  delete from public.accounts
--   where id in ('user_cmqlipot4_acc1782770873689',
--                'user_cmqlipot4_acc1782790960891');
-- ════════════════════════════════════════════════════════════════════════
