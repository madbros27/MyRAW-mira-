'use client'

/**
 * Holds "who am I and where am I" for the whole dashboard: the signed-in
 * profile, the workspaces they belong to, the active one and their role in it.
 *
 * The initial value is rendered on the server so the shell never flashes an
 * empty sidebar, then kept fresh by React Query.
 */

import * as React from 'react'

import { useProfile, useWorkspaces } from '@/lib/queries/workspaces'
import type { Profile, WorkspaceWithRole } from '@/lib/types/app'
import type { WorkspaceRole } from '@/lib/types/database'

export type WorkspaceContextValue = {
  userId: string
  profile: Profile | null
  workspaces: WorkspaceWithRole[]
  workspace: WorkspaceWithRole | null
  workspaceId: string
  role: WorkspaceRole | undefined
  isLoading: boolean
}

const WorkspaceContext = React.createContext<WorkspaceContextValue | null>(null)

export function WorkspaceProvider({
  userId,
  initialProfile,
  initialWorkspaces,
  activeWorkspaceId,
  children,
}: {
  userId: string
  initialProfile: Profile | null
  initialWorkspaces: WorkspaceWithRole[]
  activeWorkspaceId: string
  children: React.ReactNode
}) {
  const { data: profile, isLoading: profileLoading } = useProfile()
  const { data: workspaces, isLoading: workspacesLoading } = useWorkspaces(userId)

  const value = React.useMemo<WorkspaceContextValue>(() => {
    const list = workspaces?.length ? workspaces : initialWorkspaces
    const workspace =
      list.find((item) => item.id === activeWorkspaceId) ?? list[0] ?? null

    return {
      userId,
      profile: profile ?? initialProfile,
      workspaces: list,
      workspace,
      workspaceId: workspace?.id ?? activeWorkspaceId,
      role: workspace?.role,
      isLoading: profileLoading || workspacesLoading,
    }
  }, [
    activeWorkspaceId,
    initialProfile,
    initialWorkspaces,
    profile,
    profileLoading,
    userId,
    workspaces,
    workspacesLoading,
  ])

  return <WorkspaceContext.Provider value={value}>{children}</WorkspaceContext.Provider>
}

export function useWorkspaceContext() {
  const context = React.useContext(WorkspaceContext)
  if (!context) {
    throw new Error('useWorkspaceContext must be used inside <WorkspaceProvider>')
  }
  return context
}

/** Convenience: the bits almost every component needs. */
export function useCurrentUser() {
  const { userId, profile, role } = useWorkspaceContext()
  return { userId, profile, role }
}
