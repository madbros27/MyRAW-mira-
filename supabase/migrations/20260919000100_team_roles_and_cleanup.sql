-- MIRA — team, role and cleanup migration
-- Removes invite/demo behavior, adds team and custom-role model, and adds project team linkage.

begin;

-- ---------------------------------------------------------------------------
-- 1. Remove obsolete invite/demo behavior safely
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
begin
  v_name := coalesce(
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'name',
    split_part(new.email, '@', 1)
  );

  insert into public.profiles (id, email, full_name, avatar_url)
  values (
    new.id,
    new.email,
    v_name,
    coalesce(
      new.raw_user_meta_data ->> 'avatar_url',
      new.raw_user_meta_data ->> 'picture'
    )
  )
  on conflict (id) do update
    set email      = excluded.email,
        full_name  = coalesce(public.profiles.full_name, excluded.full_name),
        avatar_url = coalesce(public.profiles.avatar_url, excluded.avatar_url);

  return new;
end;
$$;

drop function if exists public.claim_pending_invites(uuid, text);
drop function if exists public.accept_invite(text);
drop function if exists public.seed_demo_for_email(text);
drop function if exists public.bootstrap_demo_workspace(uuid, text);

drop table if exists public.workspace_invites cascade;

-- ---------------------------------------------------------------------------
-- 2. Workspace-level authorization helper
-- ---------------------------------------------------------------------------

create or replace function public.is_workspace_owner(p_workspace_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.workspaces w
    where w.id = p_workspace_id
      and w.owner_id = p_user_id
  );
$$;

create or replace function public.is_workspace_admin(p_workspace_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.workspace_members wm
    where wm.workspace_id = p_workspace_id
      and wm.user_id = p_user_id
      and wm.role = 'admin'
  );
$$;

create or replace function public.is_workspace_admin_or_owner(p_workspace_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_workspace_owner(p_workspace_id, p_user_id)
    or public.is_workspace_admin(p_workspace_id, p_user_id);
$$;

create or replace function public.is_workspace_member(p_workspace uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.workspace_members m
    where m.workspace_id = p_workspace
      and m.user_id = auth.uid()
  )
  or exists (
    select 1
    from public.workspaces w
    where w.id = p_workspace
      and w.owner_id = auth.uid()
  );
$$;

create or replace function public.has_workspace_role(
  p_workspace uuid,
  p_roles public.workspace_role[]
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.workspace_members m
    where m.workspace_id = p_workspace
      and m.user_id = auth.uid()
      and m.role = any (p_roles)
  )
  or (
    p_roles && array['admin']::public.workspace_role[]
    and exists (
      select 1
      from public.workspaces w
      where w.id = p_workspace
        and w.owner_id = auth.uid()
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- 3. Teams and team membership
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.team_member_role as enum ('lead', 'member');
exception when duplicate_object then null; end $$;

create table if not exists public.teams (
  id          uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete cascade,
  name        text not null check (char_length(trim(name)) between 1 and 80),
  description text,
  created_by  uuid not null references public.profiles (id) on delete restrict,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.team_members (
  id         uuid primary key default gen_random_uuid(),
  team_id    uuid not null references public.teams (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  role       public.team_member_role not null default 'member',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (team_id, user_id)
);

create index if not exists teams_workspace_idx on public.teams (workspace_id);
create index if not exists team_members_team_idx on public.team_members (team_id);
create index if not exists team_members_user_idx on public.team_members (user_id);

create or replace function public.ensure_single_team_lead()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' or tg_op = 'UPDATE' then
    if new.role = 'lead' then
      if exists (
        select 1
        from public.team_members tm
        where tm.team_id = new.team_id
          and tm.user_id <> new.user_id
          and tm.role = 'lead'
      ) then
        raise exception 'A team can only have one lead.';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists team_members_single_lead on public.team_members;
create unique index if not exists team_members_single_lead_unique
  on public.team_members (team_id)
  where role = 'lead';
create trigger team_members_single_lead
before insert or update of role, team_id, user_id on public.team_members
for each row execute function public.ensure_single_team_lead();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists teams_set_updated_at on public.teams;
create trigger teams_set_updated_at
before update on public.teams
for each row execute function public.set_updated_at();

drop trigger if exists team_members_set_updated_at on public.team_members;
create trigger team_members_set_updated_at
before update on public.team_members
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 5. Custom roles and permissions catalog
-- ---------------------------------------------------------------------------

create table if not exists public.roles (
  id          uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete cascade,
  name        text not null check (char_length(trim(name)) between 1 and 80),
  description text,
  is_system   boolean not null default false,
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (workspace_id, name)
);

drop trigger if exists roles_set_updated_at on public.roles;
create trigger roles_set_updated_at
before update on public.roles
for each row execute function public.set_updated_at();

create table if not exists public.permissions (
  id          uuid primary key default gen_random_uuid(),
  key         text not null unique,
  name        text not null,
  description text,
  created_at  timestamptz not null default now()
);

create table if not exists public.role_permissions (
  role_id      uuid not null references public.roles (id) on delete cascade,
  permission_id uuid not null references public.permissions (id) on delete cascade,
  primary key (role_id, permission_id)
);

create table if not exists public.workspace_member_roles (
  id          uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  role_id     uuid not null references public.roles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (workspace_id, user_id, role_id)
);

create or replace function public.workspace_of_team(p_team uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select t.workspace_id
  from public.teams t
  where t.id = p_team;
$$;

create or replace function public.is_team_member(p_team_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.team_members tm
    where tm.team_id = p_team_id
      and tm.user_id = p_user_id
  );
$$;

create or replace function public.is_team_lead(p_team_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.team_members tm
    where tm.team_id = p_team_id
      and tm.user_id = p_user_id
      and tm.role = 'lead'
  );
$$;

create or replace function public.has_permission(p_workspace_id uuid, p_permission text, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    exists (
      select 1
      from public.workspaces w
      where w.id = p_workspace_id
        and w.owner_id = p_user_id
    )
    or exists (
      select 1
      from public.workspace_members wm
      where wm.workspace_id = p_workspace_id
        and wm.user_id = p_user_id
        and wm.role = 'admin'
    )
    or exists (
      select 1
      from public.workspace_member_roles wmr
      join public.role_permissions rp on rp.role_id = wmr.role_id
      join public.permissions p on p.id = rp.permission_id
      where wmr.workspace_id = p_workspace_id
        and wmr.user_id = p_user_id
        and p.key = p_permission
    );
$$;

create or replace function public.can_manage_team(p_team_id uuid, p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    public.is_workspace_admin_or_owner(public.workspace_of_team(p_team_id), p_user_id)
    or public.has_permission(public.workspace_of_team(p_team_id), 'manage_team', p_user_id)
    or public.has_permission(public.workspace_of_team(p_team_id), 'manage_team_members', p_user_id);
$$;

create index if not exists roles_workspace_idx on public.roles (workspace_id);
create index if not exists role_permissions_permission_idx on public.role_permissions (permission_id);
create index if not exists workspace_member_roles_user_idx on public.workspace_member_roles (user_id, workspace_id);
create index if not exists workspace_member_roles_role_idx on public.workspace_member_roles (role_id);

insert into public.permissions (key, name, description)
values
  ('view_workspace', 'View workspace', 'View workspace information.'),
  ('manage_workspace', 'Manage workspace', 'Manage workspace settings and membership.'),
  ('view_project', 'View project', 'View project details.'),
  ('create_project', 'Create project', 'Create new projects.'),
  ('edit_project', 'Edit project', 'Edit project details.'),
  ('delete_project', 'Delete project', 'Delete projects.'),
  ('view_issue', 'View issue', 'View issues.'),
  ('create_issue', 'Create issue', 'Create issues.'),
  ('edit_issue', 'Edit issue', 'Edit issues.'),
  ('delete_issue', 'Delete issue', 'Delete issues.'),
  ('assign_issue', 'Assign issue', 'Assign and update issue assignees.'),
  ('comment_issue', 'Comment issue', 'Create and edit comments.'),
  ('manage_labels', 'Manage labels', 'Manage issue labels.'),
  ('manage_sprints', 'Manage sprints', 'Manage sprint lifecycle.'),
  ('manage_workflow', 'Manage workflow', 'Manage project workflow and statuses.'),
  ('manage_team', 'Manage team', 'Manage team metadata.'),
  ('manage_team_members', 'Manage team members', 'Add, remove, and change team members.'),
  ('manage_users', 'Manage users', 'Manage workspace users.'),
  ('manage_roles', 'Manage roles', 'Create and manage custom roles.'),
  ('manage_permissions', 'Manage permissions', 'Manage role-to-permission mappings.'),
  ('manage_settings', 'Manage settings', 'Manage workspace settings.'),
  ('approve_join_requests', 'Approve join requests', 'Review and approve or reject project join requests.')
on conflict (key) do nothing;

create or replace function public.validate_workspace_member_role()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1
    from public.roles r
    where r.id = new.role_id
      and r.workspace_id = new.workspace_id
  ) then
    raise exception 'Role must belong to the same workspace as the assignment.';
  end if;

  if not exists (
    select 1
    from public.workspace_members wm
    where wm.workspace_id = new.workspace_id
      and wm.user_id = new.user_id
  ) then
    raise exception 'User must be a member of the workspace before assigning a role.';
  end if;

  return new;
end;
$$;

drop trigger if exists workspace_member_roles_validate on public.workspace_member_roles;
create trigger workspace_member_roles_validate
before insert or update on public.workspace_member_roles
for each row execute function public.validate_workspace_member_role();

-- ---------------------------------------------------------------------------
-- 6. Project join requests
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.join_request_status as enum ('pending', 'approved', 'rejected', 'cancelled');
exception when duplicate_object then null; end $$;

create table if not exists public.project_join_requests (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  status      public.join_request_status not null default 'pending',
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles (id) on delete set null,
  note        text
);

create table if not exists public.project_members (
  id         uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  role       text not null default 'member' check (role in ('member', 'manager')),
  created_at timestamptz not null default now(),
  unique (project_id, user_id)
);

create index if not exists project_join_requests_project_idx
  on public.project_join_requests (project_id, status);
create index if not exists project_join_requests_user_idx
  on public.project_join_requests (user_id, status);
create unique index if not exists project_join_requests_pending_unique
  on public.project_join_requests (project_id, user_id)
  where status = 'pending';
create index if not exists project_members_project_idx on public.project_members (project_id);
create index if not exists project_members_user_idx on public.project_members (user_id);

-- ---------------------------------------------------------------------------
-- 7. Add project team linkage
-- ---------------------------------------------------------------------------

alter table public.projects
  add column if not exists team_id uuid references public.teams (id) on delete set null;

create index if not exists projects_team_idx on public.projects (team_id);

create or replace function public.validate_project_team_workspace()
returns trigger
language plpgsql
as $$
begin
  if new.team_id is not null and not exists (
    select 1
    from public.teams t
    where t.id = new.team_id
      and t.workspace_id = new.workspace_id
  ) then
    raise exception 'Project team_id must belong to the same workspace.';
  end if;

  return new;
end;
$$;

drop trigger if exists projects_team_workspace_validate on public.projects;
create trigger projects_team_workspace_validate
before insert or update of workspace_id, team_id on public.projects
for each row execute function public.validate_project_team_workspace();

create or replace function public.project_team_membership_allowed(p_project uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.projects p
    left join public.team_members tm on tm.team_id = p.team_id
    where p.id = p_project
      and tm.user_id = p_user
  );
$$;

-- ---------------------------------------------------------------------------
-- 8. Validation and lifecycle triggers
-- ---------------------------------------------------------------------------

create or replace function public.validate_project_join_request_insert()
returns trigger
language plpgsql
as $$
begin
  if new.user_id <> auth.uid() then
    raise exception 'A user may only create their own join request.';
  end if;

  if new.status is null then
    new.status := 'pending';
  elsif new.status <> 'pending' then
    raise exception 'Only pending join requests may be inserted.';
  end if;

  if not exists (
    select 1
    from public.projects p
    where p.id = new.project_id
      and p.is_archived = false
  ) then
    raise exception 'Project does not exist or is archived.';
  end if;

  if not exists (
    select 1
    from public.projects p
    join public.workspace_members wm on wm.workspace_id = p.workspace_id
    where p.id = new.project_id
      and wm.user_id = new.user_id
  ) then
    raise exception 'Requester must already belong to the project workspace.';
  end if;

  if exists (
    select 1
    from public.team_members tm
    join public.projects p on p.team_id = tm.team_id
    where p.id = new.project_id
      and tm.user_id = new.user_id
  ) then
    raise exception 'Requester is already a project member.';
  end if;

  if exists (
    select 1
    from public.project_join_requests pjr
    where pjr.project_id = new.project_id
      and pjr.user_id = new.user_id
      and pjr.status = 'pending'
  ) then
    raise exception 'A pending join request already exists for this project.';
  end if;

  return new;
end;
$$;

drop trigger if exists project_join_request_insert_validate on public.project_join_requests;
create trigger project_join_request_insert_validate
before insert on public.project_join_requests
for each row execute function public.validate_project_join_request_insert();

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

    if new.reviewed_by is null then
      new.reviewed_by := auth.uid();
    end if;

    if new.reviewed_at is null then
      new.reviewed_at := now();
    end if;

    if new.reviewed_by = new.user_id then
      raise exception 'The reviewer cannot be the requester.';
    end if;

    if not exists (
      select 1
      from public.projects p
      where p.id = new.project_id
        and public.has_permission(p.workspace_id, 'approve_join_requests')
    ) then
      raise exception 'Reviewer is not authorized to approve or reject this project request.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists project_join_request_transition_validate on public.project_join_requests;
create trigger project_join_request_transition_validate
before update on public.project_join_requests
for each row execute function public.validate_project_join_request_transition();

create or replace function public.apply_project_join_request_approval()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'approved' and old.status <> 'approved' then
    insert into public.project_members (project_id, user_id, role)
    select p.id, new.user_id, 'member'
    from public.projects p
    where p.id = new.project_id
    on conflict (project_id, user_id) do nothing;

    if exists (
      select 1
      from public.projects p
      where p.id = new.project_id
        and p.team_id is not null
    ) then
      insert into public.team_members (team_id, user_id, role)
      select p.team_id, new.user_id, 'member'
      from public.projects p
      where p.id = new.project_id
        and p.team_id is not null
      on conflict (team_id, user_id) do nothing;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists project_join_request_approval_apply on public.project_join_requests;
create trigger project_join_request_approval_apply
after update of status on public.project_join_requests
for each row execute function public.apply_project_join_request_approval();

create or replace function public.validate_issue_assignee()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_workspace_id uuid;
  v_team_id uuid;
begin
  if new.assignee_id is null then
    return new;
  end if;

  select p.workspace_id, p.team_id
    into v_workspace_id, v_team_id
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

  if v_team_id is not null and not exists (
    select 1
    from public.team_members tm
    where tm.team_id = v_team_id
      and tm.user_id = new.assignee_id
  ) then
    raise exception 'Issue assignee must be a member of the project team.';
  end if;

  return new;
end;
$$;

drop trigger if exists issues_assignee_validate on public.issues;
create trigger issues_assignee_validate
before insert or update of assignee_id, project_id on public.issues
for each row execute function public.validate_issue_assignee();

-- ---------------------------------------------------------------------------
-- 9. RLS: enable and secure all new tables
-- ---------------------------------------------------------------------------

alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.workspace_member_roles enable row level security;
alter table public.project_members enable row level security;
alter table public.project_join_requests enable row level security;

-- Teams policies
create policy teams_select on public.teams
  for select to authenticated
  using (public.is_workspace_member(workspace_id));

create policy teams_insert on public.teams
  for insert to authenticated
  with check (public.has_permission(workspace_id, 'manage_team'));

create policy teams_update on public.teams
  for update to authenticated
  using (public.has_permission(workspace_id, 'manage_team'))
  with check (public.has_permission(workspace_id, 'manage_team'));

create policy teams_delete on public.teams
  for delete to authenticated
  using (public.has_permission(workspace_id, 'manage_team'));

-- Team membership policies
create policy team_members_select on public.team_members
  for select to authenticated
  using (
    public.is_team_member(team_id, auth.uid())
    or public.has_permission(public.workspace_of_team(team_id), 'manage_team_members')
    or public.has_permission(public.workspace_of_team(team_id), 'manage_team')
  );

create policy team_members_insert on public.team_members
  for insert to authenticated
  with check (
    public.has_permission(public.workspace_of_team(team_id), 'manage_team_members')
    or public.has_permission(public.workspace_of_team(team_id), 'manage_team')
  );

create policy team_members_update on public.team_members
  for update to authenticated
  using (
    public.has_permission(public.workspace_of_team(team_id), 'manage_team_members')
    or public.has_permission(public.workspace_of_team(team_id), 'manage_team')
  )
  with check (
    public.has_permission(public.workspace_of_team(team_id), 'manage_team_members')
    or public.has_permission(public.workspace_of_team(team_id), 'manage_team')
  );

create policy team_members_delete on public.team_members
  for delete to authenticated
  using (
    public.has_permission(public.workspace_of_team(team_id), 'manage_team_members')
    or public.has_permission(public.workspace_of_team(team_id), 'manage_team')
  );

-- Project membership policies
create policy project_members_select on public.project_members
  for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.projects p
      where p.id = project_members.project_id
        and (
          public.has_permission(p.workspace_id, 'manage_users')
          or public.has_permission(p.workspace_id, 'manage_team')
          or public.has_permission(p.workspace_id, 'manage_team_members')
          or (p.team_id is not null and public.is_team_member(p.team_id, auth.uid()))
        )
    )
  );

create policy project_members_insert on public.project_members
  for insert to authenticated
  with check (
    user_id <> auth.uid()
    and exists (
      select 1
      from public.projects p
      where p.id = project_members.project_id
        and (
          public.has_permission(p.workspace_id, 'manage_users')
          or public.has_permission(p.workspace_id, 'manage_team')
          or public.has_permission(p.workspace_id, 'manage_team_members')
        )
    )
  );

create policy project_members_update on public.project_members
  for update to authenticated
  using (
    exists (
      select 1
      from public.projects p
      where p.id = project_members.project_id
        and (
          public.has_permission(p.workspace_id, 'manage_users')
          or public.has_permission(p.workspace_id, 'manage_team')
          or public.has_permission(p.workspace_id, 'manage_team_members')
        )
    )
  )
  with check (
    exists (
      select 1
      from public.projects p
      where p.id = project_members.project_id
        and (
          public.has_permission(p.workspace_id, 'manage_users')
          or public.has_permission(p.workspace_id, 'manage_team')
          or public.has_permission(p.workspace_id, 'manage_team_members')
        )
    )
  );

create policy project_members_delete on public.project_members
  for delete to authenticated
  using (
    exists (
      select 1
      from public.projects p
      where p.id = project_members.project_id
        and (
          public.has_permission(p.workspace_id, 'manage_users')
          or public.has_permission(p.workspace_id, 'manage_team')
          or public.has_permission(p.workspace_id, 'manage_team_members')
        )
    )
  );

-- Role / permission assignment policies
create policy workspace_member_roles_select on public.workspace_member_roles
  for select to authenticated
  using (
    public.is_workspace_member(workspace_id)
    or public.has_permission(workspace_id, 'manage_users')
  );

create policy workspace_member_roles_insert on public.workspace_member_roles
  for insert to authenticated
  with check (
    public.has_permission(workspace_id, 'manage_users')
    or public.has_permission(workspace_id, 'manage_roles')
  );

create policy workspace_member_roles_update on public.workspace_member_roles
  for update to authenticated
  using (
    public.has_permission(workspace_id, 'manage_users')
    or public.has_permission(workspace_id, 'manage_roles')
  )
  with check (
    public.has_permission(workspace_id, 'manage_users')
    or public.has_permission(workspace_id, 'manage_roles')
  );

create policy workspace_member_roles_delete on public.workspace_member_roles
  for delete to authenticated
  using (
    public.has_permission(workspace_id, 'manage_users')
    or public.has_permission(workspace_id, 'manage_roles')
  );

-- Role and permission policies
create policy roles_select on public.roles
  for select to authenticated
  using (public.is_workspace_member(workspace_id));

create policy roles_insert on public.roles
  for insert to authenticated
  with check (public.has_permission(workspace_id, 'manage_roles'));

create policy roles_update on public.roles
  for update to authenticated
  using (public.has_permission(workspace_id, 'manage_roles'))
  with check (public.has_permission(workspace_id, 'manage_roles'));

create policy roles_delete on public.roles
  for delete to authenticated
  using (public.has_permission(workspace_id, 'manage_roles'));

create policy permissions_select on public.permissions
  for select to authenticated
  using (true);

create policy permissions_insert on public.permissions
  for insert to authenticated
  with check (false);

create policy permissions_update on public.permissions
  for update to authenticated
  using (false)
  with check (false);

create policy permissions_delete on public.permissions
  for delete to authenticated
  using (false);

create policy role_permissions_select on public.role_permissions
  for select to authenticated
  using (exists (
    select 1
    from public.roles r
    where r.id = role_permissions.role_id
      and public.is_workspace_member(r.workspace_id)
  ));

create policy role_permissions_insert on public.role_permissions
  for insert to authenticated
  with check (
    exists (
      select 1
      from public.roles r
      where r.id = role_permissions.role_id
        and public.has_permission(r.workspace_id, 'manage_permissions')
    )
  );

create policy role_permissions_update on public.role_permissions
  for update to authenticated
  using (
    exists (
      select 1
      from public.roles r
      where r.id = role_permissions.role_id
        and public.has_permission(r.workspace_id, 'manage_permissions')
    )
  )
  with check (
    exists (
      select 1
      from public.roles r
      where r.id = role_permissions.role_id
        and public.has_permission(r.workspace_id, 'manage_permissions')
    )
  );

create policy role_permissions_delete on public.role_permissions
  for delete to authenticated
  using (
    exists (
      select 1
      from public.roles r
      where r.id = role_permissions.role_id
        and public.has_permission(r.workspace_id, 'manage_permissions')
    )
  );

-- Project join requests policies
create policy project_join_requests_select on public.project_join_requests
  for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.projects p
      where p.id = project_join_requests.project_id
        and public.has_permission(p.workspace_id, 'approve_join_requests')
    )
    or exists (
      select 1
      from public.projects p
      where p.id = project_join_requests.project_id
        and public.has_permission(p.workspace_id, 'manage_users')
    )
  );

create policy project_join_requests_insert on public.project_join_requests
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and status = 'pending'
    and exists (
      select 1
      from public.projects p
      where p.id = project_join_requests.project_id
        and p.is_archived = false
    )
    and exists (
      select 1
      from public.projects p
      join public.workspace_members wm on wm.workspace_id = p.workspace_id
      where p.id = project_join_requests.project_id
        and wm.user_id = auth.uid()
    )
    and not exists (
      select 1
      from public.team_members tm
      join public.projects p on p.team_id = tm.team_id
      where p.id = project_join_requests.project_id
        and tm.user_id = auth.uid()
    )
    and not exists (
      select 1
      from public.project_join_requests pjr
      where pjr.project_id = project_join_requests.project_id
        and pjr.user_id = auth.uid()
        and pjr.status = 'pending'
    )
  );

create policy project_join_requests_update on public.project_join_requests
  for update to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.projects p
      where p.id = project_join_requests.project_id
        and public.has_permission(p.workspace_id, 'approve_join_requests')
    )
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
      and exists (
        select 1
        from public.projects p
        where p.id = project_join_requests.project_id
          and public.has_permission(p.workspace_id, 'approve_join_requests')
      )
      and (select status from public.project_join_requests where id = project_join_requests.id) = 'pending'
    )
  );

create policy project_join_requests_delete on public.project_join_requests
  for delete to authenticated
  using (
    exists (
      select 1
      from public.projects p
      where p.id = project_join_requests.project_id
        and public.has_permission(p.workspace_id, 'manage_users')
    )
  );

commit;
