-- Synchronisation des réglages et notes entre appareils (stratégie, bilans, plan, règles, objectifs)
create table if not exists public.user_kv (
  owner_uuid uuid not null default auth.uid() references auth.users(id) on delete cascade,
  k text not null,
  v text,
  updated_at timestamptz not null default now(),
  primary key (owner_uuid, k)
);
alter table public.user_kv enable row level security;
create policy user_kv_select_own on public.user_kv for select using ((select auth.uid()) = owner_uuid);
create policy user_kv_insert_own on public.user_kv for insert with check ((select auth.uid()) = owner_uuid);
create policy user_kv_update_own on public.user_kv for update using ((select auth.uid()) = owner_uuid) with check ((select auth.uid()) = owner_uuid);
create policy user_kv_delete_own on public.user_kv for delete using ((select auth.uid()) = owner_uuid);
