'use client'

import { ArrowLeft, Plus, Trash2, UserMinus } from 'lucide-react'
import Link from 'next/link'
import * as React from 'react'

import { useWorkspaceContext } from '@/components/providers/workspace-provider'
import { Button } from '@/components/ui/button'
import { Card, EmptyState } from '@/components/ui/primitives'
import { useProjects } from '@/lib/queries/projects'
import {
  useDeleteTeam,
  useTeam,
  useTeamMembers,
  useUpdateTeam,
  useAddTeamMember,
  useUpdateTeamMemberRole,
  useRemoveTeamMember,
} from '@/lib/queries/teams'
import { useMembers } from '@/lib/queries/workspaces'
import { displayName, errorMessage } from '@/lib/utils'

export function TeamDetailClient({ teamId }: { teamId: string }) {
  const { workspaceId } = useWorkspaceContext()
  const { data: team } = useTeam(teamId)
  const { data: members } = useMembers(workspaceId)
  const { data: teamMembers } = useTeamMembers(teamId)
  const { data: projects } = useProjects(workspaceId, true)
  const update = useUpdateTeam(workspaceId)
  const remove = useDeleteTeam(workspaceId)
  const addMember = useAddTeamMember(teamId)
  const updateMemberRole = useUpdateTeamMemberRole(teamId)
  const removeMember = useRemoveTeamMember(teamId)

  const [name, setName] = React.useState(team?.name ?? '')
  const [description, setDescription] = React.useState(team?.description ?? '')
  const [selectedUserId, setSelectedUserId] = React.useState('')
  const [selectedRole, setSelectedRole] = React.useState<'lead' | 'member'>('member')

  React.useEffect(() => {
    if (team) {
      setName(team.name)
      setDescription(team.description ?? '')
    }
  }, [team])

  const teamProjects = (projects ?? []).filter((project: { team_id: string | null }) => project.team_id === teamId)
  const workspaceMembers = (members ?? []).filter(
    (member: { user_id: string }) =>
      !teamMembers?.some((teamMember: { user_id: string }) => teamMember.user_id === member.user_id)
  )

  async function saveTeam() {
    if (!team) return
    try {
      await update.mutateAsync({
        id: team.id,
        name: name.trim(),
        description: description.trim() || null,
      })
    } catch (error) {
      window.alert(errorMessage(error, 'Could not save the team'))
    }
  }

  async function handleAddMember() {
    if (!selectedUserId) return
    try {
      await addMember.mutateAsync({ userId: selectedUserId, role: selectedRole })
      setSelectedUserId('')
      setSelectedRole('member')
    } catch (error) {
      window.alert(errorMessage(error, 'Could not add the member'))
    }
  }

  if (!team) {
    return (
      <EmptyState
        title="Team not found"
        description="This team may be archived or not available in the current workspace."
      />
    )
  }

  return (
    <div className="space-y-4 p-3 sm:p-4">
      <div className="flex items-center justify-between gap-3">
        <Link
          href="/teams"
          className="inline-flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground"
        >
          <ArrowLeft className="size-4" />
          Back to teams
        </Link>
        <Button
          variant="destructive"
          size="sm"
          onClick={async () => {
            try {
              await remove.mutateAsync(team.id)
              window.location.assign('/teams')
            } catch (error) {
              window.alert(errorMessage(error, 'Could not delete the team'))
            }
          }}
        >
          <Trash2 />
          Delete team
        </Button>
      </div>

      <div className="grid gap-4 xl:grid-cols-[360px_minmax(0,1fr)]">
        <Card className="p-4">
          <h1 className="text-xl font-semibold">{team.name}</h1>
          <p className="mt-2 text-sm text-muted-foreground">{team.description || 'No description yet.'}</p>

          <div className="mt-4 space-y-3">
            <div className="space-y-1">
              <label className="text-xs font-medium text-muted-foreground">Name</label>
              <input
                value={name}
                onChange={(event) => setName(event.target.value)}
                className="w-full rounded-lg border border-input bg-surface px-3 py-2 text-sm"
              />
            </div>
            <div className="space-y-1">
              <label className="text-xs font-medium text-muted-foreground">Description</label>
              <textarea
                value={description}
                onChange={(event) => setDescription(event.target.value)}
                className="min-h-24 w-full rounded-lg border border-input bg-surface px-3 py-2 text-sm"
              />
            </div>
            <Button variant="primary" size="sm" onClick={saveTeam} loading={update.isPending}>
              Save changes
            </Button>
          </div>
        </Card>

        <div className="space-y-4">
          <Card className="p-4">
            <h2 className="text-sm font-semibold">Members</h2>
            <div className="mt-3 flex flex-col gap-2 sm:flex-row">
              <select
                value={selectedUserId}
                onChange={(event) => setSelectedUserId(event.target.value)}
                className="flex-1 rounded-lg border border-input bg-surface px-3 py-2 text-sm"
              >
                <option value="">Select member</option>
                {workspaceMembers.map((member: { user_id: string; profile: { full_name?: string | null; email?: string } | null }) => (
                  <option key={member.user_id} value={member.user_id}>
                    {displayName(member.profile)}
                  </option>
                ))}
              </select>
              <select
                value={selectedRole}
                onChange={(event) => setSelectedRole(event.target.value as 'lead' | 'member')}
                className="rounded-lg border border-input bg-surface px-3 py-2 text-sm"
              >
                <option value="member">Member</option>
                <option value="lead">Lead</option>
              </select>
              <Button variant="secondary" size="sm" onClick={handleAddMember} loading={addMember.isPending}>
                <Plus /> Add
              </Button>
            </div>

            <div className="mt-4 space-y-2">
              {(teamMembers ?? []).map(
                (member: {
                  id: string
                  role: 'lead' | 'member'
                  profile: { email?: string | null } | null
                }) => (
                  <div
                    key={member.id}
                    className="flex items-center justify-between gap-2 rounded-lg border border-border bg-surface-raised px-3 py-2"
                  >
                    <div>
                      <p className="text-sm font-medium">{displayName(member.profile)}</p>
                      <p className="text-[11px] text-muted-foreground">{member.profile?.email}</p>
                    </div>
                    <div className="flex items-center gap-2">
                      <select
                        value={member.role}
                        onChange={async (event) => {
                          const nextRole = event.target.value as 'lead' | 'member'
                          try {
                            await updateMemberRole.mutateAsync({ memberId: member.id, role: nextRole })
                          } catch (error) {
                            window.alert(errorMessage(error, 'Could not update member role'))
                          }
                        }}
                        className="rounded-lg border border-input bg-surface px-2 py-1.5 text-xs"
                      >
                        <option value="member">Member</option>
                        <option value="lead">Lead</option>
                      </select>
                      <Button
                        variant="ghost"
                        size="icon-sm"
                        aria-label="Remove member"
                        onClick={async () => {
                          try {
                            await removeMember.mutateAsync(member.id)
                          } catch (error) {
                            window.alert(errorMessage(error, 'Could not remove member'))
                          }
                        }}
                      >
                        <UserMinus className="size-3.5" />
                      </Button>
                    </div>
                  </div>
                )
              )}
            </div>
          </Card>

          <Card className="p-4">
            <h2 className="text-sm font-semibold">Projects</h2>
            <div className="mt-3 space-y-2">
              {teamProjects.length ? (
                teamProjects.map((project: { id: string; name: string; key: string }) => (
                  <div
                    key={project.id}
                    className="rounded-lg border border-border bg-surface-raised px-3 py-2 text-sm"
                  >
                    {project.name} <span className="text-muted-foreground">({project.key})</span>
                  </div>
                ))
              ) : (
                <p className="text-sm text-muted-foreground">
                  No projects are assigned to this team yet.
                </p>
              )}
            </div>
          </Card>
        </div>
      </div>
    </div>
  )
}
