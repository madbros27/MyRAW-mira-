import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'

import { AppShell } from '@/components/layout/app-shell'
import { WorkspaceProvider } from '@/components/providers/workspace-provider'
import { createSupabaseServerClient } from '@/lib/supabase/server'
import type { Profile, WorkspaceWithRole } from '@/lib/types/app'
import type { WorkspaceRole, WorkspaceRow } from '@/lib/types/database'
import { ACTIVE_WORKSPACE_COOKIE } from '@/lib/workspace-cookie'

export const dynamic = 'force-dynamic'

export default async function MadbrosLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const supabase = await createSupabaseServerClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/madbros/login?next=/madbros')

  const [profileResult, membershipResult] = await Promise.all([
    supabase.from('profiles').select('*').eq('id', user.id).maybeSingle(),
    supabase
      .from('workspace_members')
      .select('role, workspace:workspaces!workspace_members_workspace_id_fkey(*)')
      .eq('user_id', user.id),
  ])

  let profile = profileResult.data as Profile | null

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

  if (!profile?.is_system_admin) {
    redirect('/')
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

  const cookieStore = await cookies()
  const preferred = cookieStore.get(ACTIVE_WORKSPACE_COOKIE)?.value
  const active = workspaces.find((workspace) => workspace.id === preferred) ?? workspaces[0] ?? null

  return (
    <WorkspaceProvider
      userId={user.id}
      initialProfile={profile}
      initialWorkspaces={workspaces}
      activeWorkspaceId={active?.id ?? ''}
    >
      <AppShell>{children}</AppShell>
    </WorkspaceProvider>
  )
}
