import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'

import { AppShell } from '@/components/layout/app-shell'
import { WorkspaceProvider } from '@/components/providers/workspace-provider'
import { createSupabaseServerClient } from '@/lib/supabase/server'
import type { Profile, WorkspaceWithRole } from '@/lib/types/app'
import type { WorkspaceRole, WorkspaceRow } from '@/lib/types/database'
import { ACTIVE_WORKSPACE_COOKIE } from '@/lib/workspace-cookie'

import { NoWorkspace } from './no-workspace'

// Every dashboard route depends on the session cookie and the active-workspace
// cookie, so there is nothing worth prerendering.
export const dynamic = 'force-dynamic'

/**
 * Server-rendered shell. Resolving the session, the profile and the workspace
 * list here means the sidebar is correct on first paint and the client never
 * has to guess which workspace it is in.
 */
export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const supabase = await createSupabaseServerClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [profileResult, membershipResult] = await Promise.all([
    supabase.from('profiles').select('*').eq('id', user.id).maybeSingle(),
    supabase
      .from('workspace_members')
      .select('role, workspace:workspaces!workspace_members_workspace_id_fkey(*)')
      .eq('user_id', user.id),
  ])

  let profile = profileResult.data as Profile | null

  // Self-heal when the auth trigger has not run (for example, the account was
  // created before the migrations were applied).
  if (!profile) {
    const { data } = await supabase
      .from('profiles')
      .upsert(
        {
          id: user.id,
          email: user.email ?? '',
          full_name:
            (user.user_metadata?.full_name as string | undefined) ??
            (user.user_metadata?.name as string | undefined) ??
            user.email?.split('@')[0] ??
            null,
          avatar_url:
            (user.user_metadata?.avatar_url as string | undefined) ??
            (user.user_metadata?.picture as string | undefined) ??
            null,
        },
        { onConflict: 'id' }
      )
      .select('*')
      .maybeSingle()
    profile = (data as Profile | null) ?? null
  }

  const workspaces: WorkspaceWithRole[] = (
    (membershipResult.data ?? []) as unknown as {
      role: WorkspaceRole
      workspace: WorkspaceRow | null
    }[]
  )
    .filter((row) => row.workspace)
    .map((row) => ({ ...(row.workspace as WorkspaceRow), role: row.role }))
    .sort((a, b) => a.name.localeCompare(b.name))

  if (!workspaces.length) {
    return (
      <NoWorkspace
        email={user.email ?? ''}
        userId={user.id}
        profile={profile}
        initialWorkspaces={workspaces}
      >
        {children}
      </NoWorkspace>
    )
  }

  const cookieStore = await cookies()
  const preferred = cookieStore.get(ACTIVE_WORKSPACE_COOKIE)?.value
  const active =
    workspaces.find((workspace) => workspace.id === preferred) ?? workspaces[0]

  return (
    <WorkspaceProvider
      userId={user.id}
      initialProfile={profile}
      initialWorkspaces={workspaces}
      activeWorkspaceId={active.id}
    >
      <AppShell>{children}</AppShell>
    </WorkspaceProvider>
  )
}
