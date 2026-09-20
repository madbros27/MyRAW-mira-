-- MIRA - final team/project integrity and owner authorization hardening
-- Preserves projects.team_id for compatibility while making teams.project_id
-- and issues.team_id authoritative for new team-aware behavior.

begin;

-- ---------------------------------------------------------------------------
-- 1. Every team must belong to the workspace's project
-- ---------------------------------------------------------------------------

-- The previous migration backfills legacy project.team_id relationships. Do
-- not silently assign or delete any remaining workspace-only team records.
do $$
begin
  if exists (
    select 1
    from public.teams
    where project_id is null
  ) then
    raise exception 'Cannot enforce teams.project_id NOT NULL: workspace-only teams remain.';
  end if;
end;
$$;

alter table public.teams
  alter column project_id set not null;

create or replace function public.validate_team_member_project()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1
    from public.teams t
    join public.projects p on p.id = t.project_id
    where t.id = new.team_id
      and public.is_project_member(p.id, new.user_id)
  ) then
    raise exception 'Team member must already belong to the team project.';
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Multi-team issue assignment
-- ---------------------------------------------------------------------------

alter table public.issues
  add column if not exists team_id uuid references public.teams(id) on delete set null;

create index if not exists issues_team_idx on public.issues(team_id);

create or replace function public.validate_issue_team_assignment()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_team_project_id uuid;
begin
  if new.team_id is null then
    return new;
  end if;

  select t.project_id
    into v_team_project_id
  from public.teams t
  where t.id = new.team_id;

  if v_team_project_id is null or v_team_project_id <> new.project_id then
    raise exception 'Issue team must belong to the issue project.';
  end if;

  if new.assignee_id is not null and not exists (
    select 1
    from public.team_members tm
    where tm.team_id = new.team_id
      and tm.user_id = new.assignee_id
  ) then
    raise exception 'Issue assignee must be a member of the issue team.';
  end if;

  return new;
end;
$$;

drop trigger if exists issues_team_assignment_validate on public.issues;
create trigger issues_team_assignment_validate
before insert or update of project_id, team_id, assignee_id on public.issues
for each row execute function public.validate_issue_team_assignment();

-- Keep the existing legacy projects.team_id validation for old records, but
-- make the new issue-level team relationship authoritative whenever present.
create or replace function public.validate_issue_assignee()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_workspace_id uuid;
  v_legacy_team_id uuid;
begin
  if new.assignee_id is null then
    return new;
  end if;

  select p.workspace_id, p.team_id
    into v_workspace_id, v_legacy_team_id
  from public.projects p
  where p.id = new.project_id;

  if v_workspace_id is null then
    raise exception 'Assigned issue must belong to an existing project.';
  end if;

  if not exists (
    select 1
    from public.project_members pm
    where pm.project_id = new.project_id
      and pm.user_id = new.assignee_id
  ) then
    raise exception 'Issue assignee must be a member of the project.';
  end if;

  if new.team_id is not null then
    if not exists (
      select 1
      from public.team_members tm
      where tm.team_id = new.team_id
        and tm.user_id = new.assignee_id
    ) then
      raise exception 'Issue assignee must be a member of the issue team.';
    end if;
  elsif v_legacy_team_id is not null and not exists (
    select 1
    from public.team_members tm
    where tm.team_id = v_legacy_team_id
      and tm.user_id = new.assignee_id
  ) then
    raise exception 'Issue assignee must be a member of the project team.';
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Project-owner join-request approval
-- ---------------------------------------------------------------------------

create or replace function public.can_review_project_join_request(
  p_project_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_system_admin(p_user_id)
    or public.is_project_owner(p_project_id, p_user_id)
    or exists (
      select 1
      from public.projects p
      where p.id = p_project_id
        and (
          public.has_permission(p.workspace_id, 'approve_join_requests', p_user_id)
          or public.has_permission(p.workspace_id, 'manage_users', p_user_id)
        )
    );
$$;

create or replace function public.validate_project_join_request_transition()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
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

    if not public.can_review_project_join_request(new.project_id, auth.uid()) then
      raise exception 'Reviewer is not authorized to review this project request.';
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

drop policy if exists project_join_requests_select on public.project_join_requests;
create policy project_join_requests_select on public.project_join_requests
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.can_review_project_join_request(project_id, auth.uid())
  );

drop policy if exists project_join_requests_update on public.project_join_requests;
create policy project_join_requests_update on public.project_join_requests
  for update to authenticated
  using (
    user_id = auth.uid()
    or public.can_review_project_join_request(project_id, auth.uid())
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
      and public.can_review_project_join_request(project_id, auth.uid())
      and (select status from public.project_join_requests where id = project_join_requests.id) = 'pending'
    )
  );

-- ---------------------------------------------------------------------------
-- 4. Prevent profile self-service from escalating system-admin authority
-- ---------------------------------------------------------------------------

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and (
      is_system_admin = false
      or public.is_system_admin(auth.uid())
    )
  );

commit;
