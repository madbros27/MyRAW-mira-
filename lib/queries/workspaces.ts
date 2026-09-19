'use client'

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import { qk } from './keys'
import { MEMBER_SELECT, unwrap, useSupabase } from './shared'
import type {
  Member,
  Profile,
  Workspace,
  WorkspaceWithRole,
} from '@/lib/types/app'
import type { WorkspaceRole } from '@/lib/types/database'

/* -------------------------------------------------------------------------- */
/* Profile                                                                    */
/* -------------------------------------------------------------------------- */

export function useProfile() {
  const supabase = useSupabase()
  return useQuery({
    queryKey: qk.profile,
    queryFn: async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) return null
      const result = await supabase.from('profiles').select('*').eq('id', user.id).single()
      return unwrap(result) as Profile
    },
    staleTime: 60_000,
  })
}

export function useUpdateProfile() {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async (patch: Partial<Profile> & { id: string }) => {
      const { id, ...rest } = patch
      const result = await supabase
        .from('profiles')
        .update(rest)
        .eq('id', id)
        .select('*')
        .single()
      return unwrap(result) as Profile
    },
    onSuccess: (profile) => {
      client.setQueryData(qk.profile, profile)
      client.invalidateQueries({ queryKey: ['members'] })
    },
  })
}

/* -------------------------------------------------------------------------- */
/* Workspaces                                                                 */
/* -------------------------------------------------------------------------- */

export function useWorkspaces(userId?: string) {
  const supabase = useSupabase()
  return useQuery({
    queryKey: qk.workspaces,
    enabled: Boolean(userId),
    queryFn: async () => {
      const result = await supabase
        .from('workspace_members')
        .select('role, workspace:workspaces!workspace_members_workspace_id_fkey(*)')
        .eq('user_id', userId!)
      const rows = unwrap(result) as unknown as {
        role: WorkspaceRole
        workspace: Workspace | null
      }[]
      return rows
        .filter((row) => row.workspace)
        .map((row) => ({ ...(row.workspace as Workspace), role: row.role }))
        .sort((a, b) => a.name.localeCompare(b.name)) as WorkspaceWithRole[]
    },
    staleTime: 60_000,
  })
}

export function useCreateWorkspace() {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async (input: { name: string }) => {
      const result = await supabase.rpc('create_workspace', { p_name: input.name })
      return unwrap(result) as unknown as Workspace
    },
    onSuccess: () => client.invalidateQueries({ queryKey: qk.workspaces }),
  })
}

export function useUpdateWorkspace() {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async ({ id, ...patch }: Partial<Workspace> & { id: string }) => {
      const result = await supabase
        .from('workspaces')
        .update(patch)
        .eq('id', id)
        .select('*')
        .single()
      return unwrap(result) as Workspace
    },
    onSuccess: (workspace) => {
      client.invalidateQueries({ queryKey: qk.workspaces })
      client.invalidateQueries({ queryKey: qk.workspace(workspace.id) })
    },
  })
}

/* -------------------------------------------------------------------------- */
/* Members                                                                    */
/* -------------------------------------------------------------------------- */

export function useMembers(workspaceId?: string) {
  const supabase = useSupabase()
  return useQuery({
    queryKey: qk.members(workspaceId ?? 'none'),
    enabled: Boolean(workspaceId),
    queryFn: async () => {
      const result = await supabase
        .from('workspace_members')
        .select(MEMBER_SELECT)
        .eq('workspace_id', workspaceId!)
      const rows = unwrap(result) as unknown as Member[]
      return rows.sort((a, b) =>
        (a.profile?.full_name ?? a.profile?.email ?? '').localeCompare(
          b.profile?.full_name ?? b.profile?.email ?? ''
        )
      )
    },
    staleTime: 60_000,
  })
}

export function useUpdateMemberRole(workspaceId: string) {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async ({ userId, role }: { userId: string; role: WorkspaceRole }) => {
      const result = await supabase
        .from('workspace_members')
        .update({ role })
        .eq('workspace_id', workspaceId)
        .eq('user_id', userId)
        .select(MEMBER_SELECT)
        .single()
      return unwrap(result) as unknown as Member
    },
    onSuccess: () => client.invalidateQueries({ queryKey: qk.members(workspaceId) }),
  })
}

export function useRemoveMember(workspaceId: string) {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async (userId: string) => {
      const { error } = await supabase
        .from('workspace_members')
        .delete()
        .eq('workspace_id', workspaceId)
        .eq('user_id', userId)
      if (error) throw error
      return userId
    },
    onSuccess: () => client.invalidateQueries({ queryKey: qk.members(workspaceId) }),
  })
}

