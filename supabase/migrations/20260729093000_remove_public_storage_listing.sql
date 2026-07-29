-- Public buckets can serve a known object URL without a broad SELECT policy.
-- Removing these policies prevents clients from enumerating every stored
-- ticket or avatar path while preserving existing public object URLs.

drop policy if exists "Public Access" on storage.objects;
drop policy if exists "Avatar images are publicly accessible."
on storage.objects;

-- This function is an auth.users trigger, not a client-callable RPC.
alter function public.handle_new_user() set search_path = '';
revoke all on function public.handle_new_user()
from public, anon, authenticated;

-- This legacy helper is unused by the app and must not be a public RPC that
-- accepts an arbitrary user's UUID.
revoke all on function public.disable_ghost_mode(uuid)
from public, anon, authenticated;
