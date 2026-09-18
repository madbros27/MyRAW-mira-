# MIRA

A project and issue tracker in the spirit of JIRA — boards, backlogs, sprints,
reports and notifications — built on **Next.js (App Router)** and **Supabase**.

Permissions are enforced by Postgres row-level security rather than by the
interface, drag-and-drop is optimistic, boards update live for everyone looking
at them, and every screen is designed for a phone as carefully as for a desk.

---

## Contents

- [Feature list](#feature-list)
- [Tech stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Setup, step by step](#setup-step-by-step)
- [Running locally](#running-locally)
- [Building for production](#building-for-production)
- [Deployment](#deployment)
- [Project structure](#project-structure)
- [Data model](#data-model)
- [Permissions](#permissions)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Design system](#design-system)
- [Troubleshooting](#troubleshooting)
- [Scripts](#scripts)

---

## Feature list

### Workspaces and projects
- Multi-tenant workspaces: each one has its own members, projects and roles
- Switch workspaces from the sidebar; the choice is remembered in a cookie
- Projects with a unique key per workspace (`MIRA`, `DES`) used as the issue
  prefix — `MIRA-101` — numbered by an atomic per-project counter
- Project settings: name, key, description, lead, icon, colour, archive/delete
- Invite teammates by email with a role; invitations are matched on first
  sign-in, so an invited person lands straight in the workspace

### Issues
- Types: **Epic**, **Story**, **Task**, **Bug**, **Sub-task**
- Fields: title, markdown description, status, priority, assignee, reporter,
  labels, due date, story points, sprint, epic link, parent/sub-tasks
- Full CRUD plus **bulk edit** (status, assignee, sprint, priority, delete) and
  **cloning** (labels included)
- Comments with **@mentions** and a preserved **edit history**
- Attachments in Supabase Storage, served through short-lived signed URLs
- Automatic **activity log** per issue: every field change and comment
- **Watchers**, added automatically when you report, get assigned, or comment

### Boards and workflow
- Kanban board with pointer, touch and keyboard drag-and-drop
- Fractional ranking, so moving a card writes exactly one row
- Columns are configurable per project: add, rename, reorder, recolour, set
  **WIP limits**, and choose the category (to do / in progress / done)
- **Allowed transitions** per status, enforced by a database trigger
- Quick filters (my issues, unassigned, overdue), a one-tap assignee avatar
  row, and a sprint scope selector

### Sprints
- Create, start and complete sprints; only one may be active per project
- Completing a sprint snapshots committed and completed points and rolls
  unfinished work into the next sprint or back to the backlog
- Backlog with drag-to-reorder and drag-between-sprints
- **Burndown** (remaining vs ideal) and **velocity** (committed vs completed)
- Markdown **retrospective notes** per sprint

### Search and filters
- Command palette (`⌘K` / `/`) searching issues, projects and comments through
  a Postgres full-text function
- A "JQL-lite" query builder: type, priority, status, assignee, reporter,
  labels, sprint, epic, due and created date ranges, overdue
- Filters serialise into the URL, so a result set can be shared as a link
- **Saved filters**, private or shared with the workspace

### Reporting
- Workspace home: open/closed counts, done this week, overdue, unassigned,
  per-project progress, workload by assignee, created vs resolved
- Project dashboard: epic progress, active-sprint burn-up, distributions by
  type, status and priority
- CSV export of any filtered list (RFC 4180 quoted, Excel-friendly BOM)

### Users, roles and permissions
- Supabase Auth: email + password, **Google** and **GitHub** OAuth, email
  confirmation, password reset
- Roles — **Admin**, **Project lead**, **Member**, **Viewer** — enforced by RLS
  policies, with the UI mirroring them so nothing is shown that would fail
- Profile page with avatar upload, display name, job title and time zone

### Notifications
- In-app notification centre: assigned, mentioned, status changed, commented,
  sprint started
- Unread badges in the sidebar, top bar and mobile tab bar
- Supabase **Realtime** keeps boards, issue detail and the bell live

### Interface
- Deliberate design system: colour tokens, spacing scale, type scale, layered
  shadows — not default component styling
- Light, dark and "follow the system" themes
- Fully responsive: swipeable snapping board columns, a bottom tab bar, a
  navigation drawer, and dialogs that become full-height sheets under `sm`
- Optimistic updates for drag-and-drop, field edits and comments
- Designed empty, loading (skeleton) and error states everywhere
- Keyboard shortcuts for power users

---

## Tech stack

| Layer | Choice |
| --- | --- |
| Framework | Next.js 15 (App Router) + React 19 + TypeScript (strict) |
| Styling | Tailwind CSS with CSS-variable design tokens |
| Components | Radix UI primitives, wrapped in `components/ui` |
| Server state | TanStack Query v5 |
| Local UI state | Zustand + React context |
| Backend | Supabase — Postgres, Auth, Storage, Realtime, RLS |
| Drag & drop | dnd-kit (pointer, touch and keyboard sensors) |
| Charts | Recharts |
| Rich text | Markdown (`react-markdown` + `remark-gfm`) with a custom composer |
| Command palette | cmdk |
| Toasts | sonner |
| Deployment | Vercel + Supabase Cloud |

---

## Prerequisites

- **Node.js 20 or newer** (built and tested on 20 and 24) — `node --version`
- **npm 10+** (or pnpm/yarn/bun; the lockfile here is npm's)
- A **Supabase account** and a project — <https://supabase.com/dashboard>
- Optional: the **Supabase CLI** for migrations and local development —
  <https://supabase.com/docs/guides/cli>

---

## Setup, step by step

### 1. Clone and install

```bash
git clone <your-fork-url> mira
cd mira
npm install
```

### 2. Create a Supabase project

In the [Supabase dashboard](https://supabase.com/dashboard) create a project,
then open **Project Settings → API** and keep this page open. You need:

| Value | Where it goes |
| --- | --- |
| Project URL | `NEXT_PUBLIC_SUPABASE_URL` |
| `anon` / publishable key | `NEXT_PUBLIC_SUPABASE_ANON_KEY` |
| `service_role` / secret key | `SUPABASE_SERVICE_ROLE_KEY` |

### 3. Create the database

Pick whichever route you prefer — they produce the same result.

**Option A — SQL editor (no CLI).** Open **SQL Editor → New query**, paste the
whole of [`supabase/schema.sql`](supabase/schema.sql), and run it. It creates
the tables, functions, triggers, RLS policies, storage buckets, the Realtime
publication and the demo seed function.

**Option B — Supabase CLI (recommended).**

```bash
npm install -g supabase          # or: brew install supabase/tap/supabase
supabase login
supabase link --project-ref <your-project-ref>
supabase db push
```

`<your-project-ref>` is the subdomain of your project URL —
`https://abcdefghijklmnop.supabase.co` → `abcdefghijklmnop`.

The migrations, applied in order, are:

| File | What it does |
| --- | --- |
| `20250101000000_init.sql` | Extensions, enums, 18 tables, indexes, full-text search columns |
| `20250101000100_functions.sql` | Authorization helpers, issue numbering, activity log, notifications, sprint and search RPCs |
| `20250101000200_rls.sql` | `ENABLE ROW LEVEL SECURITY` and every policy, plus grants |
| `20250101000300_storage_realtime.sql` | `attachments` and `avatars` buckets with policies; Realtime publication |
| `20250101000400_seed_demo.sql` | `bootstrap_demo_workspace()` — the demo workspace, two projects, three sprints and ~30 issues created for each new account |

> `supabase/schema.sql` is generated from these files. After editing a
> migration, run `npm run db:schema` to regenerate it.

### 4. Configure authentication

**Redirect URLs.** In **Authentication → URL Configuration** set:

- *Site URL*: `http://localhost:3000` while developing, your real domain later
- *Redirect URLs*: add `http://localhost:3000/auth/callback` and
  `https://<your-domain>/auth/callback`

**Email + password** works with no further setup. Turn *Confirm email* off in
**Authentication → Providers → Email** if you would rather not confirm while
developing.

**Google OAuth** (at least one social provider is part of the brief):

1. In Google Cloud Console create an **OAuth 2.0 Client ID** of type *Web
   application*.
2. Add the authorised redirect URI shown in the Supabase dashboard —
   `https://<project-ref>.supabase.co/auth/v1/callback`.
3. Paste the client ID and secret into **Authentication → Providers → Google**
   and enable it.

**GitHub OAuth** is wired up too and follows the same pattern; the sign-in
buttons appear regardless and report a clear error if a provider is disabled.

### 5. Set the environment variables

```bash
cp .env.example .env.local        # macOS / Linux
Copy-Item .env.example .env.local # Windows PowerShell
```

Then fill it in:

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://abcdefghijklmnop.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOi...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOi...
NEXT_PUBLIC_SITE_URL=http://localhost:3000
```

- The `anon` key is safe in the browser: every request is still constrained by
  RLS.
- The service-role key **bypasses RLS**. It has no `NEXT_PUBLIC_` prefix, is
  only read in `lib/supabase/server.ts`, and is used for exactly one thing:
  emailing workspace invitations from `app/api/invites/route.ts`.
- Never commit `.env.local` — it is already in `.gitignore`.

### 6. Run it

```bash
npm run dev
```

Open <http://localhost:3000>, create an account, and you land in a workspace
that already has two projects, three sprints and about thirty issues, so the
board, backlog and reports are populated from the first load.

If the environment variables are missing, every route redirects to `/setup`,
which restates these steps and shows which variables it can see.

---

## Running locally

```bash
npm run dev         # http://localhost:3000
npm run typecheck   # tsc --noEmit
npm run lint        # next lint
```

### Against a local Supabase stack (optional)

```bash
supabase start      # needs Docker
```

`supabase start` prints a local API URL and keys — put those in `.env.local`
instead of the hosted ones. Emails (confirmations, invites) are caught by
Inbucket at <http://localhost:54324>. `supabase/config.toml` disables email
confirmation locally so signing up is one step.

```bash
npm run db:reset    # re-apply every migration to the local database
```

---

## Building for production

```bash
npm run build
npm run start       # serves the production build on :3000
```

`npm run build` runs ESLint and a full TypeScript check, so a clean build means
a clean typecheck.

---

## Deployment

### Frontend on Vercel

1. Push the repository to GitHub, GitLab or Bitbucket.
2. In Vercel choose **Add New → Project** and import it. The framework is
   detected automatically; no build settings need changing.
3. Add the environment variables under **Settings → Environment Variables**,
   for Production *and* Preview:

   | Name | Value | Exposed to the browser |
   | --- | --- | --- |
   | `NEXT_PUBLIC_SUPABASE_URL` | your project URL | yes |
   | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | your `anon` key | yes |
   | `SUPABASE_SERVICE_ROLE_KEY` | your `service_role` key | **no** |
   | `NEXT_PUBLIC_SITE_URL` | `https://your-domain.com` | yes |

   Leave `NEXT_PUBLIC_SITE_URL` unset on preview deployments and MIRA falls
   back to `VERCEL_URL`, so preview builds get working auth redirects.
4. Deploy, then go back to Supabase → **Authentication → URL Configuration**
   and add `https://your-domain.com/auth/callback` (plus
   `https://*-your-team.vercel.app/auth/callback` for previews) to the redirect
   allow-list. Set the *Site URL* to your production domain.

The same Supabase project backs local development, previews and production —
nothing about the connection is baked into the build.

### Backend on Supabase Cloud

The database *is* the deployment: apply migrations with `supabase db push`
(ideally from CI on merge to `main`). Nothing else needs to run server-side —
MIRA has no separate API service.

A minimal GitHub Actions step:

```yaml
- uses: supabase/setup-cli@v1
- run: supabase link --project-ref ${{ secrets.SUPABASE_PROJECT_REF }}
  env:
    SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
- run: supabase db push
  env:
    SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
```

---

## Project structure

```
mira/
├── app/
│   ├── (auth)/                     # login, signup, forgot/reset password
│   ├── (dashboard)/                # everything behind the auth wall
│   │   ├── layout.tsx              # session + workspace resolution (server)
│   │   ├── page.tsx                # workspace home
│   │   ├── my-work/
│   │   ├── projects/
│   │   │   └── [key]/              # overview · board · backlog · reports · settings
│   │   ├── issues/[key]/           # /issues/MIRA-101
│   │   ├── search/
│   │   ├── notifications/
│   │   └── settings/               # profile · members · workspace
│   ├── api/invites/                # service-role invite emails
│   ├── auth/callback|signout/      # OAuth + email link handling
│   ├── invite/[token]/             # accept an invitation
│   ├── setup/                      # shown when env vars are missing
│   ├── actions.ts                  # server actions
│   ├── layout.tsx · error.tsx · not-found.tsx · icon.svg
├── components/
│   ├── ui/                         # design-system primitives (Radix wrappers)
│   ├── layout/                     # shell, sidebar, top bar, mobile nav, theme
│   ├── issues/                     # cards, rows, detail, pickers, dialogs
│   ├── board/                      # Kanban board and columns
│   ├── backlog/                    # backlog sections and bulk actions
│   ├── sprints/                    # sprint lifecycle dialogs
│   ├── filters/                    # query builder and filter bar
│   ├── reports/                    # chart kit, charts, stat tiles
│   ├── notifications/              # bell and list
│   ├── search/                     # command palette
│   ├── projects/                   # project provider, nav, create dialog
│   ├── providers/                  # query client, theme, workspace context
│   └── auth/                       # OAuth buttons
├── lib/
│   ├── supabase/                   # client.ts · server.ts · middleware.ts · env.ts
│   ├── queries/                    # one React Query module per domain
│   ├── types/                      # database.ts (schema) · app.ts (joined shapes)
│   ├── store/                      # Zustand UI store
│   ├── constants.ts · permissions.ts · filters.ts · reports.ts
│   ├── csv.ts · format.ts · mentions.ts · utils.ts
├── supabase/
│   ├── migrations/                 # source of truth
│   ├── schema.sql                  # generated: npm run db:schema
│   └── config.toml                 # local CLI stack
├── styles/globals.css              # design tokens
├── scripts/build-schema.mjs
├── middleware.ts                   # session refresh + route protection
├── tailwind.config.ts · next.config.mjs · tsconfig.json
├── .env.example
└── package.json
```

### How data access is organised

- `lib/supabase/client.ts` — the single browser client (memoised, so one
  Realtime socket is shared)
- `lib/supabase/server.ts` — the server client (RLS applies) and the admin
  client (service role, deliberate use only)
- `lib/queries/*` — every read and write lives in a hook; components never
  build a query themselves

---

## Data model

Eighteen tables. `workspaces` is the tenancy boundary; everything else hangs
off it.

| Table | Purpose |
| --- | --- |
| `profiles` | Public mirror of `auth.users`, kept in sync by a trigger |
| `workspaces` | Tenancy boundary; owner, name, slug |
| `workspace_members` | `(workspace, user) → role` |
| `projects` | Name, key, lead, icon, colour, archive flag, issue counter |
| `project_statuses` | The configurable board columns: name, category, colour, position, WIP limit |
| `status_transitions` | Optional allow-list of moves out of a status |
| `sprints` | Name, goal, window, status, retrospective, committed/completed points |
| `issues` | The core table, including `search_vector` and two ranking columns |
| `labels`, `issue_labels` | Per-project labels and their assignments |
| `comments`, `comment_revisions` | Comments and their edit history |
| `attachments` | Metadata for objects in the `attachments` bucket |
| `activity_log` | Append-only audit trail per issue |
| `watchers` | Who gets notified about an issue |
| `notifications` | Per-user inbox |
| `saved_filters` | Stored query-builder state, private or shared |
| `workspace_invites` | Pending invitations with a token and expiry |

### Two deliberate deviations from the brief's sketch

- **`issues.status_id` instead of `issues.status`.** A text status cannot carry
  a per-project workflow. Statuses are rows in `project_statuses`, which is
  what makes configurable columns, WIP limits, transition rules and the
  to-do/in-progress/done category (used by burndown, velocity and
  `resolved_at`) possible.
- **`board_position` and `backlog_position`** are `double precision` fractional
  ranks. Dropping a card computes a value between its new neighbours, so a
  reorder is a single-row update instead of renumbering a column.

### What the database does for you

Triggers and functions, so the client cannot get it wrong:

- `assign_issue_defaults` — allocates `issue_number` from an atomic per-project
  counter, defaults the reporter, status and both rank columns
- `handle_issue_status_change` — enforces `status_transitions` and maintains
  `resolved_at` from the status category
- `log_issue_activity` — writes an `activity_log` row per changed field
- `notify_issue_change` / `notify_comment` — raise notifications for assignees,
  watchers and anyone `@mentioned`; mentions are parsed server-side from the
  `@[Name](uuid)` markup, so the client cannot fake a recipient
- `sync_issue_watchers` — reporters, assignees and commenters follow issues
- `archive_comment_revision` — snapshots the previous body on every edit
- `handle_new_user` — creates the profile, seeds the demo workspace and claims
  any pending invitations for that email address

RPCs: `create_workspace`, `create_project`, `start_sprint`, `complete_sprint`,
`global_search`, `mark_all_notifications_read`, `accept_invite`,
`seed_demo_for_email`.

### Burndown without snapshot tables

Burndown is computed from each issue's `resolved_at` against the sprint window,
rather than from nightly snapshots. One fewer table, and it stays correct when
an issue is reopened — the status trigger clears `resolved_at`.

---

## Permissions

| Capability | Admin | Project lead | Member | Viewer |
| --- | :-: | :-: | :-: | :-: |
| Read everything in the workspace | ● | ● | ● | ● |
| Create / edit issues, comment, attach | ● | ● | ● | |
| Delete an issue you reported | ● | ● | ● | |
| Delete any issue | ● | ● | | |
| Create / edit / archive / delete projects | ● | ● | | |
| Edit the workflow, labels and sprints | ● | ● | | |
| Invite teammates | ● | ● | | |
| Change roles, remove members | ● | | | |
| Rename the workspace | ● | | | |

Postgres is the boundary. Policies call three `SECURITY DEFINER` helpers —
`is_workspace_member`, `has_workspace_role` and `project_workspace` — which
lets a policy ask "is the caller a member of the workspace that owns this row?"
without recursing into `workspace_members`' own policies.

`lib/permissions.ts` mirrors the same table so the interface never offers an
action the database would refuse. Deleting that file would change what is
*shown*, not what is *allowed*.

Two more things worth knowing:

- `activity_log`, `comment_revisions` and `notifications` have their write
  grants revoked from `authenticated`; only the definer triggers populate them.
- The `attachments` bucket is private. Object paths start with the project id,
  which is what the storage policy checks, and the UI reads files through
  one-hour signed URLs.

### Verifying RLS yourself

```sql
-- As an authenticated user in the SQL editor, impersonate a role:
set local role authenticated;
set local request.jwt.claims = '{"sub":"<some-user-uuid>","role":"authenticated"}';

-- Should only return workspaces that user belongs to:
select id, name from public.workspaces;
```

---

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| `c` | Create issue |
| `/` or `⌘K` / `Ctrl+K` | Command palette and search |
| `g` then `h` / `m` / `n` / `p` / `s` | Home · My work · Notifications · Projects · Search |
| `?` | Shortcut reference |
| `Space` | Pick up / drop the focused board card |
| `Esc` | Close a dialog, or cancel a drag |
| `⌘/Ctrl + Enter` | Submit a comment or description |
| `⌘/Ctrl + B` / `I` | Bold / italic in the markdown composer |

Nothing fires while a field has focus, so typing `c` in a comment is just a
`c`.

---

## Design system

Tokens live in `styles/globals.css` and are surfaced through Tailwind in
`tailwind.config.ts`. Components consume `bg-surface`, `text-muted-foreground`,
`shadow-md` and so on — no component hardcodes a hex value.

- **Brand**: iris (`hsl(245 68% 56%)`), lifted to `hsl(246 88% 68%)` in dark
  mode so it keeps its contrast
- **Neutrals**: a cool, slightly blue-shifted grey ramp, with three surface
  levels (`surface`, `surface-raised`, `surface-sunken`) over a `canvas`
  background
- **Semantics**: success, warning, destructive and info, each with a `-subtle`
  companion for chips and banners
- **Type**: Inter with tightened heading tracking; JetBrains Mono for issue
  keys and code
- **Radius**: a single `--radius` (10px) with derived steps
- **Elevation**: four layered, brand-tinted shadows rather than flat black

Both themes are defined explicitly, dark under `.dark`, and `prefers-reduced-motion`
disables animation.

---

## Troubleshooting

**Everything redirects to `/setup`.**
The environment variables are missing or still contain the `<placeholder>`
text. Next.js reads `.env.local` at boot — restart `npm run dev` after editing
it.

**`Cannot reach Supabase. Check your project URL and network connection.`**
The URL is wrong or the project is paused. It must include the scheme and no
trailing slash: `https://<ref>.supabase.co`. Free projects pause after a week
of inactivity — resume it from the dashboard.

**`Invalid API key` or every query returns 401.**
The `anon` key does not belong to this project (a common copy-paste slip when
you have several). Re-copy both values together from **Project Settings → API**.

**Signing in works but the app says you belong to no workspace.**
The `handle_new_user` trigger did not run — usually because the account existed
before the migrations were applied. Either create a workspace from the screen
you are looking at, or backfill the demo data:

```sql
select public.seed_demo_for_email('you@example.com');
```

**`new row violates row-level security policy` when creating something.**
This is RLS doing its job — your role is too low for that action. Check
**Members & invites**: only admins and leads can create projects, edit
workflows or manage sprints. If you are certain the role is right, confirm the
migrations all applied (`select count(*) from pg_policies where schemaname =
'public';` should be well over thirty).

**`infinite recursion detected in policy for relation "workspace_members"`.**
A policy is querying `workspace_members` directly instead of going through the
`SECURITY DEFINER` helpers. Re-apply `20250101000200_rls.sql`.

**OAuth returns `Unsupported provider` or bounces back to `/login`.**
The provider is not enabled in Supabase, or the redirect URL is not on the
allow-list. Add `<your-origin>/auth/callback` under **Authentication → URL
Configuration** — including the Vercel preview domain if that is where you are
testing.

**The confirmation or reset email never arrives.**
Supabase's built-in SMTP is rate-limited and easy to exhaust. Configure your
own SMTP under **Project Settings → Auth**, or disable email confirmation while
developing. Locally, read the mail at <http://localhost:54324>.

**Invitations are created but not emailed.**
`inviteUserByEmail` needs the service-role key and only works for addresses
without an account. MIRA treats a failure as non-fatal and shows a copyable
invite link instead — sharing that link works identically.

**The board does not update when someone else moves a card.**
Realtime needs the tables in the `supabase_realtime` publication; that is what
`20250101000300_storage_realtime.sql` does. Check
**Database → Replication** in the dashboard, and remember Realtime also applies
RLS — you only receive events for rows you are allowed to read.

**Attachment downloads 400 or the preview is blank.**
Signed URLs last an hour. Reload the issue to mint fresh ones. If uploads fail
with a storage policy error, confirm the `attachments` bucket exists and is
**private**, and that the object path starts with the project id.

**`aggregate functions are not allowed` in the console.**
PostgREST aggregates power the comment-count badge. MIRA detects the rejection
and refetches without it, so the board still works — the badge just disappears.
Enable aggregates in **Settings → API** to get it back.

**A column will not delete.**
`project_statuses` is referenced by `issues` with `on delete restrict`. Move
every issue out of the column first.

---

## Scripts

| Script | What it does |
| --- | --- |
| `npm run dev` | Development server on :3000 |
| `npm run build` | Production build (runs lint + typecheck) |
| `npm run start` | Serve the production build |
| `npm run lint` | ESLint |
| `npm run typecheck` | `tsc --noEmit` |
| `npm run db:push` | Apply migrations to the linked Supabase project |
| `npm run db:reset` | Re-apply every migration to the local stack |
| `npm run db:schema` | Regenerate `supabase/schema.sql` from the migrations |
| `npm run db:types` | Regenerate `lib/types/database.ts` from the linked project |

---

## License

MIT.
