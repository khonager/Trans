create table if not exists public.trans_color_claims (
  hex_id text primary key,
  hex text not null check (hex ~ '^#[0-9a-f]{6}$'),
  app_id text not null default 'trans',
  active boolean not null default true,
  external_user_id uuid not null references auth.users(id) on delete cascade,
  linked_portfolio_uid text,
  owner_label text,
  claimed_at timestamptz not null default timezone('utc', now()),
  last_active_at timestamptz not null default timezone('utc', now()),
  released_at timestamptz,
  updated_at timestamptz not null default timezone('utc', now()),
  synced_at timestamptz,
  sync_state text,
  sync_error text
);

create unique index if not exists trans_color_claims_active_user_idx
  on public.trans_color_claims (external_user_id)
  where active = true;

create index if not exists trans_color_claims_active_hex_idx
  on public.trans_color_claims (hex, active);

alter table public.trans_color_claims enable row level security;

drop policy if exists "Authenticated users can read Trans color claims"
  on public.trans_color_claims;
create policy "Authenticated users can read Trans color claims"
  on public.trans_color_claims
  for select
  to authenticated
  using (true);

drop policy if exists "Users can insert their own Trans color claims"
  on public.trans_color_claims;
create policy "Users can insert their own Trans color claims"
  on public.trans_color_claims
  for insert
  to authenticated
  with check (auth.uid() = external_user_id);

drop policy if exists "Users can update their own Trans color claims"
  on public.trans_color_claims;
create policy "Users can update their own Trans color claims"
  on public.trans_color_claims
  for update
  to authenticated
  using (auth.uid() = external_user_id)
  with check (auth.uid() = external_user_id);
