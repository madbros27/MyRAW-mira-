-- MIRA — single-system-admin model
-- Adds the explicit global administrator flag and enforces it at the auth boundary.

begin;

alter table public.profiles
  add column if not exists is_system_admin boolean not null default false;

create unique index if not exists profiles_single_system_admin_idx
  on public.profiles (is_system_admin)
  where is_system_admin = true;

create or replace function public.is_system_admin(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = coalesce(p_user_id, auth.uid())
      and p.is_system_admin = true
  );
$$;

create or replace function public.create_workspace(
  p_name text,
  p_slug text default null
)
returns public.workspaces
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_workspace public.workspaces;
  v_slug text;
  v_suffix integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not public.is_system_admin(auth.uid()) then
    raise exception 'Only the system administrator can create a workspace.';
  end if;

  v_slug := coalesce(nullif(trim(p_slug), ''), public.slugify(p_name));

  while exists (select 1 from public.workspaces w where w.slug = v_slug) loop
    v_suffix := v_suffix + 1;
    v_slug := public.slugify(p_name) || '-' || v_suffix;
  end loop;

  insert into public.workspaces (name, slug, owner_id)
  values (p_name, v_slug, auth.uid())
  returning * into v_workspace;

  insert into public.workspace_members (workspace_id, user_id, role)
  values (v_workspace.id, auth.uid(), 'admin');

  return v_workspace;
end;
$$;

create or replace function public.validate_project_join_request_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'cancelled' then
    if old.status <> 'pending' then
      raise exception 'Only pending requests may be cancelled.';
    end if;

    if new.user_id <> auth.uid() then
      raise exception 'Only the requester may cancel their own request.';
    end if;

    if new.reviewed_by is not null or new.reviewed_at is not null then
      raise exception 'Cancelled requests must not have reviewer metadata.';
    end if;

    return new;
  end if;

  if new.status in ('approved', 'rejected') then
    if old.status <> 'pending' then
      raise exception 'Only pending requests may be approved or rejected.';
    end if;

    if new.user_id = auth.uid() then
      raise exception 'Requesters may not approve or reject their own request.';
    end if;

    if not public.is_system_admin(auth.uid()) then
      raise exception 'Only the system administrator can approve or reject join requests.';
    end if;

    if new.reviewed_by is null then
      new.reviewed_by := auth.uid();
    end if;

    if new.reviewed_at is null then
      new.reviewed_at := now();
    end if;

    if new.reviewed_by = new.user_id then
      raise exception 'The reviewer cannot be the requester.';
    end if;
  end if;

  return new;
end;
$$;

-- Recreate the project join request policies so only the system admin can review requests.
drop policy if exists project_join_requests_select on public.project_join_requests;
create policy project_join_requests_select on public.project_join_requests
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_system_admin(auth.uid())
  );

drop policy if exists project_join_requests_update on public.project_join_requests;
create policy project_join_requests_update on public.project_join_requests
  for update to authenticated
  using (
    user_id = auth.uid()
    or public.is_system_admin(auth.uid())
  )
  with check (
    (
      user_id = auth.uid()
      and status = 'cancelled'
      and (select status from public.project_join_requests where id = project_join_requests.id) = 'pending'
    )
    or (
      status in ('approved', 'rejected')
      and reviewed_by is not null
      and reviewed_at is not null
      and reviewed_by <> user_id
      and public.is_system_admin(auth.uid())
      and (select status from public.project_join_requests where id = project_join_requests.id) = 'pending'
    )
  );

commit;
