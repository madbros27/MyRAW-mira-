import { redirect } from 'next/navigation'

import { createSupabaseServerClient } from '@/lib/supabase/server'

export const dynamic = 'force-dynamic'

export default async function AdminPage() {
  const supabase = await createSupabaseServerClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect('/login?next=/admin')
  }

  const { data: adminMemberships } = await supabase
    .from('workspace_members')
    .select('workspace_id, role')
    .eq('user_id', user.id)
    .eq('role', 'admin')

  if (!adminMemberships?.length) {
    redirect('/')
  }

  const workspaceIds = adminMemberships.map((row) => row.workspace_id)

  const [{ count: userCount }, { count: projectCount }, { count: teamCount }, { data: workspaces }] =
    await Promise.all([
      supabase.from('profiles').select('*', { count: 'exact', head: true }),
      supabase.from('projects').select('*', { count: 'exact', head: true }),
      supabase.from('teams').select('*', { count: 'exact', head: true }),
      supabase.from('workspaces').select('id, name').in('id', workspaceIds),
    ])

  const workspaceList = (workspaces ?? []) as { id: string; name: string }[]

  const sections = [
    'Overview',
    'Users',
    'Teams',
    'Projects',
    'Roles & Permissions',
    'Workspace/System settings',
  ]

  return (
    <main className="min-h-dvh bg-canvas p-4 sm:p-6">
      <div className="mx-auto max-w-6xl space-y-6">
        <header className="rounded-2xl border border-border bg-background p-6 shadow-sm">
          <p className="text-xs font-medium uppercase tracking-[0.2em] text-muted-foreground">
            Admin
          </p>
          <div className="mt-3 flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
            <div>
              <h1 className="text-2xl font-semibold">Administration</h1>
              <p className="mt-1 text-sm text-muted-foreground">
                Secure admin access is enforced server-side before this dashboard renders.
              </p>
            </div>
            <div className="rounded-lg border border-border bg-surface-raised px-3 py-2 text-sm text-muted-foreground">
              {workspaceList.length} admin workspace{workspaceList.length === 1 ? '' : 's'}
            </div>
          </div>
        </header>

        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          <StatCard label="Users" value={String(userCount ?? 0)} />
          <StatCard label="Projects" value={String(projectCount ?? 0)} />
          <StatCard label="Teams" value={String(teamCount ?? 0)} />
          <StatCard label="Access" value="Admin" tone="success" />
        </div>

        <nav className="rounded-2xl border border-border bg-background p-4 shadow-sm">
          <div className="flex flex-wrap gap-2">
            {sections.map((section) => (
              <span
                key={section}
                className="rounded-full border border-border bg-surface-raised px-3 py-1.5 text-xs font-medium text-muted-foreground"
              >
                {section}
              </span>
            ))}
          </div>
        </nav>

        <div className="grid gap-4 lg:grid-cols-2">
          <section className="rounded-2xl border border-border bg-background p-5 shadow-sm">
            <h2 className="text-base font-semibold">Overview</h2>
            <ul className="mt-4 space-y-3 text-sm text-muted-foreground">
              <li>• Workspace administration is restricted to users with an authenticated admin role.</li>
              <li>• Team and project discovery are intentionally separate from direct membership requests.</li>
              <li>• New signups create only a profile and require workspace membership to access work.</li>
            </ul>
          </section>

          <section className="rounded-2xl border border-border bg-background p-5 shadow-sm">
            <h2 className="text-base font-semibold">Admin workspaces</h2>
            <div className="mt-4 space-y-2">
              {workspaceList.length ? (
                workspaceList.map((workspace) => (
                  <div
                    key={workspace.id}
                    className="flex items-center justify-between rounded-lg border border-border bg-surface-raised px-3 py-2 text-sm"
                  >
                    <span>{workspace.name}</span>
                    <span className="rounded-full bg-primary-subtle px-2 py-1 text-xs font-medium text-primary-subtle-foreground">
                      Owner/Admin
                    </span>
                  </div>
                ))
              ) : (
                <p className="text-sm text-muted-foreground">No admin workspaces found.</p>
              )}
            </div>
          </section>
        </div>
      </div>
    </main>
  )
}

function StatCard({
  label,
  value,
  tone = 'neutral',
}: {
  label: string
  value: string
  tone?: 'neutral' | 'success'
}) {
  return (
    <div className="rounded-2xl border border-border bg-background p-5 shadow-sm">
      <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
      <p
        className={[
          'mt-3 text-2xl font-semibold',
          tone === 'success' ? 'text-success' : 'text-foreground',
        ].join(' ')}
      >
        {value}
      </p>
    </div>
  )
}
