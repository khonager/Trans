-- Rename the persisted sharing tier without changing any existing values.
-- Deploy this with the app version that reads privacy_level and calls
-- set_my_privacy_level.

alter table public.profiles
  rename column signal_level to privacy_level;
alter table public.profiles
  rename constraint profiles_signal_level_check to profiles_privacy_level_check;

alter table public.friend_sharing_overrides
  rename column signal_level to privacy_level;
alter table public.friend_sharing_overrides
  rename constraint friend_sharing_overrides_signal_level_check
  to friend_sharing_overrides_privacy_level_check;

drop trigger if exists sync_profile_signal_and_ghost on public.profiles;
drop function if exists public.sync_profile_signal_and_ghost();

create function public.sync_profile_privacy_and_ghost()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.privacy_level := coalesce(new.privacy_level, 0);
    new.ghost_mode := new.privacy_level = 0;
  elsif new.privacy_level is distinct from old.privacy_level then
    new.ghost_mode := new.privacy_level = 0;
  elsif new.ghost_mode is distinct from old.ghost_mode then
    new.privacy_level := case
      when new.ghost_mode then 0
      else greatest(coalesce(old.privacy_level, 0), 1)
    end;
  end if;
  return new;
end;
$$;

create trigger sync_profile_privacy_and_ghost
before insert or update of privacy_level, ghost_mode on public.profiles
for each row execute function public.sync_profile_privacy_and_ghost();
revoke all on function public.sync_profile_privacy_and_ghost() from public, anon, authenticated;

drop function if exists public.get_friend_journey_presence();
drop function if exists private.effective_signal_level(uuid, uuid);
create function private.effective_privacy_level(owner uuid, viewer uuid)
returns smallint
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not private.are_friends(owner, viewer) then 0::smallint
    else coalesce(
      (select o.privacy_level from public.friend_sharing_overrides o
       where o.owner_id = owner and o.friend_id = viewer),
      (select p.privacy_level from public.profiles p where p.id = owner),
      0
    )::smallint
  end;
$$;

create function public.get_friend_journey_presence()
returns table (
  friend_id uuid,
  privacy_level smallint,
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
    select mf.id, private.effective_privacy_level(mf.id, auth.uid()) as level
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

drop function if exists public.set_my_signal_level(integer);
create function public.set_my_privacy_level(requested_level integer)
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
  set privacy_level = normalized, ghost_mode = normalized = 0
  where id = auth.uid();
  if normalized = 0 then
    delete from public.journey_presence where owner_id = auth.uid();
    delete from public.user_locations where user_id = auth.uid();
  end if;
  return normalized;
end;
$$;
revoke all on function public.set_my_privacy_level(integer) from public, anon;
grant execute on function public.set_my_privacy_level(integer) to authenticated;
