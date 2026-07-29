-- Resolve avoidable Security Advisor warnings without weakening the RLS model.

drop function if exists public.disable_ghost_mode(uuid);

alter function public.sanitize_profile_favorites(jsonb)
  set search_path = '';
alter function public.sanitize_profile_favorites_before_write()
  set search_path = '';

-- Policy helpers need to bypass RLS so they can detect blocks created by the
-- other user, but they do not need to be exposed as public Data API RPCs.
create schema if not exists rls_private;
revoke all on schema rls_private from public, anon, authenticated;
grant usage on schema rls_private to authenticated;

create or replace function rls_private.can_interact_with(
  other_user_id uuid
)
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

revoke all on function rls_private.can_interact_with(uuid)
from public, anon;
grant execute on function rls_private.can_interact_with(uuid)
to authenticated;

create or replace function rls_private.is_friend_with(
  other_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select rls_private.can_interact_with(other_user_id)
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

revoke all on function rls_private.is_friend_with(uuid)
from public, anon;
grant execute on function rls_private.is_friend_with(uuid)
to authenticated;

drop policy friend_requests_insert_sender on public.friend_requests;
create policy friend_requests_insert_sender
on public.friend_requests
for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and receiver_id <> (select auth.uid())
  and status = 'pending'
  and (select rls_private.can_interact_with(receiver_id))
);

drop policy messages_insert_sender on public.messages;
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
      and (select rls_private.is_friend_with(receiver_id))
    )
  )
);

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
  if not rls_private.can_interact_with(request_sender_id) then
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

drop function public.is_friend_with(uuid);
drop function public.can_interact_with(uuid);

-- These operations are now fully supported by table grants plus owner/participant
-- RLS policies, so they no longer need to run as the function owner.
create or replace function public.remove_friend(target_friend_id uuid)
returns void
language plpgsql
security invoker
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

create or replace function public.set_my_privacy_level(
  requested_level integer
)
returns smallint
language plpgsql
security invoker
set search_path = ''
as $$
declare
  normalized smallint;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  normalized := greatest(0, least(8, requested_level))::smallint;

  update public.profiles
  set privacy_level = normalized, ghost_mode = normalized = 0
  where id = auth.uid();

  if normalized = 0 then
    delete from public.journey_presence
    where owner_id = auth.uid();

    delete from public.user_locations
    where user_id = auth.uid();
  end if;

  return normalized;
end;
$$;

revoke all on function public.set_my_privacy_level(integer)
from public, anon;
grant execute on function public.set_my_privacy_level(integer)
to authenticated;
