'use client'

import { Plus, Users } from 'lucide-react'
import Link from 'next/link'
import * as React from 'react'

import { ProjectIcon } from '@/components/layout/project-icon'
import { useWorkspaceContext } from '@/components/providers/workspace-provider'
import { Button } from '@/components/ui/button'
import { Card, EmptyState, Skeleton } from '@/components/ui/primitives'
import { useProjects } from '@/lib/queries/projects'
import { useCreateTeam, useTeams } from '@/lib/queries/teams'
import { useMembers } from '@/lib/queries/workspaces'
import { errorMessage } from '@/lib/utils'

export default function TeamsPage() {
  const { workspaceId, userId, role } = useWorkspaceContext()
  const { data: teams, isLoading } = useTeams(workspaceId)
  const { data: projects } = useProjects(workspaceId)
  const { data: members } = useMembers(workspaceId)
  const createTeam = useCreateTeam(workspaceId)
  const [name, setName] = React.useState('')
  const [description, setDescription] = React.useState('')

  const teamMembersMap = React.useMemo(() => {
    const map = new Map<string, string[]>()
    if (!members) return map
    for (const member of members) {
      map.set(member.user_id, [member.profile?.full_name ?? member.profile?.email ?? ''])
    }
    return map
  }, [members])

  async function handleCreate(event: React.FormEvent) {
    event.preventDefault()
    if (!name.trim()) return
    try {
      await createTeam.mutateAsync({ name: name.trim(), description, createdBy: userId })
      setName('')
      setDescription('')
    } catch (error) {
      const message = errorMessage(error, 'Could not create the team')
      window.alert(message)
    }
  }

  return (
    <div className="space-y-4 p-3 sm:p-4">
      <div className="rounded-2xl border border-border bg-background p-4">
        <div className="flex items-center justify-between gap-3">
          <div>
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Teams</p>
            <h1 className="mt-1 text-xl font-semibold">Team overview</h1>
          </div>
          {role === 'admin' || role === 'lead' ? (
            <Button asChild variant="primary" size="sm">
              <Link href="/teams/new">Create team</Link>
            </Button>
          ) : null}
        </div>
      </div>

      <div className="grid gap-3 lg:grid-cols-[420px_minmax(0,1fr)]">
        <Card className="p-4">
          <h2 className="text-sm font-semibold">Create team</h2>
          <form onSubmit={handleCreate} className="mt-4 space-y-3">
            <div className="space-y-1">
              <label className="text-xs font-medium text-muted-foreground">Name</label>
              <input
                value={name}
                onChange={(event) => setName(event.target.value)}
                className="w-full rounded-lg border border-input bg-surface px-3 py-2 text-sm"
                placeholder="Platform team"
              />
            </div>
            <div className="space-y-1">
              <label className="text-xs font-medium text-muted-foreground">Description</label>
              <textarea
                value={description}
                onChange={(event) => setDescription(event.target.value)}
                className="min-h-24 w-full rounded-lg border border-input bg-surface px-3 py-2 text-sm"
                placeholder="Ownership for product delivery"
              />
            </div>
            <Button type="submit" variant="primary" size="sm" loading={createTeam.isPending}>
              <Plus />
              Create team
            </Button>
          </form>
        </Card>

        <div className="space-y-3">
          {isLoading ? (
            Array.from({ length: 3 }).map((_, index) => (
              <Skeleton key={index} className="h-32 rounded-xl" />
            ))
          ) : teams?.length ? (
            teams.map((team) => {
              const teamProjects = projects?.filter((project) => project.team_id === team.id) ?? []
              return (
                <Card key={team.id} className="p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <h3 className="text-sm font-semibold">{team.name}</h3>
                      <p className="mt-1 text-xs text-muted-foreground">
                        {team.description || 'No description given.'}
                      </p>
                    </div>
                    <Link href={`/teams/${team.id}`} className="text-xs font-medium text-primary hover:underline">
                      Open dashboard
                    </Link>
                  </div>

                  <div className="mt-3 flex flex-wrap gap-2 text-2xs text-muted-foreground">
                    <span className="inline-flex items-center gap-1 rounded-full border border-border bg-surface-raised px-2 py-1">
                      <Users className="size-3" /> {teamMembersMap.get(team.id)?.length ?? 0} members
                    </span>
                    <span className="inline-flex items-center gap-1 rounded-full border border-border bg-surface-raised px-2 py-1">
                      <ProjectIcon icon="Rocket" color="#5B5BD6" size="sm" /> {teamProjects.length} projects
                    </span>
                  </div>
                </Card>
              )
            })
          ) : (
            <EmptyState
              icon={<Users />}
              title="No teams yet"
              description="Create a team to group projects and members by ownership."
            />
          )}
        </div>
      </div>
    </div>
  )
}
