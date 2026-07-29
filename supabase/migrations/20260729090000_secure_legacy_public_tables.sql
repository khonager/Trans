-- Lock down the legacy tables that predate the checked-in Supabase migrations.
-- Full profile rows are private. Other users are represented only by the
-- deliberately small RPC result shapes at the bottom of this migration.

do $$
declare
  target_table text;
  existing_policy record;
begin
  foreach target_table in array array[
    'profiles',
    'friends',
    'friend_requests',
    'messages',
    'user_blocks',
    'user_locations'
  ]
  loop
    if to_regclass(format('public.%I', target_table)) is null then
      continue;
    end if;

    execute format(
      'alter table public.%I enable row level security',
      target_table
    );
    execute format('revoke all on table public.%I from anon', target_table);

    -- Replace unknown Dashboard-era policies as well as policies created by
    -- earlier migrations. A single permissive policy would otherwise widen
    -- every restrictive policy below.
    for existing_policy in
      select policyname
      from pg_policies
      where schemaname = 'public' and tablename = target_table
    loop
      execute format(
        'drop policy %I on public.%I',
        existing_policy.policyname,
        target_table
      );
    end loop;
  end loop;
end;
$$;

create or replace function public.can_interact_with(other_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and other_user_id is not null
    and other_user_id <> auth.uid()
    and not exists (
      select 1
      from public.user_blocks block
      where (
        block.blocker_id = auth.uid()
        and block.blocked_id = other_user_id
      ) or (
        block.blocker_id = other_user_id
        and block.blocked_id = auth.uid()
      )
    );
$$;

revoke all on function public.can_interact_with(uuid) from public, anon;
grant execute on function public.can_interact_with(uuid) to authenticated;

create or replace function public.is_friend_with(other_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.can_interact_with(other_user_id)
    and exists (
      select 1
      from public.friends friend_link
      where (
        friend_link.user_id = auth.uid()
        and friend_link.friend_id = other_user_id
      ) or (
        friend_link.friend_id = auth.uid()
        and friend_link.user_id = other_user_id
      )
    );
$$;

revoke all on function public.is_friend_with(uuid) from public, anon;
grant execute on function public.is_friend_with(uuid) to authenticated;

create or replace function public.accept_friend_request(
  request_sender_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if request_sender_id is null or request_sender_id = current_user_id then
    raise exception 'Invalid friend request sender';
  end if;
  if not public.can_interact_with(request_sender_id) then
    raise exception 'Friend request is not allowed';
  end if;

  perform 1
  from public.friend_requests request
  where request.sender_id = request_sender_id
    and request.receiver_id = current_user_id
    and request.status = 'pending'
  for update;

  if not found then
    raise exception 'Pending friend request not found';
  end if;

  insert into public.friends (user_id, friend_id)
  values
    (current_user_id, request_sender_id),
    (request_sender_id, current_user_id)
  on conflict do nothing;

  update public.friend_requests request
  set status = 'accepted'
  where request.sender_id = request_sender_id
    and request.receiver_id = current_user_id
    and request.status = 'pending';
end;
$$;

revoke all on function public.accept_friend_request(uuid) from public, anon;
grant execute on function public.accept_friend_request(uuid) to authenticated;

create or replace function public.remove_friend(target_friend_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if target_friend_id is null or target_friend_id = current_user_id then
    raise exception 'Invalid friend';
  end if;

  delete from public.friends friend_link
  where (
    friend_link.user_id = current_user_id
    and friend_link.friend_id = target_friend_id
  ) or (
    friend_link.user_id = target_friend_id
    and friend_link.friend_id = current_user_id
  );

  delete from public.friend_requests request
  where (
    request.sender_id = current_user_id
    and request.receiver_id = target_friend_id
  ) or (
    request.sender_id = target_friend_id
    and request.receiver_id = current_user_id
  );
end;
$$;

revoke all on function public.remove_friend(uuid) from public, anon;
grant execute on function public.remove_friend(uuid) to authenticated;

revoke all on function public._delete_user_everywhere(uuid)
from public, anon, authenticated;
grant execute on function public._delete_user_everywhere(uuid) to service_role;

revoke all on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

revoke all on function public.admin_delete_user(uuid)
from public, anon, authenticated;
grant execute on function public.admin_delete_user(uuid) to service_role;

grant select, insert, update on table public.profiles to authenticated;

create policy profiles_select_own
on public.profiles
for select to authenticated
using (id = (select auth.uid()));

create policy profiles_insert_own
on public.profiles
for insert to authenticated
with check (id = (select auth.uid()));

create policy profiles_update_own
on public.profiles
for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

grant select, delete on table public.friends to authenticated;

create policy friends_select_participant
on public.friends
for select to authenticated
using (
  user_id = (select auth.uid())
  or friend_id = (select auth.uid())
);

create policy friends_delete_participant
on public.friends
for delete to authenticated
using (
  user_id = (select auth.uid())
  or friend_id = (select auth.uid())
);

grant select, insert, delete on table public.friend_requests to authenticated;

create policy friend_requests_select_participant
on public.friend_requests
for select to authenticated
using (
  sender_id = (select auth.uid())
  or receiver_id = (select auth.uid())
);

create policy friend_requests_insert_sender
on public.friend_requests
for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and receiver_id <> (select auth.uid())
  and status = 'pending'
  and (select public.can_interact_with(receiver_id))
);

create policy friend_requests_delete_participant
on public.friend_requests
for delete to authenticated
using (
  sender_id = (select auth.uid())
  or receiver_id = (select auth.uid())
);

grant select, insert on table public.messages to authenticated;

create policy messages_select_visible
on public.messages
for select to authenticated
using (
  coalesce(is_encrypted, false) = false
  or user_id = (select auth.uid())
  or receiver_id = (select auth.uid())
);

create policy messages_insert_sender
on public.messages
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and (
    (
      coalesce(is_encrypted, false) = false
      and receiver_id is null
      and line_id is not null
    )
    or (
      is_encrypted = true
      and receiver_id is not null
      and receiver_id <> (select auth.uid())
      and (select public.is_friend_with(receiver_id))
    )
  )
);

grant select, insert, delete on table public.user_blocks to authenticated;

create policy user_blocks_select_blocker
on public.user_blocks
for select to authenticated
using (blocker_id = (select auth.uid()));

create policy user_blocks_insert_blocker
on public.user_blocks
for insert to authenticated
with check (
  blocker_id = (select auth.uid())
  and blocked_id <> (select auth.uid())
);

create policy user_blocks_delete_blocker
on public.user_blocks
for delete to authenticated
using (blocker_id = (select auth.uid()));

grant select, insert, update, delete on table public.user_locations
to authenticated;

create policy user_locations_select_own
on public.user_locations
for select to authenticated
using (user_id = (select auth.uid()));

create policy user_locations_insert_own
on public.user_locations
for insert to authenticated
with check (user_id = (select auth.uid()));

create policy user_locations_update_own
on public.user_locations
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy user_locations_delete_own
on public.user_locations
for delete to authenticated
using (user_id = (select auth.uid()));

create or replace function public.get_public_profiles(target_ids uuid[])
returns table (
  id uuid,
  username text,
  avatar_url text,
  avatar_emoji text,
  theme_color bigint,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    profile.id,
    profile.username::text,
    profile.avatar_url::text,
    profile.avatar_emoji::text,
    profile.theme_color::bigint,
    null::timestamptz as created_at
  from public.profiles profile
  where auth.uid() is not null
    and coalesce(cardinality(target_ids), 0) between 1 and 100
    and profile.id = any(target_ids);
$$;

revoke all on function public.get_public_profiles(uuid[]) from public, anon;
grant execute on function public.get_public_profiles(uuid[]) to authenticated;

create or replace function public.search_public_profiles(
  search_term text,
  result_limit integer default 10
)
returns table (
  id uuid,
  username text,
  avatar_url text,
  avatar_emoji text,
  theme_color bigint,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    profile.id,
    profile.username::text,
    profile.avatar_url::text,
    profile.avatar_emoji::text,
    profile.theme_color::bigint,
    null::timestamptz as created_at
  from public.profiles profile
  where auth.uid() is not null
    and length(trim(search_term)) >= 3
    and profile.username ilike ('%' || trim(search_term) || '%')
    and not exists (
      select 1
      from public.user_blocks block
      where (
        block.blocker_id = auth.uid()
        and block.blocked_id = profile.id
      ) or (
        block.blocker_id = profile.id
        and block.blocked_id = auth.uid()
      )
    )
  order by
    lower(profile.username) = lower(trim(search_term)) desc,
    lower(profile.username),
    profile.id
  limit least(greatest(coalesce(result_limit, 10), 1), 20);
$$;

revoke all on function public.search_public_profiles(text, integer)
from public, anon;
grant execute on function public.search_public_profiles(text, integer)
to authenticated;
