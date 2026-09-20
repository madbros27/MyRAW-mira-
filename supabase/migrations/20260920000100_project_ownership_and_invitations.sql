-- MIRA - project ownership, single-project workspaces and project invitations
-- This migration extends the existing authorization model without recreating
-- the removed workspace-wide invitation system.

begin;

-- Only the designated account may ever carry the global flag. The initial
-- assignment can be performed by the migration runner with auth.uid() null.
create or replace function public.protect_system_admin_flag()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if lower(new.email) = 'madbrostech27@gmail.com' then
    new.is_system_admin := true;
  end if;

  if new.is_system_admin and lower(new.email) <> 'madbrostech27@gmail.com' then
    raise exception 'Only madbrostech27@gmail.com may be the system administrator.';
  end if;

    if tg_op = 'UPDATE'
      and new.is_system_admin is distinct from old.is_system_admin
     and auth.uid() is not null
     and not public.is_system_admin(auth.uid()) then
    raise exception 'Only the system administrator can change the system-admin flag.';
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_system_admin_protect on public.profiles;
create trigger profiles_system_admin_protect
before insert or update of email, is_system_admin on public.profiles
for each row execute function public.protect_system_admin_flag();

update public.profiles
set is_system_admin = true
where lower(email) = 'madbrostech27@gmail.com';

-- ---------------------------------------------------------------------------
-- 1. Project ownership and the one-project-per-workspace invariant
-- ---------------------------------------------------------------------------

alter table public.projects
  add column if not exists owner_id uuid;

update public.projects p
set owner_id = coalesce(p.owner_id, p.lead_id, w.owner_id)
from public.workspaces w
where w.id = p.workspace_id
  and p.owner_id is null;

alter table public.projects
  alter column owner_id set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'projects_owner_id_fkey'
      and conrelid = 'public.projects'::regclass
  ) then
    alter table public.projects
      add constraint projects_owner_id_fkey
      foreign key (owner_id) references public.profiles(id) on delete restrict;
  end if;
end;
$$;

create unique index if not exists projects_one_per_workspace_idx
  on public.projects (workspace_id);

-- Teams may be associated with a project while retaining workspace_id for
-- compatibility with the existing queries and membership model.
alter table public.teams
  add column if not exists project_id uuid references public.projects(id) on delete cascade;

update public.teams t
set project_id = p.id
from public.projects p
where p.team_id = t.id
  and t.project_id is null;

create index if not exists teams_project_idx on public.teams (project_id);

create or replace function public.validate_team_project_workspace()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.project_id is not null and not exists (
    select 1
    from public.projects p
    where p.id = new.project_id
      and p.workspace_id = new.workspace_id
  ) then
    raise exception 'Team project must belong to the same workspace.';
  end if;
  return new;
end;
$$;

drop trigger if exists teams_project_workspace_validate on public.teams;
create trigger teams_project_workspace_validate
before insert or update of workspace_id, project_id on public.teams
for each row execute function public.validate_team_project_workspace();

create or replace function public.validate_team_member_project()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if exists (
    select 1
    from public.teams t
    where t.id = new.team_id
      and t.project_id is not null
      and not public.is_project_member(t.project_id, new.user_id)
  ) then
    raise exception 'Team member must already belong to the team project.';
  end if;
  return new;
end;
$$;

drop trigger if exists team_members_project_validate on public.team_members;
create trigger team_members_project_validate
before insert or update of team_id, user_id on public.team_members
for each row execute function public.validate_team_member_project();

-- ---------------------------------------------------------------------------
-- 2. Authorization helpers
-- ---------------------------------------------------------------------------

create or replace function public.is_project_owner(
  p_project_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.projects p
    where p.id = p_project_id
      and (
        p.owner_id = p_user_id
        or public.is_system_admin(p_user_id)
      )
  );
$$;

create or replace function public.is_project_member(
  p_project_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_project_owner(p_project_id, p_user_id)
    or exists (
      select 1
      from public.project_members pm
      where pm.project_id = p_project_id
        and pm.user_id = p_user_id
    );
$$;

create or replace function public.project_of_team(p_team_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select t.project_id
  from public.teams t
  where t.id = p_team_id;
$$;

create or replace function public.is_workspace_project_owner(
  p_workspace_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.projects p
    where p.workspace_id = p_workspace_id
      and p.owner_id = p_user_id
  );
$$;

create or replace function public.can_manage_project(
  p_project_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_project_owner(p_project_id, p_user_id)
    or public.is_system_admin(p_user_id)
    or public.has_permission(
      (select p.workspace_id from public.projects p where p.id = p_project_id),
      'manage_project_members',
      p_user_id
    )
    or public.has_permission(
      (select p.workspace_id from public.projects p where p.id = p_project_id),
      'manage_settings',
      p_user_id
    );
$$;

create or replace function public.can_manage_project_teams(
  p_project_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_project_owner(p_project_id, p_user_id)
    or public.is_system_admin(p_user_id)
    or public.has_permission(
      (select p.workspace_id from public.projects p where p.id = p_project_id),
      'manage_team',
      p_user_id
    );
$$;

create or replace function public.can_manage_team(
  p_team_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_system_admin(p_user_id)
    or public.is_project_owner(public.project_of_team(p_team_id), p_user_id)
    or (
      public.is_team_lead(p_team_id, p_user_id)
      and (
        public.has_permission(public.workspace_of_team(p_team_id), 'manage_team', p_user_id)
        or public.has_permission(public.workspace_of_team(p_team_id), 'manage_team_members', p_user_id)
      )
    );
$$;

create or replace function public.can_read_project(p_project uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_project_member(p_project, auth.uid());
$$;

create or replace function public.can_write_project(p_project uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_project_owner(p_project, auth.uid())
    or public.is_system_admin(auth.uid())
    or exists (
      select 1
      from public.project_members pm
      where pm.project_id = p_project
        and pm.user_id = auth.uid()
    );
$$;

create or replace function public.can_admin_project(p_project uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.can_manage_project(p_project, auth.uid());
$$;

-- ---------------------------------------------------------------------------
-- 3. System-admin-only creation RPCs
-- ---------------------------------------------------------------------------

drop function if exists public.create_project(uuid, text, text, text, uuid, text, text);

create or replace function public.create_project(
  p_workspace uuid,
  p_name text,
  p_key text,
  p_description text default null,
  p_owner uuid default null,
  p_lead uuid default null,
  p_team_id uuid default null,
  p_icon text default 'Rocket',
  p_color text default '#5B5BD6'
)
returns public.projects
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_project public.projects;
  v_owner uuid;
begin
  if auth.uid() is null or not public.is_system_admin(auth.uid()) then
    raise exception 'Only the system administrator can create projects.';
  end if;

  v_owner := coalesce(p_owner, p_lead, auth.uid());

  if not exists (select 1 from public.profiles where id = v_owner) then
    raise exception 'Project owner does not exist.';
  end if;

  if not exists (select 1 from public.workspaces where id = p_workspace) then
    raise exception 'Workspace does not exist.';
  end if;

  insert into public.projects (
    workspace_id, name, key, description, owner_id, lead_id, team_id, icon, color
  )
  values (
    p_workspace, p_name, upper(p_key), p_description, v_owner, p_lead, p_team_id, p_icon, p_color
  )
  returning * into v_project;

  insert into public.workspace_members (workspace_id, user_id, role)
  values (p_workspace, v_owner, 'member')
  on conflict (workspace_id, user_id) do nothing;

  insert into public.project_members (project_id, user_id, role)
  values (v_project.id, v_owner, 'manager')
  on conflict (project_id, user_id) do update set role = 'manager';

  insert into public.project_statuses (project_id, name, category, color, position)
  values
    (v_project.id, 'To Do', 'todo', '#64748B', 0),
    (v_project.id, 'In Progress', 'in_progress', '#2563EB', 1),
    (v_project.id, 'In Review', 'in_progress', '#A855F7', 2),
    (v_project.id, 'Done', 'done', '#059669', 3);

  insert into public.labels (project_id, name, color)
  values
    (v_project.id, 'frontend', '#2563EB'),
    (v_project.id, 'backend', '#7C3AED'),
    (v_project.id, 'design', '#DB2777'),
    (v_project.id, 'tech-debt', '#D97706');

  return v_project;
end;
$$;

revoke all on function public.create_project(uuid, text, text, text, uuid, uuid, uuid, text, text) from public;
grant execute on function public.create_project(uuid, text, text, text, uuid, uuid, uuid, text, text) to authenticated;

create or replace function public.create_workspace_and_project(
  p_workspace_name text,
  p_project_name text,
  p_project_key text,
  p_project_owner uuid
)
returns public.projects
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_workspace public.workspaces;
begin
  if auth.uid() is null or not public.is_system_admin(auth.uid()) then
    raise exception 'Only the system administrator can provision a workspace and project.';
  end if;

  v_workspace := public.create_workspace(p_workspace_name);

  return public.create_project(
    v_workspace.id,
    p_project_name,
    p_project_key,
    null,
    p_project_owner,
    null,
    null,
    'Rocket',
    '#5B5BD6'
  );
end;
$$;

revoke all on function public.create_workspace_and_project(text, text, text, uuid) from public;
grant execute on function public.create_workspace_and_project(text, text, text, uuid) to authenticated;

-- Direct inserts are disabled. All project creation goes through the RPC.
drop policy if exists projects_insert on public.projects;
create policy projects_insert on public.projects
  for insert to authenticated
  with check (false);

drop policy if exists projects_select on public.projects;
create policy projects_select on public.projects
  for select to authenticated
  using (
    public.can_read_project(id)
    or public.is_system_admin(auth.uid())
    or is_archived = false
  );

drop policy if exists projects_update on public.projects;
create policy projects_update on public.projects
  for update to authenticated
  using (public.can_admin_project(id))
  with check (public.can_admin_project(id));

drop policy if exists projects_delete on public.projects;
create policy projects_delete on public.projects
  for delete to authenticated
  using (public.is_system_admin(auth.uid()));

create or replace function public.validate_project_join_request_insert()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.user_id <> auth.uid() or new.status <> 'pending' then
    raise exception 'A user may only create their own pending join request.';
  end if;

  if not exists (
    select 1 from public.projects p
    where p.id = new.project_id and p.is_archived = false
  ) then
    raise exception 'Project does not exist or is archived.';
  end if;

  if public.is_project_member(new.project_id, new.user_id) then
    raise exception 'Requester is already a project member.';
  end if;

  if exists (
    select 1 from public.project_join_requests r
    where r.project_id = new.project_id
      and r.user_id = new.user_id
      and r.status = 'pending'
  ) then
    raise exception 'A pending join request already exists for this project.';
  end if;

  return new;
end;
$$;

drop policy if exists project_join_requests_insert on public.project_join_requests;
create policy project_join_requests_insert on public.project_join_requests
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and status = 'pending'
    and exists (
      select 1 from public.projects p
      where p.id = project_join_requests.project_id
        and p.is_archived = false
    )
  );

-- Workspace writes are also global-admin-only, including direct inserts.
drop policy if exists workspaces_insert on public.workspaces;
create policy workspaces_insert on public.workspaces
  for insert to authenticated
  with check (public.is_system_admin(auth.uid()) and owner_id = auth.uid());

drop policy if exists workspaces_update_admin on public.workspaces;
create policy workspaces_update_admin on public.workspaces
  for update to authenticated
  using (public.is_system_admin(auth.uid()))
  with check (public.is_system_admin(auth.uid()));

drop policy if exists workspaces_delete_owner on public.workspaces;
create policy workspaces_delete_owner on public.workspaces
  for delete to authenticated
  using (public.is_system_admin(auth.uid()));

-- System-admin visibility is needed for global administration and user choice.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or public.shares_workspace(id)
    or public.is_system_admin(auth.uid())
  );

-- ---------------------------------------------------------------------------
-- 4. Project-scoped invitations
-- ---------------------------------------------------------------------------

do $$ begin
  create type public.project_invitation_status as enum ('pending', 'accepted', 'cancelled', 'expired');
exception when duplicate_object then null; end $$;

create table if not exists public.project_invitations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  team_id uuid references public.teams(id) on delete set null,
  invited_email text not null check (char_length(trim(invited_email)) between 3 and 320),
  invited_by uuid not null references public.profiles(id) on delete restrict,
  token text not null unique,
  status public.project_invitation_status not null default 'pending',
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists project_invitations_project_idx
  on public.project_invitations(project_id, status);
create index if not exists project_invitations_team_idx
  on public.project_invitations(team_id, status);
create index if not exists project_invitations_email_idx
  on public.project_invitations(lower(invited_email), status);
create unique index if not exists project_invitations_pending_unique
  on public.project_invitations(project_id, lower(invited_email), coalesce(team_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where status = 'pending';

create or replace function public.validate_project_invitation()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.team_id is not null and not exists (
    select 1
    from public.teams t
    where t.id = new.team_id
      and (t.project_id = new.project_id or exists (
        select 1 from public.projects p
        where p.id = new.project_id and p.team_id = t.id
      ))
  ) then
    raise exception 'Invitation team must belong to the invited project.';
  end if;
  return new;
end;
$$;

drop trigger if exists project_invitation_validate on public.project_invitations;
create trigger project_invitation_validate
before insert or update of project_id, team_id on public.project_invitations
for each row execute function public.validate_project_invitation();

alter table public.project_invitations enable row level security;

drop policy if exists project_invitations_select on public.project_invitations;
create policy project_invitations_select on public.project_invitations
  for select to authenticated
  using (
    invited_by = auth.uid()
    or public.is_system_admin(auth.uid())
    or lower(invited_email) = lower(public.auth_email())
  );

drop policy if exists project_invitations_insert on public.project_invitations;
create policy project_invitations_insert on public.project_invitations
  for insert to authenticated
  with check (
    invited_by = auth.uid()
    and (
      public.is_project_owner(project_id, auth.uid())
      or public.is_system_admin(auth.uid())
      or (
        team_id is not null
        and public.can_manage_team(team_id, auth.uid())
      )
    )
  );

drop policy if exists project_invitations_update on public.project_invitations;
create policy project_invitations_update on public.project_invitations
  for update to authenticated
  using (
    public.is_project_owner(project_id, auth.uid())
    or public.is_system_admin(auth.uid())
    or (team_id is not null and public.can_manage_team(team_id, auth.uid()))
  )
  with check (status in ('pending', 'accepted', 'cancelled', 'expired'));

-- Generate a token only on the server-side database boundary.
create or replace function public.create_project_invitation(
  p_project_id uuid,
  p_invited_email text,
  p_team_id uuid default null,
  p_expires_at timestamptz default (now() + interval '7 days')
)
returns public.project_invitations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_invitation public.project_invitations;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not (
    public.is_project_owner(p_project_id, auth.uid())
    or public.is_system_admin(auth.uid())
    or (p_team_id is not null and public.can_manage_team(p_team_id, auth.uid()))
  ) then
    raise exception 'You cannot create an invitation for this project.';
  end if;

  if p_team_id is not null and not exists (
    select 1 from public.teams t
    where t.id = p_team_id
      and (t.project_id = p_project_id or exists (
        select 1 from public.projects p where p.id = p_project_id and p.team_id = t.id
      ))
  ) then
    raise exception 'Team does not belong to this project.';
  end if;

  insert into public.project_invitations (
    project_id, team_id, invited_email, invited_by, token, expires_at
  )
  values (
    p_project_id,
    p_team_id,
    lower(trim(p_invited_email)),
    auth.uid(),
    encode(gen_random_bytes(32), 'hex'),
    least(p_expires_at, now() + interval '30 days')
  )
  returning * into v_invitation;

  return v_invitation;
end;
$$;

create or replace function public.get_project_invitation_preview(p_token text)
returns table (
  project_name text,
  team_name text,
  inviter_name text,
  status text,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    p.name,
    t.name,
    coalesce(inviter.full_name, inviter.email),
    case when i.status = 'pending' and i.expires_at <= now() then 'expired' else i.status::text end,
    i.expires_at
  from public.project_invitations i
  join public.projects p on p.id = i.project_id
  left join public.teams t on t.id = i.team_id
  join public.profiles inviter on inviter.id = i.invited_by
  where i.token = p_token;
$$;

create or replace function public.accept_project_invitation(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_invitation public.project_invitations;
  v_email text;
  v_project_workspace uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required before accepting an invitation.';
  end if;

  select lower(email) into v_email
  from public.profiles
  where id = auth.uid();

  select * into v_invitation
  from public.project_invitations
  where token = p_token
  for update;

  if v_invitation.id is null
    or v_invitation.status <> 'pending'
    or v_invitation.expires_at <= now() then
    raise exception 'This invitation is invalid or has expired.';
  end if;

  if lower(v_invitation.invited_email) <> v_email then
    raise exception 'This invitation was issued to a different email address.';
  end if;

  select workspace_id into v_project_workspace
  from public.projects
  where id = v_invitation.project_id
    and is_archived = false;

  if v_project_workspace is null then
    raise exception 'The invited project is not available.';
  end if;

  insert into public.workspace_members (workspace_id, user_id, role)
  values (v_project_workspace, auth.uid(), 'member')
  on conflict (workspace_id, user_id) do nothing;

  insert into public.project_members (project_id, user_id, role)
  values (v_invitation.project_id, auth.uid(), 'member')
  on conflict (project_id, user_id) do nothing;

  if v_invitation.team_id is not null then
    insert into public.team_members (team_id, user_id, role)
    values (v_invitation.team_id, auth.uid(), 'member')
    on conflict (team_id, user_id) do nothing;
  end if;

  update public.project_invitations
  set status = 'accepted', accepted_at = now()
  where id = v_invitation.id;

  return v_invitation.project_id;
end;
$$;

grant execute on function public.get_project_invitation_preview(text) to anon, authenticated;
grant execute on function public.accept_project_invitation(text) to authenticated;
grant execute on function public.create_project_invitation(uuid, text, uuid, timestamptz) to authenticated;

drop policy if exists team_members_select on public.team_members;
create policy team_members_select on public.team_members
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.can_manage_team(team_id, auth.uid())
    or public.is_team_member(team_id, auth.uid())
  );

drop policy if exists project_members_select on public.project_members;
create policy project_members_select on public.project_members
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_project_owner(project_id, auth.uid())
    or public.is_system_admin(auth.uid())
  );

drop policy if exists project_members_insert on public.project_members;
create policy project_members_insert on public.project_members
  for insert to authenticated
  with check (
    public.is_project_owner(project_id, auth.uid())
    or public.is_system_admin(auth.uid())
  );

drop policy if exists project_members_update on public.project_members;
create policy project_members_update on public.project_members
  for update to authenticated
  using (public.is_project_owner(project_id, auth.uid()) or public.is_system_admin(auth.uid()))
  with check (public.is_project_owner(project_id, auth.uid()) or public.is_system_admin(auth.uid()));

drop policy if exists project_members_delete on public.project_members;
create policy project_members_delete on public.project_members
  for delete to authenticated
  using (public.is_project_owner(project_id, auth.uid()) or public.is_system_admin(auth.uid()));

drop policy if exists roles_insert on public.roles;
create policy roles_insert on public.roles
  for insert to authenticated
  with check (
    public.is_workspace_project_owner(workspace_id, auth.uid())
    or public.has_permission(workspace_id, 'manage_roles', auth.uid())
    or public.is_system_admin(auth.uid())
  );

drop policy if exists roles_update on public.roles;
create policy roles_update on public.roles
  for update to authenticated
  using (
    public.is_workspace_project_owner(workspace_id, auth.uid())
    or public.has_permission(workspace_id, 'manage_roles', auth.uid())
    or public.is_system_admin(auth.uid())
  )
  with check (
    public.is_workspace_project_owner(workspace_id, auth.uid())
    or public.has_permission(workspace_id, 'manage_roles', auth.uid())
    or public.is_system_admin(auth.uid())
  );

drop policy if exists roles_delete on public.roles;
create policy roles_delete on public.roles
  for delete to authenticated
  using (
    public.is_workspace_project_owner(workspace_id, auth.uid())
    or public.has_permission(workspace_id, 'manage_roles', auth.uid())
    or public.is_system_admin(auth.uid())
  );

-- Project owner/member access is project-scoped; team leads remain team-scoped.
drop policy if exists teams_select on public.teams;
create policy teams_select on public.teams
  for select to authenticated
  using (
    public.is_system_admin(auth.uid())
    or (project_id is not null and public.can_read_project(project_id))
    or public.is_workspace_member(workspace_id)
  );

drop policy if exists teams_insert on public.teams;
create policy teams_insert on public.teams
  for insert to authenticated
  with check (
    (project_id is not null and public.is_project_owner(project_id, auth.uid()))
    or (project_id is null and public.is_system_admin(auth.uid()))
  );

drop policy if exists teams_update on public.teams;
create policy teams_update on public.teams
  for update to authenticated
  using (
    (project_id is not null and public.can_manage_team(id, auth.uid()))
    or (project_id is null and public.is_system_admin(auth.uid()))
  )
  with check (
    (project_id is not null and public.can_manage_team(id, auth.uid()))
    or (project_id is null and public.is_system_admin(auth.uid()))
  );

drop policy if exists teams_delete on public.teams;
create policy teams_delete on public.teams
  for delete to authenticated
  using (
    (project_id is not null and public.can_manage_team(id, auth.uid()))
    or (project_id is null and public.is_system_admin(auth.uid()))
  );

drop policy if exists team_members_insert on public.team_members;
create policy team_members_insert on public.team_members
  for insert to authenticated
  with check (
    public.can_manage_team(team_id, auth.uid())
    and exists (
      select 1
      from public.teams t
      where t.id = team_members.team_id
        and (
          t.project_id is null
          or public.is_project_member(t.project_id, user_id)
        )
    )
  );

drop policy if exists team_members_update on public.team_members;
create policy team_members_update on public.team_members
  for update to authenticated
  using (public.can_manage_team(team_id, auth.uid()))
  with check (
    public.can_manage_team(team_id, auth.uid())
    and exists (
      select 1
      from public.teams t
      where t.id = team_members.team_id
        and (t.project_id is null or public.is_project_member(t.project_id, user_id))
    )
  );

drop policy if exists team_members_delete on public.team_members;
create policy team_members_delete on public.team_members
  for delete to authenticated
  using (public.can_manage_team(team_id, auth.uid()));

drop policy if exists workspace_member_roles_insert on public.workspace_member_roles;
create policy workspace_member_roles_insert on public.workspace_member_roles
  for insert to authenticated
  with check (
    public.is_workspace_project_owner(workspace_id, auth.uid())
    or public.has_permission(workspace_id, 'manage_roles', auth.uid())
    or public.is_system_admin(auth.uid())
  );

drop policy if exists workspace_member_roles_update on public.workspace_member_roles;
create policy workspace_member_roles_update on public.workspace_member_roles
  for update to authenticated
  using (
    public.is_workspace_project_owner(workspace_id, auth.uid())
    or public.has_permission(workspace_id, 'manage_roles', auth.uid())
    or public.is_system_admin(auth.uid())
  )
  with check (
    public.is_workspace_project_owner(workspace_id, auth.uid())
    or public.has_permission(workspace_id, 'manage_roles', auth.uid())
    or public.is_system_admin(auth.uid())
  );

drop policy if exists workspace_member_roles_delete on public.workspace_member_roles;
create policy workspace_member_roles_delete on public.workspace_member_roles
  for delete to authenticated
  using (
    public.is_workspace_project_owner(workspace_id, auth.uid())
    or public.has_permission(workspace_id, 'manage_roles', auth.uid())
    or public.is_system_admin(auth.uid())
  );

drop policy if exists role_permissions_insert on public.role_permissions;
create policy role_permissions_insert on public.role_permissions
  for insert to authenticated
  with check (
    exists (
      select 1 from public.roles r
      where r.id = role_permissions.role_id
        and (
          public.is_workspace_project_owner(r.workspace_id, auth.uid())
          or public.has_permission(r.workspace_id, 'manage_permissions', auth.uid())
          or public.is_system_admin(auth.uid())
        )
    )
  );

drop policy if exists role_permissions_update on public.role_permissions;
create policy role_permissions_update on public.role_permissions
  for update to authenticated
  using (
    exists (
      select 1 from public.roles r
      where r.id = role_permissions.role_id
        and (
          public.is_workspace_project_owner(r.workspace_id, auth.uid())
          or public.has_permission(r.workspace_id, 'manage_permissions', auth.uid())
          or public.is_system_admin(auth.uid())
        )
    )
  )
  with check (
    exists (
      select 1 from public.roles r
      where r.id = role_permissions.role_id
        and (
          public.is_workspace_project_owner(r.workspace_id, auth.uid())
          or public.has_permission(r.workspace_id, 'manage_permissions', auth.uid())
          or public.is_system_admin(auth.uid())
        )
    )
  );

drop policy if exists role_permissions_delete on public.role_permissions;
create policy role_permissions_delete on public.role_permissions
  for delete to authenticated
  using (
    exists (
      select 1 from public.roles r
      where r.id = role_permissions.role_id
        and (
          public.is_workspace_project_owner(r.workspace_id, auth.uid())
          or public.has_permission(r.workspace_id, 'manage_permissions', auth.uid())
          or public.is_system_admin(auth.uid())
        )
    )
  );

commit;
