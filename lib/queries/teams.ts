'use client'

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import { qk } from './keys'
import { unwrap, useSupabase } from './shared'
import type { PermissionRow, RoleRow, TeamMemberRole, TeamRow } from '@/lib/types/database'

export function useTeams(workspaceId?: string) {
  const supabase = useSupabase()
  return useQuery({
    queryKey: qk.teams(workspaceId ?? 'none'),
    enabled: Boolean(workspaceId),
    queryFn: async () => {
      const result = await supabase
        .from('teams')
        .select('*')
        .eq('workspace_id', workspaceId!)
        .order('name')
      return unwrap(result) as TeamRow[]
    },
    staleTime: 30_000,
  })
}

export function useTeam(teamId?: string) {
  const supabase = useSupabase()
  return useQuery({
    queryKey: qk.team(teamId ?? 'none'),
    enabled: Boolean(teamId),
    queryFn: async () => {
      const result = await supabase.from('teams').select('*').eq('id', teamId!).single()
      return unwrap(result) as TeamRow
    },
  })
}

export function useCreateTeam(workspaceId: string) {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async ({
      name,
      description,
      createdBy,
    }: {
      name: string
      description?: string | null
      createdBy: string
    }) => {
      const result = await supabase
        .from('teams')
        .insert({
          workspace_id: workspaceId,
          name,
          description: description ?? null,
          created_by: createdBy,
        })
        .select('*')
        .single()
      return unwrap(result) as TeamRow
    },
    onSuccess: () => client.invalidateQueries({ queryKey: qk.teams(workspaceId) }),
  })
}

export function useUpdateTeam(workspaceId: string) {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async ({
      id,
      ...patch
    }: {
      id: string
      name?: string
      description?: string | null
    }) => {
      const result = await supabase
        .from('teams')
        .update(patch)
        .eq('id', id)
        .select('*')
        .single()
      return unwrap(result) as TeamRow
    },
    onSuccess: () => {
      client.invalidateQueries({ queryKey: qk.teams(workspaceId) })
    },
  })
}

export function useDeleteTeam(workspaceId: string) {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async (teamId: string) => {
      const { error } = await supabase.from('teams').delete().eq('id', teamId)
      if (error) throw error
      return teamId
    },
    onSuccess: () => client.invalidateQueries({ queryKey: qk.teams(workspaceId) }),
  })
}

type TeamMemberWithProfile = {
  id: string
  team_id: string
  user_id: string
  role: TeamMemberRole
  created_at: string
  profile: {
    id: string
    email: string
    full_name: string | null
    avatar_url: string | null
  } | null
}

export function useTeamMembers(teamId?: string) {
  const supabase = useSupabase()
  return useQuery({
    queryKey: ['team-members', teamId ?? 'none'],
    enabled: Boolean(teamId),
    queryFn: async () => {
      const result = await supabase
        .from('team_members')
        .select('*, profile:profiles!team_members_user_id_fkey(*)')
        .eq('team_id', teamId!)
        .order('created_at')
      return unwrap(result) as unknown as TeamMemberWithProfile[]
    },
    staleTime: 30_000,
  })
}

export function useAddTeamMember(teamId: string) {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async ({ userId, role }: { userId: string; role: TeamMemberRole }) => {
      const result = await supabase
        .from('team_members')
        .insert({ team_id: teamId, user_id: userId, role })
        .select('*, profile:profiles!team_members_user_id_fkey(*)')
        .single()
      return unwrap(result)
    },
    onSuccess: () => client.invalidateQueries({ queryKey: ['team-members', teamId] }),
  })
}

export function useUpdateTeamMemberRole(teamId: string) {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async ({ memberId, role }: { memberId: string; role: TeamMemberRole }) => {
      const result = await supabase
        .from('team_members')
        .update({ role })
        .eq('id', memberId)
        .select('*, profile:profiles!team_members_user_id_fkey(*)')
        .single()
      return unwrap(result)
    },
    onSuccess: () => client.invalidateQueries({ queryKey: ['team-members', teamId] }),
  })
}

export function useRemoveTeamMember(teamId: string) {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async (memberId: string) => {
      const { error } = await supabase.from('team_members').delete().eq('id', memberId)
      if (error) throw error
      return memberId
    },
    onSuccess: () => client.invalidateQueries({ queryKey: ['team-members', teamId] }),
  })
}

export function useProjectDiscovery(workspaceId?: string, userId?: string) {
  const supabase = useSupabase()
  return useQuery({
    queryKey: ['project-discovery', workspaceId ?? 'none', userId ?? 'none'],
    enabled: Boolean(workspaceId && userId),
    queryFn: async () => {
      const [projectsResult, requestResult, teamMemberResult] = await Promise.all([
        supabase
          .from('projects')
          .select('*, team:teams!projects_team_id_fkey(id,name), lead:profiles!projects_lead_id_fkey(id,full_name,avatar_url,email)')
          .eq('workspace_id', workspaceId!)
          .eq('is_archived', false),
        supabase
          .from('project_join_requests')
          .select('*')
          .eq('user_id', userId!),
        supabase.from('team_members').select('team_id,user_id').eq('user_id', userId!),
      ])

      const projects = unwrap(projectsResult) as unknown as Array<{
        id: string
        workspace_id: string
        team_id: string | null
        name: string
        key: string
        description: string | null
        lead_id: string | null
        icon: string
        color: string
        is_archived: boolean
        issue_counter: number
        team: { id: string; name: string } | null
        lead: { id: string; full_name: string | null; avatar_url: string | null; email: string } | null
      }>

      const requests = unwrap(requestResult) as Array<{
        id: string
        project_id: string
        user_id: string
        status: 'pending' | 'approved' | 'rejected' | 'cancelled'
      }>
      const teamIds = new Set(
        (unwrap(teamMemberResult) as Array<{ team_id: string; user_id: string }>).map((row) => row.team_id)
      )

      return projects.map((project) => ({
        ...project,
        isTeamMember: project.team_id ? teamIds.has(project.team_id) : false,
        joinRequest: requests.find((request) => request.project_id === project.id) ?? null,
      }))
    },
  })
}

export function useProjectJoinRequests(workspaceId?: string) {
  const supabase = useSupabase()
  return useQuery({
    queryKey: qk.projectRequests(workspaceId ?? 'none'),
    enabled: Boolean(workspaceId),
    queryFn: async () => {
      const result = await supabase
        .from('project_join_requests')
        .select(
          '*, project:projects!project_join_requests_project_id_fkey(*), user:profiles!project_join_requests_user_id_fkey(*), reviewer:profiles!project_join_requests_reviewed_by_fkey(*)'
        )
        .in(
          'project_id',
          (
            await supabase
              .from('projects')
              .select('id')
              .eq('workspace_id', workspaceId!)
          ).data?.map((project) => project.id) ?? []
        )
      return unwrap(result) as Array<any>
    },
    staleTime: 30_000,
  })
}

export function useCreateProjectJoinRequest() {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async ({ projectId, userId }: { projectId: string; userId: string }) => {
      const result = await supabase
        .from('project_join_requests')
        .insert({ project_id: projectId, user_id: userId, status: 'pending' })
        .select('*')
        .single()
      return unwrap(result)
    },
    onSuccess: () => {
      client.invalidateQueries({ queryKey: ['project-discovery'] })
      client.invalidateQueries({ queryKey: ['project-requests'] })
    },
  })
}

export function useCancelProjectJoinRequest() {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async ({ requestId }: { requestId: string }) => {
      const result = await supabase
        .from('project_join_requests')
        .update({ status: 'cancelled' })
        .eq('id', requestId)
        .select('*')
        .single()
      return unwrap(result)
    },
    onSuccess: () => {
      client.invalidateQueries({ queryKey: ['project-discovery'] })
      client.invalidateQueries({ queryKey: ['project-requests'] })
    },
  })
}

export function useRespondProjectJoinRequest() {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async ({
      requestId,
      status,
      reviewerId,
    }: {
      requestId: string
      status: 'approved' | 'rejected'
      reviewerId: string
    }) => {
      const result = await supabase
        .from('project_join_requests')
        .update({ status, reviewed_at: new Date().toISOString(), reviewed_by: reviewerId })
        .eq('id', requestId)
        .select('*')
        .single()

      const payload = unwrap(result) as {
        project_id: string
        user_id: string
        status: 'approved' | 'rejected'
      }

      if (payload.status === 'approved') {
        const projectResult = await supabase
          .from('projects')
          .select('team_id')
          .eq('id', payload.project_id)
          .single()
        const project = unwrap(projectResult) as { team_id: string | null }

        if (project.team_id) {
          const existing = await supabase
            .from('team_members')
            .select('id')
            .eq('team_id', project.team_id)
            .eq('user_id', payload.user_id)
            .maybeSingle()

          if (!existing.data) {
            const { error } = await supabase
              .from('team_members')
              .insert({ team_id: project.team_id, user_id: payload.user_id, role: 'member' })
            if (error) throw error
          }
        }
      }

      return payload
    },
    onSuccess: () => {
      client.invalidateQueries({ queryKey: ['project-discovery'] })
      client.invalidateQueries({ queryKey: ['project-requests'] })
      client.invalidateQueries({ queryKey: ['team-members'] })
    },
  })
}

export function usePermissions() {
  const supabase = useSupabase()
  return useQuery({
    queryKey: qk.permissions,
    queryFn: async () => {
      const result = await supabase.from('permissions').select('*').order('name')
      return unwrap(result) as PermissionRow[]
    },
    staleTime: 60_000,
  })
}

export function useRoles(workspaceId?: string) {
  const supabase = useSupabase()
  return useQuery({
    queryKey: qk.roles(workspaceId ?? 'none'),
    enabled: Boolean(workspaceId),
    queryFn: async () => {
      const result = await supabase
        .from('roles')
        .select('*, role_permissions(permission:permissions(*))')
        .eq('workspace_id', workspaceId!)
        .order('name')
      return unwrap(result) as unknown as Array<
        RoleRow & {
          role_permissions?: Array<{ permission: PermissionRow | null }> | null
        }
      >
    },
    staleTime: 30_000,
  })
}

export function useCreateRole(workspaceId: string) {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async ({
      name,
      description,
      createdBy,
    }: {
      name: string
      description?: string | null
      createdBy: string
    }) => {
      const result = await supabase
        .from('roles')
        .insert({
          workspace_id: workspaceId,
          name,
          description: description ?? null,
          is_system: false,
        })
        .select('*')
        .single()
      return unwrap(result) as RoleRow
    },
    onSuccess: () => client.invalidateQueries({ queryKey: qk.roles(workspaceId) }),
  })
}

export function useUpdateRole(workspaceId: string) {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async ({ id, ...patch }: Partial<RoleRow> & { id: string }) => {
      const result = await supabase
        .from('roles')
        .update(patch)
        .eq('id', id)
        .select('*')
        .single()
      return unwrap(result) as RoleRow
    },
    onSuccess: () => client.invalidateQueries({ queryKey: qk.roles(workspaceId) }),
  })
}

export function useDeleteRole(workspaceId: string) {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async (roleId: string) => {
      const { error } = await supabase.from('roles').delete().eq('id', roleId)
      if (error) throw error
      return roleId
    },
    onSuccess: () => client.invalidateQueries({ queryKey: qk.roles(workspaceId) }),
  })
}

export function useSetRolePermissions(roleId: string) {
  const supabase = useSupabase()
  const client = useQueryClient()

  return useMutation({
    mutationFn: async (permissionIds: string[]) => {
      const { error: deleteError } = await supabase
        .from('role_permissions')
        .delete()
        .eq('role_id', roleId)
      if (deleteError) throw deleteError

      if (!permissionIds.length) return [] as string[]

      const { error } = await supabase.from('role_permissions').insert(
        permissionIds.map((permissionId) => ({ role_id: roleId, permission_id: permissionId }))
      )
      if (error) throw error

      return permissionIds
    },
    onSuccess: () => client.invalidateQueries({ queryKey: qk.roles(roleId) })
  })
}
