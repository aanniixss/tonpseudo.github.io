-- ═══════════════════════════════════════════════════════════════
-- 003 — Le Notebook passe en base
-- Avant : les notes vivaient uniquement dans le localStorage du
-- navigateur. Vider le cache = tout perdre, et aucune synchro
-- entre le telephone et le PC. Ces deux tables corrigent ca.
-- Idempotent : peut etre rejoue sans risque.
-- ═══════════════════════════════════════════════════════════════

create table if not exists public.nb_folders (
  id          text primary key,
  owner_uuid  uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  color       text default '#3b82f6',
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

create table if not exists public.nb_notes (
  id          text primary key,
  owner_uuid  uuid not null references auth.users(id) on delete cascade,
  folder_id   text,
  title       text default '',
  html        text default '',
  tags        text default '[]',
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

create index if not exists nb_folders_owner_idx on public.nb_folders(owner_uuid);
create index if not exists nb_notes_owner_idx   on public.nb_notes(owner_uuid);

alter table public.nb_folders enable row level security;
alter table public.nb_notes   enable row level security;

-- RLS : chacun ne voit que ses propres notes.
-- (select auth.uid()) et pas auth.uid() : l'appel est evalue une
-- seule fois par requete au lieu d'une fois par ligne.
drop policy if exists nb_folders_select on public.nb_folders;
drop policy if exists nb_folders_insert on public.nb_folders;
drop policy if exists nb_folders_update on public.nb_folders;
drop policy if exists nb_folders_delete on public.nb_folders;

create policy nb_folders_select on public.nb_folders for select
  using ((select auth.uid()) = owner_uuid);
create policy nb_folders_insert on public.nb_folders for insert
  with check ((select auth.uid()) = owner_uuid);
create policy nb_folders_update on public.nb_folders for update
  using ((select auth.uid()) = owner_uuid) with check ((select auth.uid()) = owner_uuid);
create policy nb_folders_delete on public.nb_folders for delete
  using ((select auth.uid()) = owner_uuid);

drop policy if exists nb_notes_select on public.nb_notes;
drop policy if exists nb_notes_insert on public.nb_notes;
drop policy if exists nb_notes_update on public.nb_notes;
drop policy if exists nb_notes_delete on public.nb_notes;

create policy nb_notes_select on public.nb_notes for select
  using ((select auth.uid()) = owner_uuid);
create policy nb_notes_insert on public.nb_notes for insert
  with check ((select auth.uid()) = owner_uuid);
create policy nb_notes_update on public.nb_notes for update
  using ((select auth.uid()) = owner_uuid) with check ((select auth.uid()) = owner_uuid);
create policy nb_notes_delete on public.nb_notes for delete
  using ((select auth.uid()) = owner_uuid);

-- Verification
select 'nb_folders' as t, count(*) from public.nb_folders
union all
select 'nb_notes', count(*) from public.nb_notes;
