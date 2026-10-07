-- Privacy-conscious, first-party visitor totals for EJ Designs Community.
-- The browser stores a random UUID in localStorage; this table contains no IP,
-- name, email, URL, or other browsing history. Counts are browser estimates,
-- not a guarantee that one row equals one human being.

create table if not exists public.site_visitor_analytics (
    visitor_id uuid primary key,
    first_seen_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now(),
    has_registered boolean not null default false
);

alter table public.site_visitor_analytics enable row level security;
revoke all on table public.site_visitor_analytics from anon, authenticated;

create or replace function public.record_site_visit(p_visitor_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if p_visitor_id is null then
        raise exception 'A visitor ID is required.';
    end if;

    insert into public.site_visitor_analytics (visitor_id, has_registered)
    values (p_visitor_id, auth.uid() is not null)
    on conflict (visitor_id) do update
    set last_seen_at = now(),
        has_registered = public.site_visitor_analytics.has_registered or auth.uid() is not null;
end;
$$;

revoke all on function public.record_site_visit(uuid) from public;
grant execute on function public.record_site_visit(uuid) to anon, authenticated;

create or replace function public.get_site_visitor_stats()
returns table (
    total_unique_visitors bigint,
    guests_without_registration bigint,
    registered_visitors bigint
)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is distinct from '4f757ff7-d08f-4fa8-826c-0a8f7c9f1917'::uuid then
        raise exception 'Only the site owner can view visitor statistics.'
            using errcode = '42501';
    end if;

    return query
    select count(*)::bigint,
           count(*) filter (where not has_registered)::bigint,
           count(*) filter (where has_registered)::bigint
    from public.site_visitor_analytics;
end;
$$;

revoke all on function public.get_site_visitor_stats() from public;
grant execute on function public.get_site_visitor_stats() to authenticated;
