create or replace function public.sanitize_profile_favorites(
  favorites_input jsonb
)
returns jsonb
language sql
immutable
as $$
  select coalesce(
    (
      select jsonb_agg(favorite)
      from jsonb_array_elements(coalesce(favorites_input, '[]'::jsonb)) favorite
      where favorite ->> 'type' = 'station'
    ),
    '[]'::jsonb
  );
$$;

create or replace function public.sanitize_profile_favorites_before_write()
returns trigger
language plpgsql
as $$
begin
  if new.favorites is not null then
    new.favorites := public.sanitize_profile_favorites(new.favorites::jsonb);
  end if;

  return new;
end;
$$;

do $$
begin
  if to_regclass('public.user_locations') is null then
    return;
  end if;

  alter table public.user_locations enable row level security;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'user_locations'
      and policyname = 'user_locations_select_self_or_friends'
  ) then
    if to_regclass('public.friends') is not null then
      create policy user_locations_select_self_or_friends
      on public.user_locations
      for select
      to authenticated
      using (
        auth.uid() = user_id
        or exists (
          select 1
          from public.friends friend_link
          where (
              friend_link.user_id = auth.uid()
              and friend_link.friend_id = user_locations.user_id
            )
            or (
              friend_link.friend_id = auth.uid()
              and friend_link.user_id = user_locations.user_id
            )
        )
      );
    else
      create policy user_locations_select_self_or_friends
      on public.user_locations
      for select
      to authenticated
      using (auth.uid() = user_id);
    end if;
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'user_locations'
      and policyname = 'user_locations_insert_own'
  ) then
    create policy user_locations_insert_own
    on public.user_locations
    for insert
    to authenticated
    with check (auth.uid() = user_id);
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'user_locations'
      and policyname = 'user_locations_update_own'
  ) then
    create policy user_locations_update_own
    on public.user_locations
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'user_locations'
      and policyname = 'user_locations_delete_own'
  ) then
    create policy user_locations_delete_own
    on public.user_locations
    for delete
    to authenticated
    using (auth.uid() = user_id);
  end if;
end;
$$;

do $$
begin
  if to_regclass('public.profiles') is null then
    return;
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'favorites'
  ) then
    return;
  end if;

  update public.profiles
  set favorites = public.sanitize_profile_favorites(favorites::jsonb)
  where favorites is not null;

  if not exists (
    select 1
    from pg_trigger
    where tgname = 'sanitize_profile_favorites_before_write'
      and tgrelid = 'public.profiles'::regclass
  ) then
    create trigger sanitize_profile_favorites_before_write
    before insert or update of favorites on public.profiles
    for each row
    execute function public.sanitize_profile_favorites_before_write();
  end if;
end;
$$;
