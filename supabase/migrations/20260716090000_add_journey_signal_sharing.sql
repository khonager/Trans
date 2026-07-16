-- Journey Signal: cumulative friend visibility levels with per-friend overrides.
-- Legacy ghost_mode and user_locations columns remain writable during the
-- rollout, while friend reads move to the tier-masking RPC below.

alter table public.profiles
  add column if not exists signal_level smallint;

update public.profiles
set signal_level = case when coalesce(ghost_mode, false) then 0 else 1 end
where signal_level is null;

alter table public.profiles
  alter column signal_level set default 0,
  alter column signal_level set not null;

alter table public.profiles
  drop constraint if exists profiles_signal_level_check;
alter table public.profiles
  add constraint profiles_signal_level_check check (signal_level between 0 and 8);

create or replace function public.sync_profile_signal_and_ghost()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.signal_level := coalesce(new.signal_level, 0);
    new.ghost_mode := new.signal_level = 0;
  elsif new.signal_level is distinct from old.signal_level then
    new.ghost_mode := new.signal_level = 0;
  elsif new.ghost_mode is distinct from old.ghost_mode then
    new.signal_level := case
      when new.ghost_mode then 0
      else greatest(coalesce(old.signal_level, 0), 1)
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists sync_profile_signal_and_ghost on public.profiles;
create trigger sync_profile_signal_and_ghost
before insert or update of signal_level, ghost_mode on public.profiles
for each row execute function public.sync_profile_signal_and_ghost();
revoke all on function public.sync_profile_signal_and_ghost() from public, anon, authenticated;

create table if not exists public.friend_sharing_overrides (
  owner_id uuid not null references auth.users(id) on delete cascade,
  friend_id uuid not null references auth.users(id) on delete cascade,
  signal_level smallint not null check (signal_level between 0 and 8),
  updated_at timestamptz not null default now(),
  primary key (owner_id, friend_id),
  check (owner_id <> friend_id)
);

alter table public.friend_sharing_overrides enable row level security;
revoke all on public.friend_sharing_overrides from anon;
grant select, insert, update, delete on public.friend_sharing_overrides to authenticated;

drop policy if exists friend_sharing_overrides_owner_all on public.friend_sharing_overrides;
create policy friend_sharing_overrides_owner_all
on public.friend_sharing_overrides
for all to authenticated
using (owner_id = (select auth.uid()))
with check (
  owner_id = (select auth.uid())
  and exists (
    select 1 from public.friends f
    where (f.user_id = owner_id and f.friend_id = friend_sharing_overrides.friend_id)
       or (f.friend_id = owner_id and f.user_id = friend_sharing_overrides.friend_id)
  )
);

create table if not exists public.journey_presence (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  journey_id text,
  is_active boolean not null default false,
  current_line text,
  departure_at timestamptz,
  arrival_at timestamptz,
  destination_name text,
  itinerary jsonb not null default '[]'::jsonb,
  progress double precision check (progress is null or progress between 0 and 1),
  progress_label text,
  latitude double precision,
  longitude double precision,
  accuracy_m double precision,
  location_is_journey boolean not null default false,
  updated_at timestamptz not null default now(),
  line_expires_at timestamptz,
  journey_expires_at timestamptz
);

create table if not exists public.private_profile_favorites (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  favorites jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

insert into public.private_profile_favorites(owner_id, favorites)
select id, public.sanitize_profile_favorites(coalesce(favorites::jsonb, '[]'::jsonb))
from public.profiles
on conflict (owner_id) do update
set favorites = excluded.favorites, updated_at = now();

update public.profiles set favorites = '[]'::jsonb where favorites is not null;

alter table public.private_profile_favorites enable row level security;
revoke all on public.private_profile_favorites from anon;
grant select, insert, update, delete on public.private_profile_favorites to authenticated;

drop policy if exists private_profile_favorites_owner_all on public.private_profile_favorites;
create policy private_profile_favorites_owner_all
on public.private_profile_favorites
for all to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

create or replace function public.divert_profile_favorites_to_private()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.favorites is distinct from old.favorites and new.id = auth.uid() then
    insert into public.private_profile_favorites(owner_id, favorites, updated_at)
    values (
      new.id,
      public.sanitize_profile_favorites(coalesce(new.favorites::jsonb, '[]'::jsonb)),
      now()
    )
    on conflict (owner_id) do update
    set favorites = excluded.favorites, updated_at = excluded.updated_at;
  end if;
  new.favorites := '[]'::jsonb;
  return new;
end;
$$;

drop trigger if exists divert_profile_favorites_to_private on public.profiles;
create trigger divert_profile_favorites_to_private
before update of favorites on public.profiles
for each row execute function public.divert_profile_favorites_to_private();
revoke all on function public.divert_profile_favorites_to_private() from public, anon, authenticated;

alter table public.journey_presence enable row level security;
revoke all on public.journey_presence from anon;
grant select, insert, update, delete on public.journey_presence to authenticated;

drop policy if exists journey_presence_owner_all on public.journey_presence;
create policy journey_presence_owner_all
on public.journey_presence
for all to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

create index if not exists friend_sharing_overrides_friend_idx
  on public.friend_sharing_overrides(friend_id);
create index if not exists journey_presence_updated_idx
  on public.journey_presence(updated_at);

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.are_friends(first_id uuid, second_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.friends f
    where (f.user_id = first_id and f.friend_id = second_id)
       or (f.friend_id = first_id and f.user_id = second_id)
  ) and not exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = first_id and b.blocked_id = second_id)
       or (b.blocker_id = second_id and b.blocked_id = first_id)
  );
$$;

create or replace function private.effective_signal_level(owner uuid, viewer uuid)
returns smallint
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not private.are_friends(owner, viewer) then 0::smallint
    else coalesce(
      (select o.signal_level from public.friend_sharing_overrides o
       where o.owner_id = owner and o.friend_id = viewer),
      (select p.signal_level from public.profiles p where p.id = owner),
      0
    )::smallint
  end;
$$;

create or replace function public.get_friend_journey_presence()
returns table (
  friend_id uuid,
  signal_level smallint,
  current_line text,
  departure_at timestamptz,
  arrival_at timestamptz,
  destination_name text,
  itinerary jsonb,
  progress double precision,
  progress_label text,
  latitude double precision,
  longitude double precision,
  accuracy_m double precision,
  is_active boolean,
  updated_at timestamptz,
  favorites jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  with my_friends as (
    select case when f.user_id = auth.uid() then f.friend_id else f.user_id end as id
    from public.friends f
    where f.user_id = auth.uid() or f.friend_id = auth.uid()
  ), allowed as (
    select mf.id, private.effective_signal_level(mf.id, auth.uid()) as level
    from my_friends mf
  )
  select
    a.id,
    a.level,
    case when a.level >= 1 and jp.line_expires_at > now() then jp.current_line end,
    case when a.level >= 2 and jp.is_active and jp.journey_expires_at > now() then jp.departure_at end,
    case when a.level >= 2 and jp.is_active and jp.journey_expires_at > now() then jp.arrival_at end,
    case when a.level >= 3 and jp.is_active and jp.journey_expires_at > now() then jp.destination_name end,
    case when a.level >= 4 and jp.is_active and jp.journey_expires_at > now() then jp.itinerary else '[]'::jsonb end,
    case when a.level >= 5 and jp.is_active and jp.journey_expires_at > now() then jp.progress end,
    case when a.level >= 5 and jp.is_active and jp.journey_expires_at > now() then jp.progress_label end,
    case when (a.level >= 6 and jp.is_active and jp.location_is_journey and jp.journey_expires_at > now()) or a.level >= 7 then jp.latitude end,
    case when (a.level >= 6 and jp.is_active and jp.location_is_journey and jp.journey_expires_at > now()) or a.level >= 7 then jp.longitude end,
    case when (a.level >= 6 and jp.is_active and jp.location_is_journey and jp.journey_expires_at > now()) or a.level >= 7 then jp.accuracy_m end,
    case when a.level >= 2 and jp.journey_expires_at > now() then jp.is_active else false end,
    case when a.level >= 1 then jp.updated_at end,
    case when a.level >= 8 then coalesce(pf.favorites, '[]'::jsonb) else '[]'::jsonb end
  from allowed a
  left join public.journey_presence jp on jp.owner_id = a.id
  left join public.private_profile_favorites pf on pf.owner_id = a.id
  where a.level > 0;
$$;

revoke all on function public.get_friend_journey_presence() from public, anon;
grant execute on function public.get_friend_journey_presence() to authenticated;

create or replace function public.set_my_signal_level(requested_level integer)
returns smallint
language plpgsql
security definer
set search_path = ''
as $$
declare normalized smallint;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  normalized := greatest(0, least(8, requested_level))::smallint;
  update public.profiles
  set signal_level = normalized, ghost_mode = normalized = 0
  where id = auth.uid();
  if normalized = 0 then
    delete from public.journey_presence where owner_id = auth.uid();
    delete from public.user_locations where user_id = auth.uid();
  end if;
  return normalized;
end;
$$;

revoke all on function public.set_my_signal_level(integer) from public, anon;
grant execute on function public.set_my_signal_level(integer) to authenticated;

-- Old clients can still read user_locations. Restrict those reads to the owner;
-- new clients use get_friend_journey_presence(), which masks every tier server-side.
drop policy if exists user_locations_select_self_or_friends on public.user_locations;
drop policy if exists user_locations_select_own on public.user_locations;
create policy user_locations_select_own
on public.user_locations for select to authenticated
using (user_id = (select auth.uid()));
