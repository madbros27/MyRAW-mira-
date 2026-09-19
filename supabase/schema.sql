-- ===========================================================================
-- MIRA — complete schema
--
-- GENERATED FILE — do not edit by hand.
-- Built from supabase/migrations by `npm run db:schema`.
--
-- Paste this whole file into the Supabase SQL editor, or prefer the CLI:
--   supabase link --project-ref <ref> && supabase db push
-- ===========================================================================


-- >>> 20250101000000_init.sql -------------------------------------------

-- ===========================================================================
-- MIRA — 01. Schema
-- Extensions, enums, tables and indexes.
-- ===========================================================================

create extension if not exists "pgcrypto" with schema extensions;
create extension if not exists "pg_trgm" with schema extensions;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.workspace_role as enum ('admin', 'lead', 'member', 'viewer');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.issue_type as enum ('epic', 'story', 'task', 'bug', 'subtask');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.issue_priority as enum ('highest', 'high', 'medium', 'low', 'lowest');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.status_category as enum ('todo', 'in_progress', 'done');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.sprint_status as enum ('planned', 'active', 'completed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.notification_type as enum (
    'assigned', 'mentioned', 'status_changed', 'commented',
    'issue_created', 'sprint_started', 'sprint_completed', 'invited'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.invite_status as enum ('pending', 'accepted', 'revoked', 'expired');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- profiles — one row per auth user, kept in sync by a trigger on auth.users
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text not null,
  full_name   text,
  avatar_url  text,
  job_title   text,
  timezone    text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.profiles is 'Public profile mirror of auth.users.';

-- ---------------------------------------------------------------------------
-- workspaces — the multi-tenant boundary
-- ---------------------------------------------------------------------------
create table if not exists public.workspaces (
  id          uuid primary key default extensions.gen_random_uuid(),
  name        text not null check (char_length(trim(name)) between 1 and 80),
  slug        text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,48}$'),
  description text,
  avatar_url  text,
  owner_id    uuid not null references public.profiles (id) on delete restrict,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.workspace_members (
  workspace_id uuid not null references public.workspaces (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  role         public.workspace_role not null default 'member',
  created_at   timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create index if not exists workspace_members_user_idx on public.workspace_members (user_id);

-- ---------------------------------------------------------------------------
-- projects
-- ---------------------------------------------------------------------------
create table if not exists public.projects (
  id            uuid primary key default extensions.gen_random_uuid(),
  workspace_id  uuid not null references public.workspaces (id) on delete cascade,
  name          text not null check (char_length(trim(name)) between 1 and 80),
  key           text not null check (key ~ '^[A-Z][A-Z0-9]{1,9}$'),
  description   text,
  lead_id       uuid references public.profiles (id) on delete set null,
  icon          text not null default 'Rocket',
  color         text not null default '#5B5BD6',
  is_archived   boolean not null default false,
  issue_counter integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (workspace_id, key)
);

create index if not exists projects_workspace_idx on public.projects (workspace_id);

-- ---------------------------------------------------------------------------
-- project_statuses — the configurable workflow columns of a project
-- ---------------------------------------------------------------------------
create table if not exists public.project_statuses (
  id         uuid primary key default extensions.gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  name       text not null check (char_length(trim(name)) between 1 and 40),
  category   public.status_category not null default 'todo',
  color      text not null default '#64748B',
  position   integer not null default 0,
  wip_limit  integer check (wip_limit is null or wip_limit > 0),
  created_at timestamptz not null default now(),
  unique (project_id, name)
);

create index if not exists project_statuses_project_idx
  on public.project_statuses (project_id, position);

-- Allowed workflow transitions. An empty set for a given `from` status means
-- "any transition is allowed" — projects only become restrictive once a lead
-- defines transitions explicitly.
create table if not exists public.status_transitions (
  id             uuid primary key default extensions.gen_random_uuid(),
  project_id     uuid not null references public.projects (id) on delete cascade,
  from_status_id uuid not null references public.project_statuses (id) on delete cascade,
  to_status_id   uuid not null references public.project_statuses (id) on delete cascade,
  unique (from_status_id, to_status_id),
  check (from_status_id <> to_status_id)
);

create index if not exists status_transitions_project_idx
  on public.status_transitions (project_id);

-- ---------------------------------------------------------------------------
-- sprints
-- ---------------------------------------------------------------------------
create table if not exists public.sprints (
  id               uuid primary key default extensions.gen_random_uuid(),
  project_id       uuid not null references public.projects (id) on delete cascade,
  name             text not null check (char_length(trim(name)) between 1 and 80),
  goal             text,
  start_date       timestamptz,
  end_date         timestamptz,
  status           public.sprint_status not null default 'planned',
  retrospective    text,
  committed_points numeric(7, 1),
  completed_points numeric(7, 1),
  completed_at     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (start_date is null or end_date is null or end_date >= start_date)
);

create index if not exists sprints_project_idx on public.sprints (project_id, status);

-- Only one active sprint per project.
create unique index if not exists sprints_one_active_per_project
  on public.sprints (project_id)
  where status = 'active';

-- ---------------------------------------------------------------------------
-- issues
-- ---------------------------------------------------------------------------
create table if not exists public.issues (
  id               uuid primary key default extensions.gen_random_uuid(),
  project_id       uuid not null references public.projects (id) on delete cascade,
  issue_number     integer not null,
  type             public.issue_type not null default 'task',
  title            text not null check (char_length(trim(title)) between 1 and 300),
  description      text,
  status_id        uuid not null references public.project_statuses (id) on delete restrict,
  priority         public.issue_priority not null default 'medium',
  assignee_id      uuid references public.profiles (id) on delete set null,
  reporter_id      uuid references public.profiles (id) on delete set null,
  epic_id          uuid references public.issues (id) on delete set null,
  parent_id        uuid references public.issues (id) on delete cascade,
  sprint_id        uuid references public.sprints (id) on delete set null,
  story_points     numeric(5, 1) check (story_points is null or story_points >= 0),
  due_date         date,
  board_position   double precision not null default 0,
  backlog_position double precision not null default 0,
  resolved_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (project_id, issue_number),
  check (id <> parent_id),
  check (id <> epic_id)
);

-- Full-text search vector over title + description.
alter table public.issues
  drop column if exists search_vector;
alter table public.issues
  add column search_vector tsvector generated always as (
    setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(description, '')), 'B')
  ) stored;

create index if not exists issues_project_idx on public.issues (project_id);
create index if not exists issues_status_idx on public.issues (status_id, board_position);
create index if not exists issues_sprint_idx on public.issues (sprint_id);
create index if not exists issues_assignee_idx on public.issues (assignee_id);
create index if not exists issues_epic_idx on public.issues (epic_id);
create index if not exists issues_parent_idx on public.issues (parent_id);
create index if not exists issues_backlog_idx on public.issues (project_id, backlog_position);
create index if not exists issues_search_idx on public.issues using gin (search_vector);
create index if not exists issues_title_trgm_idx
  on public.issues using gin (title extensions.gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- labels
-- ---------------------------------------------------------------------------
create table if not exists public.labels (
  id         uuid primary key default extensions.gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  name       text not null check (char_length(trim(name)) between 1 and 40),
  color      text not null default '#64748B',
  created_at timestamptz not null default now(),
  unique (project_id, name)
);

create table if not exists public.issue_labels (
  issue_id uuid not null references public.issues (id) on delete cascade,
  label_id uuid not null references public.labels (id) on delete cascade,
  primary key (issue_id, label_id)
);

create index if not exists issue_labels_label_idx on public.issue_labels (label_id);

-- ---------------------------------------------------------------------------
-- comments (+ edit history)
-- ---------------------------------------------------------------------------
create table if not exists public.comments (
  id         uuid primary key default extensions.gen_random_uuid(),
  issue_id   uuid not null references public.issues (id) on delete cascade,
  author_id  uuid references public.profiles (id) on delete set null,
  body       text not null check (char_length(body) between 1 and 20000),
  is_edited  boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.comments
  drop column if exists search_vector;
alter table public.comments
  add column search_vector tsvector generated always as (
    to_tsvector('english', coalesce(body, ''))
  ) stored;

create index if not exists comments_issue_idx on public.comments (issue_id, created_at);
create index if not exists comments_search_idx on public.comments using gin (search_vector);

create table if not exists public.comment_revisions (
  id         uuid primary key default extensions.gen_random_uuid(),
  comment_id uuid not null references public.comments (id) on delete cascade,
  body       text not null,
  editor_id  uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists comment_revisions_comment_idx
  on public.comment_revisions (comment_id, created_at desc);

-- ---------------------------------------------------------------------------
-- attachments — metadata for objects in the `attachments` storage bucket
-- ---------------------------------------------------------------------------
create table if not exists public.attachments (
  id           uuid primary key default extensions.gen_random_uuid(),
  issue_id     uuid not null references public.issues (id) on delete cascade,
  storage_path text not null,
  file_name    text not null,
  file_size    bigint not null default 0,
  mime_type    text,
  uploaded_by  uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now()
);

create index if not exists attachments_issue_idx on public.attachments (issue_id);

-- ---------------------------------------------------------------------------
-- activity_log — append-only audit trail per issue
-- ---------------------------------------------------------------------------
create table if not exists public.activity_log (
  id            uuid primary key default extensions.gen_random_uuid(),
  issue_id      uuid not null references public.issues (id) on delete cascade,
  actor_id      uuid references public.profiles (id) on delete set null,
  action        text not null,
  field_changed text,
  old_value     text,
  new_value     text,
  created_at    timestamptz not null default now()
);

create index if not exists activity_log_issue_idx
  on public.activity_log (issue_id, created_at desc);

-- ---------------------------------------------------------------------------
-- watchers
-- ---------------------------------------------------------------------------
create table if not exists public.watchers (
  issue_id   uuid not null references public.issues (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (issue_id, user_id)
);

create index if not exists watchers_user_idx on public.watchers (user_id);

-- ---------------------------------------------------------------------------
-- notifications
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id           uuid primary key default extensions.gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  workspace_id uuid references public.workspaces (id) on delete cascade,
  project_id   uuid references public.projects (id) on delete cascade,
  issue_id     uuid references public.issues (id) on delete cascade,
  actor_id     uuid references public.profiles (id) on delete set null,
  type         public.notification_type not null,
  title        text not null,
  body         text,
  payload      jsonb not null default '{}'::jsonb,
  is_read      boolean not null default false,
  created_at   timestamptz not null default now()
);

create index if not exists notifications_user_idx
  on public.notifications (user_id, is_read, created_at desc);

-- ---------------------------------------------------------------------------
-- saved_filters — the "JQL-lite" query builder store
-- ---------------------------------------------------------------------------
create table if not exists public.saved_filters (
  id           uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete cascade,
  project_id   uuid references public.projects (id) on delete cascade,
  owner_id     uuid not null references public.profiles (id) on delete cascade,
  name         text not null check (char_length(trim(name)) between 1 and 60),
  query        jsonb not null default '{}'::jsonb,
  is_shared    boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists saved_filters_workspace_idx
  on public.saved_filters (workspace_id, owner_id);

-- ---------------------------------------------------------------------------
-- workspace_invites
-- ---------------------------------------------------------------------------
create table if not exists public.workspace_invites (
  id           uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id) on delete cascade,
  email        text not null check (position('@' in email) > 1),
  role         public.workspace_role not null default 'member',
  invited_by   uuid references public.profiles (id) on delete set null,
  token        text not null unique default encode(extensions.gen_random_bytes(24), 'hex'),
  status       public.invite_status not null default 'pending',
  expires_at   timestamptz not null default now() + interval '14 days',
  accepted_at  timestamptz,
  created_at   timestamptz not null default now()
);

create unique index if not exists workspace_invites_pending_unique
  on public.workspace_invites (workspace_id, lower(email))
  where status = 'pending';

create index if not exists workspace_invites_email_idx
  on public.workspace_invites (lower(email), status);


-- >>> 20250101000100_functions.sql --------------------------------------

-- ===========================================================================
-- MIRA — 02. Functions & triggers
--
-- Membership helpers are SECURITY DEFINER so that RLS policies can ask
-- "is the caller a member of this workspace?" without recursing back into the
-- policies of workspace_members itself.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Generic helpers
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.slugify(p_text text)
returns text
language sql
immutable
set search_path = pg_temp
as $$
  select coalesce(
    nullif(
      trim(both '-' from regexp_replace(lower(p_text), '[^a-z0-9]+', '-', 'g')),
      ''
    ),
    'workspace'
  );
$$;

-- ---------------------------------------------------------------------------
-- Authorization helpers
-- ---------------------------------------------------------------------------
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
  );
$$;

-- Named `current_workspace_role` rather than `workspace_role` so the function
-- never shadows the enum type of the same name in a function-style cast.
create or replace function public.current_workspace_role(p_workspace uuid)
returns public.workspace_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select m.role
  from public.workspace_members m
  where m.workspace_id = p_workspace
    and m.user_id = auth.uid();
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
  );
$$;

create or replace function public.project_workspace(p_project uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.workspace_id from public.projects p where p.id = p_project;
$$;

create or replace function public.issue_project(p_issue uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select i.project_id from public.issues i where i.id = p_issue;
$$;

-- Read access: any member of the owning workspace.
create or replace function public.can_read_project(p_project uuid)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select public.is_workspace_member(public.project_workspace(p_project));
$$;

-- Write access: admin, lead or member (viewers are read-only).
create or replace function public.can_write_project(p_project uuid)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select public.has_workspace_role(
    public.project_workspace(p_project),
    array['admin', 'lead', 'member']::public.workspace_role[]
  );
$$;

-- Administer a project (workflow, labels, delete, sprint lifecycle).
create or replace function public.can_admin_project(p_project uuid)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select public.has_workspace_role(
    public.project_workspace(p_project),
    array['admin', 'lead']::public.workspace_role[]
  );
$$;

create or replace function public.can_read_issue(p_issue uuid)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select public.can_read_project(public.issue_project(p_issue));
$$;

create or replace function public.can_write_issue(p_issue uuid)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select public.can_write_project(public.issue_project(p_issue));
$$;

create or replace function public.issue_key(p_project uuid, p_number integer)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.key || '-' || p_number from public.projects p where p.id = p_project;
$$;

-- ---------------------------------------------------------------------------
-- profiles <- auth.users
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

  -- Direct registration only: create the profile, do not seed demo workspaces,
  -- projects, or claims from any invite table.
  return new;
end;
$$;

create or replace function public.handle_user_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.profiles
     set email = new.email,
         updated_at = now()
   where id = new.id
     and email is distinct from new.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated
  after update of email on auth.users
  for each row execute function public.handle_user_update();

-- ---------------------------------------------------------------------------
-- Issue numbering & defaults
-- ---------------------------------------------------------------------------
create or replace function public.assign_issue_defaults()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_counter integer;
begin
  -- Atomic per-project counter -> MIRA-1, MIRA-2, ...
  update public.projects
     set issue_counter = issue_counter + 1
   where id = new.project_id
  returning issue_counter into v_counter;

  if v_counter is null then
    raise exception 'Unknown project %', new.project_id;
  end if;

  new.issue_number := v_counter;

  if new.reporter_id is null then
    new.reporter_id := auth.uid();
  end if;

  if new.status_id is null then
    select s.id into new.status_id
      from public.project_statuses s
     where s.project_id = new.project_id
     order by s.position, s.created_at
     limit 1;
  end if;

  if coalesce(new.board_position, 0) = 0 then
    select coalesce(max(i.board_position), 0) + 1024
      into new.board_position
      from public.issues i
     where i.status_id = new.status_id;
  end if;

  if coalesce(new.backlog_position, 0) = 0 then
    select coalesce(max(i.backlog_position), 0) + 1024
      into new.backlog_position
      from public.issues i
     where i.project_id = new.project_id;
  end if;

  return new;
end;
$$;

drop trigger if exists issues_assign_defaults on public.issues;
create trigger issues_assign_defaults
  before insert on public.issues
  for each row execute function public.assign_issue_defaults();

-- Keep resolved_at in sync with the status category, and guard the workflow.
create or replace function public.handle_issue_status_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_new_category public.status_category;
  v_restricted boolean;
begin
  select category into v_new_category
    from public.project_statuses where id = new.status_id;

  if tg_op = 'UPDATE' and new.status_id is distinct from old.status_id then
    -- Enforce custom transitions only when the project defines them.
    select exists (
      select 1 from public.status_transitions t
       where t.from_status_id = old.status_id
    ) into v_restricted;

    if v_restricted and not exists (
      select 1 from public.status_transitions t
       where t.from_status_id = old.status_id
         and t.to_status_id = new.status_id
    ) then
      raise exception
        'Transition is not allowed by this project workflow'
        using errcode = 'check_violation';
    end if;
  end if;

  if v_new_category = 'done' then
    if new.resolved_at is null then
      new.resolved_at := now();
    end if;
  else
    new.resolved_at := null;
  end if;

  return new;
end;
$$;

drop trigger if exists issues_status_change on public.issues;
create trigger issues_status_change
  before insert or update of status_id on public.issues
  for each row execute function public.handle_issue_status_change();

-- ---------------------------------------------------------------------------
-- Activity log
-- ---------------------------------------------------------------------------
create or replace function public.log_issue_activity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    insert into public.activity_log (issue_id, actor_id, action)
    values (new.id, coalesce(v_actor, new.reporter_id), 'created');
    return new;
  end if;

  if new.title is distinct from old.title then
    insert into public.activity_log (issue_id, actor_id, action, field_changed, old_value, new_value)
    values (new.id, v_actor, 'updated', 'title', old.title, new.title);
  end if;

  if new.description is distinct from old.description then
    insert into public.activity_log (issue_id, actor_id, action, field_changed, old_value, new_value)
    values (new.id, v_actor, 'updated', 'description', null, null);
  end if;

  if new.status_id is distinct from old.status_id then
    insert into public.activity_log (issue_id, actor_id, action, field_changed, old_value, new_value)
    values (
      new.id, v_actor, 'updated', 'status',
      (select name from public.project_statuses where id = old.status_id),
      (select name from public.project_statuses where id = new.status_id)
    );
  end if;

  if new.assignee_id is distinct from old.assignee_id then
    insert into public.activity_log (issue_id, actor_id, action, field_changed, old_value, new_value)
    values (
      new.id, v_actor, 'updated', 'assignee',
      (select full_name from public.profiles where id = old.assignee_id),
      (select full_name from public.profiles where id = new.assignee_id)
    );
  end if;

  if new.priority is distinct from old.priority then
    insert into public.activity_log (issue_id, actor_id, action, field_changed, old_value, new_value)
    values (new.id, v_actor, 'updated', 'priority', old.priority::text, new.priority::text);
  end if;

  if new.type is distinct from old.type then
    insert into public.activity_log (issue_id, actor_id, action, field_changed, old_value, new_value)
    values (new.id, v_actor, 'updated', 'type', old.type::text, new.type::text);
  end if;

  if new.story_points is distinct from old.story_points then
    insert into public.activity_log (issue_id, actor_id, action, field_changed, old_value, new_value)
    values (new.id, v_actor, 'updated', 'story_points', old.story_points::text, new.story_points::text);
  end if;

  if new.due_date is distinct from old.due_date then
    insert into public.activity_log (issue_id, actor_id, action, field_changed, old_value, new_value)
    values (new.id, v_actor, 'updated', 'due_date', old.due_date::text, new.due_date::text);
  end if;

  if new.sprint_id is distinct from old.sprint_id then
    insert into public.activity_log (issue_id, actor_id, action, field_changed, old_value, new_value)
    values (
      new.id, v_actor, 'updated', 'sprint',
      (select name from public.sprints where id = old.sprint_id),
      (select name from public.sprints where id = new.sprint_id)
    );
  end if;

  if new.epic_id is distinct from old.epic_id then
    insert into public.activity_log (issue_id, actor_id, action, field_changed, old_value, new_value)
    values (
      new.id, v_actor, 'updated', 'epic',
      (select title from public.issues where id = old.epic_id),
      (select title from public.issues where id = new.epic_id)
    );
  end if;

  return new;
end;
$$;

drop trigger if exists issues_activity_log on public.issues;
create trigger issues_activity_log
  after insert or update on public.issues
  for each row execute function public.log_issue_activity();

-- ---------------------------------------------------------------------------
-- Watchers — reporters and assignees follow their issues automatically
-- ---------------------------------------------------------------------------
create or replace function public.sync_issue_watchers()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.reporter_id is not null then
    insert into public.watchers (issue_id, user_id)
    values (new.id, new.reporter_id)
    on conflict do nothing;
  end if;

  if new.assignee_id is not null then
    insert into public.watchers (issue_id, user_id)
    values (new.id, new.assignee_id)
    on conflict do nothing;
  end if;

  return null;
end;
$$;

drop trigger if exists issues_sync_watchers on public.issues;
create trigger issues_sync_watchers
  after insert or update of assignee_id on public.issues
  for each row execute function public.sync_issue_watchers();

-- ---------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------
create or replace function public.notify_issue_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_workspace uuid;
  v_key text;
  v_status text;
begin
  select p.workspace_id, p.key || '-' || new.issue_number
    into v_workspace, v_key
    from public.projects p
   where p.id = new.project_id;

  -- Assigned to you
  if new.assignee_id is not null
     and new.assignee_id is distinct from v_actor
     and (tg_op = 'INSERT' or new.assignee_id is distinct from old.assignee_id)
  then
    insert into public.notifications
      (user_id, workspace_id, project_id, issue_id, actor_id, type, title, body, payload)
    values (
      new.assignee_id, v_workspace, new.project_id, new.id, v_actor, 'assigned',
      v_key || ' was assigned to you', new.title,
      jsonb_build_object('issue_key', v_key)
    );
  end if;

  -- Status changed -> every watcher except the actor
  if tg_op = 'UPDATE' and new.status_id is distinct from old.status_id then
    select name into v_status from public.project_statuses where id = new.status_id;

    insert into public.notifications
      (user_id, workspace_id, project_id, issue_id, actor_id, type, title, body, payload)
    select w.user_id, v_workspace, new.project_id, new.id, v_actor, 'status_changed',
           v_key || ' moved to ' || v_status, new.title,
           jsonb_build_object('issue_key', v_key, 'status', v_status)
      from public.watchers w
     where w.issue_id = new.id
       and w.user_id is distinct from v_actor;
  end if;

  return null;
end;
$$;

drop trigger if exists issues_notify on public.issues;
create trigger issues_notify
  after insert or update on public.issues
  for each row execute function public.notify_issue_change();

-- Comments: notify mentioned users (type "mentioned") and everyone else
-- watching the issue (type "commented"). Mentions are encoded by the client as
-- `@[Display Name](user-uuid)` so the parsing can stay server-side.
create or replace function public.notify_comment()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_workspace uuid;
  v_project uuid;
  v_key text;
  v_mentioned uuid[];
begin
  select p.workspace_id, p.id, p.key || '-' || i.issue_number
    into v_workspace, v_project, v_key
    from public.issues i
    join public.projects p on p.id = i.project_id
   where i.id = new.issue_id;

  -- The regex matches the exact UUID shape, so the ::uuid cast can never
  -- raise and break the comment insert. `regexp_matches` is set-returning and
  -- therefore called in FROM rather than in the select list.
  select coalesce(array_agg(distinct (m.groups)[1]::uuid), '{}'::uuid[])
    into v_mentioned
    from regexp_matches(
           new.body,
           '@\[[^\]]+\]\(([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\)',
           'g'
         ) as m(groups)
    join public.workspace_members wm
      on wm.user_id = (m.groups)[1]::uuid
     and wm.workspace_id = v_workspace
   where (m.groups)[1]::uuid is distinct from new.author_id;

  if array_length(v_mentioned, 1) > 0 then
    insert into public.notifications
      (user_id, workspace_id, project_id, issue_id, actor_id, type, title, body, payload)
    select u, v_workspace, v_project, new.issue_id, new.author_id, 'mentioned',
           'You were mentioned on ' || v_key, left(new.body, 280),
           jsonb_build_object('issue_key', v_key, 'comment_id', new.id)
      from unnest(v_mentioned) as u;
  end if;

  insert into public.notifications
    (user_id, workspace_id, project_id, issue_id, actor_id, type, title, body, payload)
  select w.user_id, v_workspace, v_project, new.issue_id, new.author_id, 'commented',
         'New comment on ' || v_key, left(new.body, 280),
         jsonb_build_object('issue_key', v_key, 'comment_id', new.id)
    from public.watchers w
   where w.issue_id = new.issue_id
     and w.user_id is distinct from new.author_id
     and not (w.user_id = any (v_mentioned));

  -- Commenting implies watching.
  if new.author_id is not null then
    insert into public.watchers (issue_id, user_id)
    values (new.issue_id, new.author_id)
    on conflict do nothing;
  end if;

  insert into public.activity_log (issue_id, actor_id, action, field_changed)
  values (new.issue_id, new.author_id, 'commented', 'comment');

  return null;
end;
$$;

drop trigger if exists comments_notify on public.comments;
create trigger comments_notify
  after insert on public.comments
  for each row execute function public.notify_comment();

-- Keep an edit history for comments.
create or replace function public.archive_comment_revision()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.body is distinct from old.body then
    insert into public.comment_revisions (comment_id, body, editor_id)
    values (old.id, old.body, auth.uid());
    new.is_edited := true;
    new.updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists comments_archive_revision on public.comments;
create trigger comments_archive_revision
  before update on public.comments
  for each row execute function public.archive_comment_revision();

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'profiles', 'workspaces', 'projects', 'issues', 'sprints', 'saved_filters'
  ]
  loop
    execute format('drop trigger if exists set_updated_at on public.%I', t);
    execute format(
      'create trigger set_updated_at before update on public.%I
         for each row execute function public.set_updated_at()', t
    );
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- RPC: project creation with a default workflow
-- ---------------------------------------------------------------------------
create or replace function public.create_project(
  p_workspace   uuid,
  p_name        text,
  p_key         text,
  p_description text default null,
  p_lead        uuid default null,
  p_icon        text default 'Rocket',
  p_color       text default '#5B5BD6'
)
returns public.projects
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_project public.projects;
begin
  insert into public.projects (workspace_id, name, key, description, lead_id, icon, color)
  values (
    p_workspace, p_name, upper(p_key), p_description,
    coalesce(p_lead, auth.uid()), p_icon, p_color
  )
  returning * into v_project;

  insert into public.project_statuses (project_id, name, category, color, position)
  values
    (v_project.id, 'To Do',       'todo',        '#64748B', 0),
    (v_project.id, 'In Progress', 'in_progress', '#2563EB', 1),
    (v_project.id, 'In Review',   'in_progress', '#A855F7', 2),
    (v_project.id, 'Done',        'done',        '#059669', 3);

  insert into public.labels (project_id, name, color)
  values
    (v_project.id, 'frontend',  '#2563EB'),
    (v_project.id, 'backend',   '#7C3AED'),
    (v_project.id, 'design',    '#DB2777'),
    (v_project.id, 'tech-debt', '#D97706');

  return v_project;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: sprint lifecycle
-- ---------------------------------------------------------------------------
create or replace function public.start_sprint(
  p_sprint uuid,
  p_start  timestamptz default now(),
  p_end    timestamptz default null
)
returns public.sprints
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_sprint public.sprints;
  v_points numeric;
begin
  select coalesce(sum(i.story_points), 0) into v_points
    from public.issues i where i.sprint_id = p_sprint;

  update public.sprints
     set status = 'active',
         start_date = p_start,
         end_date = coalesce(p_end, end_date, p_start + interval '14 days'),
         committed_points = v_points
   where id = p_sprint
  returning * into v_sprint;

  if v_sprint.id is null then
    raise exception 'Sprint not found or not permitted';
  end if;

  insert into public.notifications
    (user_id, workspace_id, project_id, actor_id, type, title, body, payload)
  select m.user_id, p.workspace_id, p.id, auth.uid(), 'sprint_started',
         v_sprint.name || ' started', v_sprint.goal,
         jsonb_build_object('sprint_id', v_sprint.id, 'project_key', p.key)
    from public.projects p
    join public.workspace_members m on m.workspace_id = p.workspace_id
   where p.id = v_sprint.project_id
     and m.user_id is distinct from auth.uid();

  return v_sprint;
end;
$$;

create or replace function public.complete_sprint(
  p_sprint        uuid,
  p_target_sprint uuid default null
)
returns public.sprints
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_sprint public.sprints;
  v_completed numeric;
begin
  select coalesce(sum(i.story_points), 0) into v_completed
    from public.issues i
    join public.project_statuses s on s.id = i.status_id
   where i.sprint_id = p_sprint
     and s.category = 'done';

  -- Unfinished work rolls into the next sprint, or back to the backlog.
  update public.issues i
     set sprint_id = p_target_sprint
   where i.sprint_id = p_sprint
     and i.status_id in (
       select s.id from public.project_statuses s where s.category <> 'done'
     );

  update public.sprints
     set status = 'completed',
         completed_points = v_completed,
         completed_at = now()
   where id = p_sprint
  returning * into v_sprint;

  if v_sprint.id is null then
    raise exception 'Sprint not found or not permitted';
  end if;

  return v_sprint;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: global search across issues, projects and comments
-- ---------------------------------------------------------------------------
create or replace function public.global_search(
  p_workspace uuid,
  p_query     text,
  p_limit     integer default 20
)
returns table (
  kind         text,
  id           uuid,
  project_id   uuid,
  project_key  text,
  project_name text,
  issue_id     uuid,
  issue_number integer,
  title        text,
  snippet      text,
  rank         real
)
language sql
stable
set search_path = public, pg_temp
as $$
  with q as (
    select
      websearch_to_tsquery('english', p_query) as tsq,
      '%' || p_query || '%' as likeq
  )
  (
    -- Issues rank highest: a +1 offset keeps a weak title match above a
    -- strong comment match.
    select 'issue'::text, i.id, p.id, p.key, p.name, i.id, i.issue_number,
           i.title, left(coalesce(i.description, ''), 160),
           (ts_rank(i.search_vector, q.tsq) + 1.0)::real
      from public.issues i
      join public.projects p on p.id = i.project_id
      cross join q
     where p.workspace_id = p_workspace
       and (i.search_vector @@ q.tsq or i.title ilike q.likeq)
     order by 10 desc, i.updated_at desc
     limit p_limit
  )
  union all
  (
    select 'project'::text, p.id, p.id, p.key, p.name, null::uuid, null::integer,
           p.name, left(coalesce(p.description, ''), 160), 0.9::real
      from public.projects p
      cross join q
     where p.workspace_id = p_workspace
       and (p.name ilike q.likeq or p.key ilike q.likeq)
     limit p_limit
  )
  union all
  (
    select 'comment'::text, c.id, p.id, p.key, p.name, i.id, i.issue_number,
           i.title, left(c.body, 160), ts_rank(c.search_vector, q.tsq)::real
      from public.comments c
      join public.issues i on i.id = c.issue_id
      join public.projects p on p.id = i.project_id
      cross join q
     where p.workspace_id = p_workspace
       and (c.search_vector @@ q.tsq or c.body ilike q.likeq)
     order by 10 desc, c.created_at desc
     limit p_limit
  );
$$;

-- ---------------------------------------------------------------------------
-- Lock down the functions a client should never call directly. PostgreSQL
-- grants EXECUTE to PUBLIC by default, and several of these are SECURITY
-- DEFINER. Trigger functions keep working: privileges are checked when the
-- trigger is created, not when it fires.
-- ---------------------------------------------------------------------------
revoke all on function public.handle_new_user() from public;
revoke all on function public.handle_user_update() from public;
revoke all on function public.assign_issue_defaults() from public;
revoke all on function public.handle_issue_status_change() from public;
revoke all on function public.log_issue_activity() from public;
revoke all on function public.sync_issue_watchers() from public;
revoke all on function public.notify_issue_change() from public;
revoke all on function public.notify_comment() from public;
revoke all on function public.archive_comment_revision() from public;
revoke all on function public.set_updated_at() from public;
revoke all on function public.claim_pending_invites(uuid, text) from public;

-- ---------------------------------------------------------------------------
-- RPC: notifications
-- ---------------------------------------------------------------------------
create or replace function public.mark_all_notifications_read(p_workspace uuid default null)
returns integer
language sql
set search_path = public, pg_temp
as $$
  with updated as (
    update public.notifications
       set is_read = true
     where user_id = auth.uid()
       and is_read = false
       and (p_workspace is null or workspace_id = p_workspace)
    returning 1
  )
  select count(*)::integer from updated;
$$;

-- ---------------------------------------------------------------------------
-- RPC: invites
-- ---------------------------------------------------------------------------
create or replace function public.claim_pending_invites(p_user uuid, p_email text)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer := 0;
begin
  with claimed as (
    update public.workspace_invites
       set status = 'accepted', accepted_at = now()
     where lower(email) = lower(p_email)
       and status = 'pending'
       and expires_at > now()
    returning workspace_id, role
  ),
  joined as (
    insert into public.workspace_members (workspace_id, user_id, role)
    select workspace_id, p_user, role from claimed
    on conflict (workspace_id, user_id) do nothing
    returning 1
  )
  select count(*)::integer into v_count from joined;

  return v_count;
end;
$$;

create or replace function public.accept_invite(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_invite public.workspace_invites;
  v_email text;
begin
  select email into v_email from public.profiles where id = auth.uid();
  if v_email is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_invite
    from public.workspace_invites
   where token = p_token
     and status = 'pending'
     and expires_at > now();

  if v_invite.id is null then
    raise exception 'This invitation is invalid or has expired';
  end if;

  if lower(v_invite.email) <> lower(v_email) then
    raise exception 'This invitation was issued to a different email address';
  end if;

  insert into public.workspace_members (workspace_id, user_id, role)
  values (v_invite.workspace_id, auth.uid(), v_invite.role)
  on conflict (workspace_id, user_id) do nothing;

  update public.workspace_invites
     set status = 'accepted', accepted_at = now()
   where id = v_invite.id;

  return v_invite.workspace_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: workspace creation (creator becomes admin in one transaction)
-- ---------------------------------------------------------------------------
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


-- >>> 20250101000200_rls.sql --------------------------------------------

-- ===========================================================================
-- MIRA — 03. Row-Level Security
--
-- The rule, in one sentence: a row is visible only if you are a member of the
-- workspace that owns it, and writable only if your role in that workspace
-- allows it.
--
--   admin  — everything, including workspace settings and member management
--   lead   — project settings, workflow, sprints, delete issues
--   member — create/edit issues, comments, attachments
--   viewer — read only
-- ===========================================================================

-- Two more SECURITY DEFINER lookups used by the policies below.
create or replace function public.shares_workspace(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.workspace_members mine
    join public.workspace_members theirs
      on theirs.workspace_id = mine.workspace_id
    where mine.user_id = auth.uid()
      and theirs.user_id = p_user
  );
$$;

create or replace function public.comment_issue(p_comment uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select c.issue_id from public.comments c where c.id = p_comment;
$$;

create or replace function public.auth_email()
returns text
language sql
stable
set search_path = public, pg_temp
as $$
  select coalesce(
    nullif(auth.jwt() ->> 'email', ''),
    (select email from public.profiles where id = auth.uid())
  );
$$;

-- ---------------------------------------------------------------------------
-- Enable RLS everywhere. No table in `public` is left open.
-- ---------------------------------------------------------------------------
alter table public.profiles            enable row level security;
alter table public.workspaces          enable row level security;
alter table public.workspace_members   enable row level security;
alter table public.projects            enable row level security;
alter table public.project_statuses    enable row level security;
alter table public.status_transitions  enable row level security;
alter table public.sprints             enable row level security;
alter table public.issues              enable row level security;
alter table public.labels              enable row level security;
alter table public.issue_labels        enable row level security;
alter table public.comments            enable row level security;
alter table public.comment_revisions   enable row level security;
alter table public.attachments         enable row level security;
alter table public.activity_log        enable row level security;
alter table public.watchers            enable row level security;
alter table public.notifications       enable row level security;
alter table public.saved_filters       enable row level security;
alter table public.workspace_invites   enable row level security;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.shares_workspace(id));

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
  for insert to authenticated
  with check (id = auth.uid());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- workspaces
-- ---------------------------------------------------------------------------
drop policy if exists workspaces_select on public.workspaces;
create policy workspaces_select on public.workspaces
  for select to authenticated
  using (public.is_workspace_member(id));

drop policy if exists workspaces_insert on public.workspaces;
create policy workspaces_insert on public.workspaces
  for insert to authenticated
  with check (owner_id = auth.uid());

drop policy if exists workspaces_update_admin on public.workspaces;
create policy workspaces_update_admin on public.workspaces
  for update to authenticated
  using (public.has_workspace_role(id, array['admin']::public.workspace_role[]))
  with check (public.has_workspace_role(id, array['admin']::public.workspace_role[]));

drop policy if exists workspaces_delete_owner on public.workspaces;
create policy workspaces_delete_owner on public.workspaces
  for delete to authenticated
  using (owner_id = auth.uid());

-- ---------------------------------------------------------------------------
-- workspace_members
-- ---------------------------------------------------------------------------
drop policy if exists workspace_members_select on public.workspace_members;
create policy workspace_members_select on public.workspace_members
  for select to authenticated
  using (public.is_workspace_member(workspace_id));

drop policy if exists workspace_members_insert_admin on public.workspace_members;
create policy workspace_members_insert_admin on public.workspace_members
  for insert to authenticated
  with check (public.has_workspace_role(workspace_id, array['admin']::public.workspace_role[]));

drop policy if exists workspace_members_update_admin on public.workspace_members;
create policy workspace_members_update_admin on public.workspace_members
  for update to authenticated
  using (public.has_workspace_role(workspace_id, array['admin']::public.workspace_role[]))
  with check (public.has_workspace_role(workspace_id, array['admin']::public.workspace_role[]));

-- An admin can remove anyone; anyone can remove themselves (leave workspace).
drop policy if exists workspace_members_delete on public.workspace_members;
create policy workspace_members_delete on public.workspace_members
  for delete to authenticated
  using (
    user_id = auth.uid()
    or public.has_workspace_role(workspace_id, array['admin']::public.workspace_role[])
  );

-- ---------------------------------------------------------------------------
-- projects — create/edit/archive/delete is admin + lead
-- ---------------------------------------------------------------------------
drop policy if exists projects_select on public.projects;
create policy projects_select on public.projects
  for select to authenticated
  using (public.is_workspace_member(workspace_id));

drop policy if exists projects_insert on public.projects;
create policy projects_insert on public.projects
  for insert to authenticated
  with check (
    public.has_workspace_role(workspace_id, array['admin', 'lead']::public.workspace_role[])
  );

drop policy if exists projects_update on public.projects;
create policy projects_update on public.projects
  for update to authenticated
  using (
    public.has_workspace_role(workspace_id, array['admin', 'lead']::public.workspace_role[])
  )
  with check (
    public.has_workspace_role(workspace_id, array['admin', 'lead']::public.workspace_role[])
  );

drop policy if exists projects_delete on public.projects;
create policy projects_delete on public.projects
  for delete to authenticated
  using (
    public.has_workspace_role(workspace_id, array['admin', 'lead']::public.workspace_role[])
  );

-- ---------------------------------------------------------------------------
-- project_statuses & status_transitions — the workflow, owned by leads
-- ---------------------------------------------------------------------------
drop policy if exists project_statuses_select on public.project_statuses;
create policy project_statuses_select on public.project_statuses
  for select to authenticated
  using (public.can_read_project(project_id));

drop policy if exists project_statuses_write on public.project_statuses;
create policy project_statuses_write on public.project_statuses
  for all to authenticated
  using (public.can_admin_project(project_id))
  with check (public.can_admin_project(project_id));

drop policy if exists status_transitions_select on public.status_transitions;
create policy status_transitions_select on public.status_transitions
  for select to authenticated
  using (public.can_read_project(project_id));

drop policy if exists status_transitions_write on public.status_transitions;
create policy status_transitions_write on public.status_transitions
  for all to authenticated
  using (public.can_admin_project(project_id))
  with check (public.can_admin_project(project_id));

-- ---------------------------------------------------------------------------
-- sprints
-- ---------------------------------------------------------------------------
drop policy if exists sprints_select on public.sprints;
create policy sprints_select on public.sprints
  for select to authenticated
  using (public.can_read_project(project_id));

drop policy if exists sprints_write on public.sprints;
create policy sprints_write on public.sprints
  for all to authenticated
  using (public.can_admin_project(project_id))
  with check (public.can_admin_project(project_id));

-- ---------------------------------------------------------------------------
-- issues
-- ---------------------------------------------------------------------------
drop policy if exists issues_select on public.issues;
create policy issues_select on public.issues
  for select to authenticated
  using (public.can_read_project(project_id));

drop policy if exists issues_insert on public.issues;
create policy issues_insert on public.issues
  for insert to authenticated
  with check (public.can_write_project(project_id));

drop policy if exists issues_update on public.issues;
create policy issues_update on public.issues
  for update to authenticated
  using (public.can_write_project(project_id))
  with check (public.can_write_project(project_id));

-- Leads/admins can delete anything; a member may delete an issue they raised.
drop policy if exists issues_delete on public.issues;
create policy issues_delete on public.issues
  for delete to authenticated
  using (
    public.can_admin_project(project_id)
    or (public.can_write_project(project_id) and reporter_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- labels
-- ---------------------------------------------------------------------------
drop policy if exists labels_select on public.labels;
create policy labels_select on public.labels
  for select to authenticated
  using (public.can_read_project(project_id));

drop policy if exists labels_insert on public.labels;
create policy labels_insert on public.labels
  for insert to authenticated
  with check (public.can_write_project(project_id));

drop policy if exists labels_update on public.labels;
create policy labels_update on public.labels
  for update to authenticated
  using (public.can_admin_project(project_id))
  with check (public.can_admin_project(project_id));

drop policy if exists labels_delete on public.labels;
create policy labels_delete on public.labels
  for delete to authenticated
  using (public.can_admin_project(project_id));

-- ---------------------------------------------------------------------------
-- issue_labels
-- ---------------------------------------------------------------------------
drop policy if exists issue_labels_select on public.issue_labels;
create policy issue_labels_select on public.issue_labels
  for select to authenticated
  using (public.can_read_issue(issue_id));

drop policy if exists issue_labels_write on public.issue_labels;
create policy issue_labels_write on public.issue_labels
  for all to authenticated
  using (public.can_write_issue(issue_id))
  with check (public.can_write_issue(issue_id));

-- ---------------------------------------------------------------------------
-- comments — authors own their words
-- ---------------------------------------------------------------------------
drop policy if exists comments_select on public.comments;
create policy comments_select on public.comments
  for select to authenticated
  using (public.can_read_issue(issue_id));

drop policy if exists comments_insert on public.comments;
create policy comments_insert on public.comments
  for insert to authenticated
  with check (author_id = auth.uid() and public.can_write_issue(issue_id));

drop policy if exists comments_update_own on public.comments;
create policy comments_update_own on public.comments
  for update to authenticated
  using (author_id = auth.uid())
  with check (author_id = auth.uid());

drop policy if exists comments_delete on public.comments;
create policy comments_delete on public.comments
  for delete to authenticated
  using (
    author_id = auth.uid()
    or public.can_admin_project(public.issue_project(issue_id))
  );

drop policy if exists comment_revisions_select on public.comment_revisions;
create policy comment_revisions_select on public.comment_revisions
  for select to authenticated
  using (public.can_read_issue(public.comment_issue(comment_id)));

-- ---------------------------------------------------------------------------
-- attachments
-- ---------------------------------------------------------------------------
drop policy if exists attachments_select on public.attachments;
create policy attachments_select on public.attachments
  for select to authenticated
  using (public.can_read_issue(issue_id));

drop policy if exists attachments_insert on public.attachments;
create policy attachments_insert on public.attachments
  for insert to authenticated
  with check (uploaded_by = auth.uid() and public.can_write_issue(issue_id));

drop policy if exists attachments_delete on public.attachments;
create policy attachments_delete on public.attachments
  for delete to authenticated
  using (
    uploaded_by = auth.uid()
    or public.can_admin_project(public.issue_project(issue_id))
  );

-- ---------------------------------------------------------------------------
-- activity_log — readable, append-only, written by triggers only
-- ---------------------------------------------------------------------------
drop policy if exists activity_log_select on public.activity_log;
create policy activity_log_select on public.activity_log
  for select to authenticated
  using (public.can_read_issue(issue_id));

-- ---------------------------------------------------------------------------
-- watchers
-- ---------------------------------------------------------------------------
drop policy if exists watchers_select on public.watchers;
create policy watchers_select on public.watchers
  for select to authenticated
  using (public.can_read_issue(issue_id));

drop policy if exists watchers_insert_self on public.watchers;
create policy watchers_insert_self on public.watchers
  for insert to authenticated
  with check (user_id = auth.uid() and public.can_read_issue(issue_id));

drop policy if exists watchers_delete_self on public.watchers;
create policy watchers_delete_self on public.watchers
  for delete to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- notifications — strictly personal. Rows are created by triggers.
-- ---------------------------------------------------------------------------
drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own on public.notifications
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists notifications_delete_own on public.notifications;
create policy notifications_delete_own on public.notifications
  for delete to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- saved_filters
-- ---------------------------------------------------------------------------
drop policy if exists saved_filters_select on public.saved_filters;
create policy saved_filters_select on public.saved_filters
  for select to authenticated
  using (
    owner_id = auth.uid()
    or (is_shared and public.is_workspace_member(workspace_id))
  );

drop policy if exists saved_filters_insert on public.saved_filters;
create policy saved_filters_insert on public.saved_filters
  for insert to authenticated
  with check (owner_id = auth.uid() and public.is_workspace_member(workspace_id));

drop policy if exists saved_filters_update_own on public.saved_filters;
create policy saved_filters_update_own on public.saved_filters
  for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists saved_filters_delete_own on public.saved_filters;
create policy saved_filters_delete_own on public.saved_filters
  for delete to authenticated
  using (owner_id = auth.uid());

-- ---------------------------------------------------------------------------
-- workspace_invites — managed by admins/leads, visible to the invitee
-- ---------------------------------------------------------------------------
drop policy if exists workspace_invites_select on public.workspace_invites;
create policy workspace_invites_select on public.workspace_invites
  for select to authenticated
  using (
    public.has_workspace_role(workspace_id, array['admin', 'lead']::public.workspace_role[])
    or lower(email) = lower(coalesce(public.auth_email(), ''))
  );

drop policy if exists workspace_invites_insert on public.workspace_invites;
create policy workspace_invites_insert on public.workspace_invites
  for insert to authenticated
  with check (
    public.has_workspace_role(workspace_id, array['admin', 'lead']::public.workspace_role[])
  );

drop policy if exists workspace_invites_update on public.workspace_invites;
create policy workspace_invites_update on public.workspace_invites
  for update to authenticated
  using (
    public.has_workspace_role(workspace_id, array['admin', 'lead']::public.workspace_role[])
  )
  with check (
    public.has_workspace_role(workspace_id, array['admin', 'lead']::public.workspace_role[])
  );

drop policy if exists workspace_invites_delete on public.workspace_invites;
create policy workspace_invites_delete on public.workspace_invites
  for delete to authenticated
  using (
    public.has_workspace_role(workspace_id, array['admin', 'lead']::public.workspace_role[])
  );

-- ---------------------------------------------------------------------------
-- Grants. RLS decides row visibility; these grants decide table visibility.
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;

grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

-- The append-only tables are never written directly by a client; triggers
-- (SECURITY DEFINER, owned by the database owner) populate them.
revoke insert, update, delete on public.activity_log from authenticated;
revoke insert, update, delete on public.comment_revisions from authenticated;
revoke insert on public.notifications from authenticated;

-- `anon` gets nothing: every MIRA page requires a session.
revoke all on all tables in schema public from anon;


-- >>> 20250101000300_storage_realtime.sql -------------------------------

-- ===========================================================================
-- MIRA — 04. Storage buckets & Realtime publication
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Buckets
--   attachments  private, path = {project_id}/{issue_id}/{uuid}-{filename}
--   avatars      public,  path = {user_id}/{filename}
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 26214400, null)
on conflict (id) do update
  set public = false,
      file_size_limit = 26214400;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars', 'avatars', true, 2097152,
  array['image/png', 'image/jpeg', 'image/webp', 'image/gif', 'image/svg+xml']
)
on conflict (id) do update
  set public = true,
      file_size_limit = 2097152;

-- Parse the leading path segment as a project id without ever raising on a
-- malformed object name (a cast failure inside a policy aborts the request).
create or replace function public.storage_path_project(p_name text)
returns uuid
language sql
immutable
set search_path = public, pg_temp
as $$
  select case
    when split_part(p_name, '/', 1) ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    then split_part(p_name, '/', 1)::uuid
  end;
$$;

-- --- attachments -----------------------------------------------------------
drop policy if exists "MIRA attachments read" on storage.objects;
create policy "MIRA attachments read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'attachments'
    and public.can_read_project(public.storage_path_project(name))
  );

-- Membership of the owning project is the whole test here. `storage.objects.owner`
-- is deliberately not consulted: it is populated by the Storage API rather
-- than by the client, and has changed shape across versions. The
-- `public.attachments` row policy is what restricts deletion to the uploader
-- or a project lead.
drop policy if exists "MIRA attachments insert" on storage.objects;
create policy "MIRA attachments insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'attachments'
    and public.can_write_project(public.storage_path_project(name))
  );

drop policy if exists "MIRA attachments delete" on storage.objects;
create policy "MIRA attachments delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'attachments'
    and public.can_write_project(public.storage_path_project(name))
  );

-- --- avatars ---------------------------------------------------------------
drop policy if exists "MIRA avatars read" on storage.objects;
create policy "MIRA avatars read" on storage.objects
  for select to public
  using (bucket_id = 'avatars');

drop policy if exists "MIRA avatars write own" on storage.objects;
create policy "MIRA avatars write own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and split_part(name, '/', 1) = auth.uid()::text
  );

drop policy if exists "MIRA avatars update own" on storage.objects;
create policy "MIRA avatars update own" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and split_part(name, '/', 1) = auth.uid()::text)
  with check (bucket_id = 'avatars' and split_part(name, '/', 1) = auth.uid()::text);

drop policy if exists "MIRA avatars delete own" on storage.objects;
create policy "MIRA avatars delete own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and split_part(name, '/', 1) = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- Realtime — boards, issue detail and the notification bell all subscribe to
-- postgres_changes. RLS is still applied per subscriber.
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'issues', 'comments', 'notifications', 'activity_log',
    'sprints', 'project_statuses', 'issue_labels', 'attachments'
  ]
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception
      when duplicate_object then null;
      when undefined_object then
        raise notice 'MIRA: publication supabase_realtime not found, skipping %', t;
    end;
  end loop;
end $$;

-- DELETE events must carry enough of the old row for client-side filters
-- (e.g. `project_id=eq.<id>`) to match.
alter table public.issues replica identity full;
alter table public.comments replica identity full;
alter table public.issue_labels replica identity full;


-- >>> 20250101000400_seed_demo.sql --------------------------------------

-- ===========================================================================
-- MIRA — 05. Demo seed
--
-- `bootstrap_demo_workspace` is called by the auth.users insert trigger, so
-- every new account lands in a populated workspace instead of an empty shell.
-- It is SECURITY DEFINER (it runs with no auth.uid()) and a no-op for users
-- who already belong to a workspace.
-- ===========================================================================

create or replace function public.bootstrap_demo_workspace(
  p_user uuid,
  p_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_workspace uuid;
  v_slug      text;
  v_project   uuid;
  v_design    uuid;
  v_todo      uuid;
  v_progress  uuid;
  v_review    uuid;
  v_done      uuid;
  v_d_todo    uuid;
  v_d_done    uuid;
  v_sprint_1  uuid;
  v_sprint_2  uuid;
  v_sprint_3  uuid;
  v_epic_auth uuid;
  v_epic_board uuid;
  v_epic_mobile uuid;
  v_label_fe  uuid;
  v_label_be  uuid;
  v_label_ux  uuid;
  v_label_debt uuid;
  v_parent    uuid;
  v_display   text;
begin
  -- Already onboarded? Leave everything alone.
  if exists (select 1 from public.workspace_members m where m.user_id = p_user) then
    return null;
  end if;

  v_display := coalesce(nullif(trim(p_name), ''), 'My');
  v_slug := public.slugify(v_display) || '-' || substr(replace(p_user::text, '-', ''), 1, 6);

  insert into public.workspaces (name, slug, description, owner_id)
  values (
    v_display || '''s Team',
    v_slug,
    'Demo workspace created with your account — rename it or start a fresh one any time.',
    p_user
  )
  returning id into v_workspace;

  insert into public.workspace_members (workspace_id, user_id, role)
  values (v_workspace, p_user, 'admin');

  -- ---------------------------------------------------------------------
  -- Project 1 — MIRA Platform
  -- ---------------------------------------------------------------------
  insert into public.projects (workspace_id, name, key, description, lead_id, icon, color)
  values (
    v_workspace, 'MIRA Platform', 'MIRA',
    'The product itself: boards, backlog, sprints and reporting.',
    p_user, 'Rocket', '#5B5BD6'
  )
  returning id into v_project;

  insert into public.project_statuses (project_id, name, category, color, position, wip_limit)
  values (v_project, 'To Do', 'todo', '#64748B', 0, null)
  returning id into v_todo;
  insert into public.project_statuses (project_id, name, category, color, position, wip_limit)
  values (v_project, 'In Progress', 'in_progress', '#2563EB', 1, 4)
  returning id into v_progress;
  insert into public.project_statuses (project_id, name, category, color, position, wip_limit)
  values (v_project, 'In Review', 'in_progress', '#A855F7', 2, 3)
  returning id into v_review;
  insert into public.project_statuses (project_id, name, category, color, position, wip_limit)
  values (v_project, 'Done', 'done', '#059669', 3, null)
  returning id into v_done;

  insert into public.labels (project_id, name, color)
  values (v_project, 'frontend', '#2563EB') returning id into v_label_fe;
  insert into public.labels (project_id, name, color)
  values (v_project, 'backend', '#7C3AED') returning id into v_label_be;
  insert into public.labels (project_id, name, color)
  values (v_project, 'ux', '#DB2777') returning id into v_label_ux;
  insert into public.labels (project_id, name, color)
  values (v_project, 'tech-debt', '#D97706') returning id into v_label_debt;

  -- Sprints: one finished, one running, one being planned.
  insert into public.sprints
    (project_id, name, goal, start_date, end_date, status,
     committed_points, completed_points, completed_at, retrospective)
  values (
    v_project, 'Sprint 1', 'Ship authentication and the project shell.',
    now() - interval '28 days', now() - interval '14 days', 'completed',
    34, 29, now() - interval '14 days',
    E'## What went well\n- Auth landed two days early.\n- Pairing on RLS policies paid off.\n\n## What to improve\n- Estimates on the storage work were optimistic.\n\n## Actions\n- Break anything above 8 points into sub-tasks.'
  )
  returning id into v_sprint_1;

  insert into public.sprints
    (project_id, name, goal, start_date, end_date, status, committed_points)
  values (
    v_project, 'Sprint 2', 'Board, backlog and realtime sync feel instant.',
    now() - interval '6 days', now() + interval '8 days', 'active', 42
  )
  returning id into v_sprint_2;

  insert into public.sprints (project_id, name, goal, status)
  values (v_project, 'Sprint 3', 'Reporting and notifications.', 'planned')
  returning id into v_sprint_3;

  -- Epics
  insert into public.issues
    (project_id, type, title, description, status_id, priority, reporter_id,
     assignee_id, story_points, board_position, backlog_position)
  values (
    v_project, 'epic', 'Accounts & access control',
    'Sign-up, sign-in, OAuth and role-based permissions enforced in the database.',
    v_done, 'high', p_user, p_user, null, 1024, 1024
  )
  returning id into v_epic_auth;

  insert into public.issues
    (project_id, type, title, description, status_id, priority, reporter_id,
     assignee_id, story_points, board_position, backlog_position)
  values (
    v_project, 'epic', 'Board & backlog experience',
    'Drag-and-drop board, ordered backlog, sprint planning and live updates.',
    v_progress, 'highest', p_user, p_user, null, 2048, 2048
  )
  returning id into v_epic_board;

  insert into public.issues
    (project_id, type, title, description, status_id, priority, reporter_id,
     assignee_id, story_points, board_position, backlog_position)
  values (
    v_project, 'epic', 'Mobile & offline polish',
    'Everything works one-handed on a phone.',
    v_todo, 'medium', p_user, p_user, null, 3072, 3072
  )
  returning id into v_epic_mobile;

  -- Sprint 1 (completed) — resolved dates spread across the sprint so the
  -- burndown chart has a realistic shape.
  insert into public.issues
    (project_id, type, title, description, status_id, priority, reporter_id,
     assignee_id, epic_id, sprint_id, story_points, resolved_at,
     board_position, backlog_position)
  values
    (v_project, 'story', 'Email + password sign-up with confirmation',
     'New users can register, confirm their address and land in a seeded workspace.',
     v_done, 'high', p_user, p_user, v_epic_auth, v_sprint_1, 8,
     now() - interval '25 days', 4096, 4096),
    (v_project, 'story', 'Google OAuth sign-in',
     'Single click sign-in via Google, reusing the same profile record.',
     v_done, 'high', p_user, p_user, v_epic_auth, v_sprint_1, 5,
     now() - interval '22 days', 5120, 5120),
    (v_project, 'task', 'Row-Level Security policies for every table',
     'A row is readable only by members of the owning workspace.',
     v_done, 'highest', p_user, p_user, v_epic_auth, v_sprint_1, 13,
     now() - interval '18 days', 6144, 6144),
    (v_project, 'bug', 'Session lost after a hard refresh',
     'Cookies were not being written back from the middleware response.',
     v_done, 'high', p_user, p_user, v_epic_auth, v_sprint_1, 3,
     now() - interval '16 days', 7168, 7168);

  -- Sprint 2 (active)
  insert into public.issues
    (project_id, type, title, description, status_id, priority, reporter_id,
     assignee_id, epic_id, sprint_id, story_points, due_date, resolved_at,
     board_position, backlog_position)
  values
    (v_project, 'story', 'Drag-and-drop across board columns',
     E'Move a card between columns with the mouse, touch, or the keyboard.\n\n**Acceptance criteria**\n- Optimistic update, rolled back on failure\n- Announced to screen readers\n- Works with a horizontal swipe on mobile',
     v_done, 'highest', p_user, p_user, v_epic_board, v_sprint_2, 8,
     (now() - interval '2 days')::date, now() - interval '3 days', 8192, 8192),
    (v_project, 'story', 'Realtime board sync between viewers',
     'Two people looking at the same board see each other''s changes without refreshing.',
     v_review, 'highest', p_user, p_user, v_epic_board, v_sprint_2, 8,
     (now() + interval '3 days')::date, null, 9216, 9216),
    (v_project, 'story', 'Backlog ordering and sprint assignment',
     'Reorder the backlog by dragging, and pull items into the active sprint.',
     v_progress, 'high', p_user, p_user, v_epic_board, v_sprint_2, 5,
     (now() + interval '5 days')::date, null, 10240, 10240),
    (v_project, 'task', 'Quick filters: my issues, unassigned, overdue',
     'One-tap filters on the board toolbar that combine with the saved filters.',
     v_progress, 'medium', p_user, p_user, v_epic_board, v_sprint_2, 3,
     null, null, 11264, 11264),
    (v_project, 'bug', 'Card jumps to the wrong column on a fast drop',
     'Position is recomputed against a stale neighbour list.',
     v_todo, 'high', p_user, null, v_epic_board, v_sprint_2, 2,
     (now() + interval '1 day')::date, null, 12288, 12288),
    (v_project, 'task', 'Keyboard shortcuts: c to create, / to search',
     'Global shortcut layer that never fires while a field has focus.',
     v_todo, 'low', p_user, null, v_epic_board, v_sprint_2, 3,
     null, null, 13312, 13312),
    (v_project, 'story', 'Issue detail: comments, attachments, activity',
     'Everything about one issue on a single screen, with an audit trail.',
     v_review, 'high', p_user, p_user, v_epic_board, v_sprint_2, 8,
     null, null, 14336, 14336),
    (v_project, 'task', 'Loading skeletons for board and backlog',
     'No layout shift between the skeleton and the loaded content.',
     v_todo, 'low', p_user, null, v_epic_board, v_sprint_2, 2,
     null, null, 15360, 15360);

  -- Sub-tasks hang off the realtime story.
  select id into v_parent
    from public.issues
   where project_id = v_project
     and title = 'Realtime board sync between viewers';

  insert into public.issues
    (project_id, type, title, status_id, priority, reporter_id, assignee_id,
     parent_id, epic_id, sprint_id, story_points, board_position, backlog_position)
  values
    (v_project, 'subtask', 'Subscribe to postgres_changes for issues',
     v_done, 'medium', p_user, p_user, v_parent, v_epic_board, v_sprint_2, 2, 16384, 16384),
    (v_project, 'subtask', 'Reconcile realtime events with the query cache',
     v_progress, 'medium', p_user, p_user, v_parent, v_epic_board, v_sprint_2, 3, 17408, 17408);

  -- Backlog (no sprint yet)
  insert into public.issues
    (project_id, type, title, description, status_id, priority, reporter_id,
     assignee_id, epic_id, sprint_id, story_points, board_position, backlog_position)
  values
    (v_project, 'story', 'Burndown and velocity reports',
     'Remaining points per day against the ideal line, plus velocity over the last sprints.',
     v_todo, 'high', p_user, null, v_epic_board, v_sprint_3, 8, 18432, 18432),
    (v_project, 'story', 'In-app notification centre',
     'Assignments, mentions, status changes and comments, marked read per item.',
     v_todo, 'high', p_user, null, v_epic_board, v_sprint_3, 5, 19456, 19456),
    (v_project, 'story', 'Saved filters and a JQL-lite query builder',
     'Compose filters without writing a query language, then save and share them.',
     v_todo, 'medium', p_user, null, null, v_sprint_3, 8, 20480, 20480),
    (v_project, 'story', 'Swipe between board columns on mobile',
     'Columns become a snapping horizontal rail under 768px.',
     v_todo, 'medium', p_user, null, v_epic_mobile, null, 5, 21504, 21504),
    (v_project, 'task', 'Full-screen sheets instead of modals on small screens',
     'Dialogs become bottom sheets that can be dismissed by dragging.',
     v_todo, 'medium', p_user, null, v_epic_mobile, null, 3, 22528, 22528),
    (v_project, 'task', 'CSV export of the current issue list',
     'Export respects the active filters and column order.',
     v_todo, 'low', p_user, null, null, null, 2, 23552, 23552),
    (v_project, 'bug', 'Dark theme: low contrast on the priority chips',
     'Fails WCAG AA at 4.5:1 for the "lowest" chip.',
     v_todo, 'low', p_user, null, v_epic_mobile, null, 1, 24576, 24576),
    (v_project, 'task', 'Replace ad-hoc date formatting with a shared helper',
     'Three components format dates differently today.',
     v_todo, 'lowest', p_user, null, null, null, 2, 25600, 25600);

  -- Labels on a handful of issues
  insert into public.issue_labels (issue_id, label_id)
  select i.id, v_label_fe from public.issues i
   where i.project_id = v_project
     and i.title in (
       'Drag-and-drop across board columns',
       'Loading skeletons for board and backlog',
       'Swipe between board columns on mobile',
       'Dark theme: low contrast on the priority chips'
     )
  on conflict do nothing;

  insert into public.issue_labels (issue_id, label_id)
  select i.id, v_label_be from public.issues i
   where i.project_id = v_project
     and i.title in (
       'Row-Level Security policies for every table',
       'Realtime board sync between viewers',
       'Subscribe to postgres_changes for issues'
     )
  on conflict do nothing;

  insert into public.issue_labels (issue_id, label_id)
  select i.id, v_label_ux from public.issues i
   where i.project_id = v_project
     and i.title in (
       'Full-screen sheets instead of modals on small screens',
       'Issue detail: comments, attachments, activity'
     )
  on conflict do nothing;

  insert into public.issue_labels (issue_id, label_id)
  select i.id, v_label_debt from public.issues i
   where i.project_id = v_project
     and i.title = 'Replace ad-hoc date formatting with a shared helper'
  on conflict do nothing;

  -- A couple of comments so the issue detail view is not empty.
  insert into public.comments (issue_id, author_id, body)
  select i.id, p_user,
         E'Split this into two sub-tasks — the subscription itself and the cache reconciliation. The second one is where the sharp edges are.'
    from public.issues i
   where i.project_id = v_project
     and i.title = 'Realtime board sync between viewers';

  insert into public.comments (issue_id, author_id, body)
  select i.id, p_user,
         E'Reproduced on a 120Hz trackpad: two drop events fire before the first mutation settles.\n\n```\nboard.tsx:142  stale neighbours -> position collision\n```'
    from public.issues i
   where i.project_id = v_project
     and i.title = 'Card jumps to the wrong column on a fast drop';

  -- ---------------------------------------------------------------------
  -- Project 2 — Design System (small, shows multi-project navigation)
  -- ---------------------------------------------------------------------
  insert into public.projects (workspace_id, name, key, description, lead_id, icon, color)
  values (
    v_workspace, 'Design System', 'DES',
    'Tokens, primitives and documentation shared by every surface.',
    p_user, 'Palette', '#DB2777'
  )
  returning id into v_design;

  insert into public.project_statuses (project_id, name, category, color, position)
  values (v_design, 'To Do', 'todo', '#64748B', 0) returning id into v_d_todo;
  insert into public.project_statuses (project_id, name, category, color, position)
  values (v_design, 'In Progress', 'in_progress', '#2563EB', 1);
  insert into public.project_statuses (project_id, name, category, color, position)
  values (v_design, 'Done', 'done', '#059669', 2) returning id into v_d_done;

  insert into public.issues
    (project_id, type, title, description, status_id, priority, reporter_id,
     assignee_id, story_points, board_position, backlog_position)
  values
    (v_design, 'task', 'Colour tokens for light and dark',
     'One semantic scale, verified at AA contrast in both themes.',
     v_d_done, 'high', p_user, p_user, 5, 1024, 1024),
    (v_design, 'task', 'Typography scale',
     'Six sizes, two weights, consistent optical tracking.',
     v_d_todo, 'medium', p_user, null, 3, 2048, 2048),
    (v_design, 'story', 'Document every primitive with usage rules',
     null, v_d_todo, 'low', p_user, null, 8, 3072, 3072);

  -- A saved filter to demonstrate the query builder.
  insert into public.saved_filters (workspace_id, project_id, owner_id, name, query, is_shared)
  values (
    v_workspace, v_project, p_user, 'Open bugs by priority',
    jsonb_build_object(
      'types', jsonb_build_array('bug'),
      'statusCategories', jsonb_build_array('todo', 'in_progress'),
      'sort', 'priority'
    ),
    true
  );

  -- Seeding assigns a lot of issues to the new account, and the triggers
  -- dutifully raise a notification for each. Keep the three most recent unread
  -- so the bell is demonstrably alive without burying the user.
  update public.notifications n
     set is_read = true
   where n.user_id = p_user
     and n.id not in (
       select id
         from public.notifications
        where user_id = p_user
        order by created_at desc
        limit 3
     );

  return v_workspace;
end;
$$;

-- ---------------------------------------------------------------------------
-- Manual seeding helper — useful when you created the account before applying
-- these migrations:
--
--   select public.seed_demo_for_email('you@example.com');
-- ---------------------------------------------------------------------------
create or replace function public.seed_demo_for_email(p_email text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid;
  v_name text;
begin
  select id, full_name into v_user, v_name
    from public.profiles
   where lower(email) = lower(p_email);

  if v_user is null then
    raise exception 'No profile for %. Sign up first, then re-run this.', p_email;
  end if;

  return public.bootstrap_demo_workspace(v_user, v_name);
end;
$$;

-- These two are for the signup trigger and the SQL editor, never for a client.
revoke all on function public.bootstrap_demo_workspace(uuid, text) from public;
revoke all on function public.seed_demo_for_email(text) from public;

-- Backfill profiles for accounts that existed before this schema was applied.
insert into public.profiles (id, email, full_name, avatar_url)
select
  u.id,
  u.email,
  coalesce(
    u.raw_user_meta_data ->> 'full_name',
    u.raw_user_meta_data ->> 'name',
    split_part(u.email, '@', 1)
  ),
  coalesce(
    u.raw_user_meta_data ->> 'avatar_url',
    u.raw_user_meta_data ->> 'picture'
  )
from auth.users u
where u.email is not null
on conflict (id) do nothing;


-- >>> 20260919000100_team_roles_and_cleanup.sql -------------------------

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

