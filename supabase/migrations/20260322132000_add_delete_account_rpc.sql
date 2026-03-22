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
    execute $sql$
      delete from public.messages
      where user_id = $1 or receiver_id = $1
    $sql$
    using target_user_id;
  end if;

  if to_regclass('public.friend_requests') is not null then
    execute $sql$
      delete from public.friend_requests
      where sender_id = $1 or receiver_id = $1
    $sql$
    using target_user_id;
  end if;

  if to_regclass('public.friends') is not null then
    execute $sql$
      delete from public.friends
      where user_id = $1 or friend_id = $1
    $sql$
    using target_user_id;
  end if;

  if to_regclass('public.user_blocks') is not null then
    execute $sql$
      delete from public.user_blocks
      where blocker_id = $1 or blocked_id = $1
    $sql$
    using target_user_id;
  end if;

  if to_regclass('public.user_locations') is not null then
    execute $sql$
      delete from public.user_locations
      where user_id = $1
    $sql$
    using target_user_id;
  end if;

  if to_regclass('storage.objects') is not null then
    execute $sql$
      delete from storage.objects
      where bucket_id = 'tickets'
        and name like ($1::text || '/%')
    $sql$
    using target_user_id;
  end if;

  if to_regclass('public.profiles') is not null then
    execute $sql$
      delete from public.profiles
      where id = $1
    $sql$
    using target_user_id;
  end if;

  delete from auth.users where id = target_user_id;
end;
$$;

revoke all on function public.delete_account() from public;
grant execute on function public.delete_account() to authenticated;
