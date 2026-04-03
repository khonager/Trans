create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = public, auth, storage
as $$
declare
  target_user_id uuid := auth.uid();
begin
  if target_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if to_regclass('public.messages') is not null then
    execute 'delete from public.messages where user_id = $1'
      using target_user_id;
    execute 'delete from public.messages where receiver_id = $1'
      using target_user_id;
  end if;

  if to_regclass('public.friend_requests') is not null then
    execute 'delete from public.friend_requests where sender_id = $1'
      using target_user_id;
    execute 'delete from public.friend_requests where receiver_id = $1'
      using target_user_id;
  end if;

  if to_regclass('public.friends') is not null then
    execute 'delete from public.friends where user_id = $1'
      using target_user_id;
    execute 'delete from public.friends where friend_id = $1'
      using target_user_id;

    if exists (
      select 1
      from public.friends
      where user_id = target_user_id or friend_id = target_user_id
    ) then
      raise exception 'Failed to remove all friend links for user %',
        target_user_id;
    end if;
  end if;

  if to_regclass('public.user_blocks') is not null then
    execute 'delete from public.user_blocks where blocker_id = $1'
      using target_user_id;
    execute 'delete from public.user_blocks where blocked_id = $1'
      using target_user_id;
  end if;

  if to_regclass('public.user_locations') is not null then
    execute 'delete from public.user_locations where user_id = $1'
      using target_user_id;
  end if;

  if to_regclass('public.profiles') is not null then
    execute 'delete from public.profiles where id = $1'
      using target_user_id;
  end if;

  delete from auth.users where id = target_user_id;
end;
$$;

revoke all on function public.delete_account() from public;
grant execute on function public.delete_account() to authenticated;
