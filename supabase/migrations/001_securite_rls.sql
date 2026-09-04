-- ════════════════════════════════════════════════════════════════════════
--  BAKOU — Sécurisation de la base (Row Level Security)
--  À exécuter dans : Supabase → SQL Editor → New query → Run
--
--  ⚠️  CRITIQUE AVANT TOUTE COMMERCIALISATION
--  Sans ces règles, la clé publique (anon) présente dans le code du site
--  permet à n'importe qui de lire, modifier et supprimer les données de
--  TOUS les utilisateurs. Avec ces règles, la base refuse elle-même tout
--  accès aux données d'autrui, même si le code du navigateur est modifié.
--
--  Ce script est idempotent : tu peux le relancer sans risque.
-- ════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────
-- ÉTAPE 1 — Colonne propriétaire, rattachée au compte authentifié
-- ───────────────────────────────────────────────────────────────────────
alter table public.accounts add column if not exists owner_uuid uuid references auth.users(id) on delete cascade;
alter table public.trades   add column if not exists owner_uuid uuid references auth.users(id) on delete cascade;

-- ───────────────────────────────────────────────────────────────────────
-- ÉTAPE 2 — Reprise des données existantes
--   Les trades héritent du propriétaire de leur compte de trading.
--   ⚠️ Vérifie le résultat de l'ÉTAPE 6 avant d'activer la sécurité :
--      toute ligne dont owner_uuid reste NULL deviendra invisible.
-- ───────────────────────────────────────────────────────────────────────
update public.trades t
   set owner_uuid = a.owner_uuid
  from public.accounts a
 where t.user_id = a.id
   and t.owner_uuid is null
   and a.owner_uuid is not null;

-- ───────────────────────────────────────────────────────────────────────
-- ÉTAPE 3 — Index (indispensables : sans eux, chaque lecture scanne
--            toute la table et le service ralentit avec le nombre d'inscrits)
-- ───────────────────────────────────────────────────────────────────────
create index if not exists idx_accounts_owner_uuid on public.accounts(owner_uuid);
create index if not exists idx_trades_owner_uuid   on public.trades(owner_uuid);
create index if not exists idx_trades_user_id      on public.trades(user_id);
create index if not exists idx_trades_owner_year   on public.trades(owner_uuid, trade_year);

-- ───────────────────────────────────────────────────────────────────────
-- ÉTAPE 4 — Activation de la sécurité au niveau des lignes
-- ───────────────────────────────────────────────────────────────────────
alter table public.accounts enable row level security;
alter table public.trades   enable row level security;

-- Nettoyage d'éventuelles règles antérieures (permissives ou en double)
do $$
declare r record;
begin
  for r in select policyname, tablename from pg_policies
            where schemaname='public' and tablename in ('accounts','trades')
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- ───────────────────────────────────────────────────────────────────────
-- ÉTAPE 5 — Règles : chacun ne voit et ne touche QUE ses propres données
-- ───────────────────────────────────────────────────────────────────────
create policy "accounts_select_own" on public.accounts
  for select to authenticated using (auth.uid() = owner_uuid);
create policy "accounts_insert_own" on public.accounts
  for insert to authenticated with check (auth.uid() = owner_uuid);
create policy "accounts_update_own" on public.accounts
  for update to authenticated using (auth.uid() = owner_uuid) with check (auth.uid() = owner_uuid);
create policy "accounts_delete_own" on public.accounts
  for delete to authenticated using (auth.uid() = owner_uuid);

create policy "trades_select_own" on public.trades
  for select to authenticated using (auth.uid() = owner_uuid);
create policy "trades_insert_own" on public.trades
  for insert to authenticated with check (auth.uid() = owner_uuid);
create policy "trades_update_own" on public.trades
  for update to authenticated using (auth.uid() = owner_uuid) with check (auth.uid() = owner_uuid);
create policy "trades_delete_own" on public.trades
  for delete to authenticated using (auth.uid() = owner_uuid);

-- ───────────────────────────────────────────────────────────────────────
-- ÉTAPE 6 — Vérification (à lire avant de considérer le travail terminé)
-- ───────────────────────────────────────────────────────────────────────
select 'Lignes orphelines — DOIT afficher 0 partout' as controle;
select 'accounts sans proprietaire' as table_, count(*) as lignes_invisibles
  from public.accounts where owner_uuid is null
union all
select 'trades sans proprietaire', count(*)
  from public.trades where owner_uuid is null;

select 'Securite active — DOIT afficher true partout' as controle;
select relname as table_, relrowsecurity as securite_activee
  from pg_class where relname in ('accounts','trades');

select 'Regles en place — DOIT afficher 8 lignes' as controle;
select tablename, policyname, cmd
  from pg_policies where schemaname='public' and tablename in ('accounts','trades')
  order by tablename, cmd;
