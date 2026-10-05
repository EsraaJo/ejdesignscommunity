-- Read-only, privacy-aware network list RPCs used by the community site.
-- Counts stay visible to signed-in members; people lists require the owner's
-- show_lists setting unless the caller is viewing their own lists.

create or replace function public.get_member_social_counts(p_user_id uuid)
returns table(connection_count bigint, follower_count bigint, following_count bigint)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    (select count(*)::bigint
       from public.connections c
      where c.status = 'accepted'
        and (c.requester_id = p_user_id or c.recipient_id = p_user_id)),
    (select count(*)::bigint
       from public.member_follows f
      where f.following_id = p_user_id),
    (select count(*)::bigint
       from public.member_follows f
      where f.follower_id = p_user_id);
$$;

create or replace function public.get_member_social_connections(p_user_id uuid)
returns table(member_id uuid, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if auth.uid() <> p_user_id and not exists (
    select 1
      from public.member_social_settings settings
     where settings.user_id = p_user_id
       and settings.show_lists = true
  ) then
    raise exception 'This member keeps their lists private';
  end if;

  return query
  select case when c.requester_id = p_user_id then c.recipient_id else c.requester_id end,
         c.created_at
    from public.connections c
   where c.status = 'accepted'
     and (c.requester_id = p_user_id or c.recipient_id = p_user_id)
   order by c.created_at desc;
end;
$$;

revoke all on function public.get_member_social_counts(uuid) from public, anon;
grant execute on function public.get_member_social_counts(uuid) to authenticated;
revoke all on function public.get_member_social_connections(uuid) from public, anon;
grant execute on function public.get_member_social_connections(uuid) to authenticated;
revoke all on function public.get_member_social_list(uuid, text) from public, anon;
grant execute on function public.get_member_social_list(uuid, text) to authenticated;
