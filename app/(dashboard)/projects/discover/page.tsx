'use client'

import { Search, ShieldCheck, UserRound, UserRoundPlus } from 'lucide-react'
import * as React from 'react'
import { toast } from 'sonner'

import { ProjectIcon } from '@/components/layout/project-icon'
import { useWorkspaceContext } from '@/components/providers/workspace-provider'
import { Button } from '@/components/ui/button'
import { Card, EmptyState, Skeleton } from '@/components/ui/primitives'
import { useCreateProjectJoinRequest, useProjectDiscovery, useCancelProjectJoinRequest } from '@/lib/queries/teams'
import { displayName, errorMessage } from '@/lib/utils'

export default function ProjectDiscoveryPage() {
  const { workspaceId, userId } = useWorkspaceContext()
  const { data: projects, isLoading } = useProjectDiscovery(workspaceId, userId)
  const request = useCreateProjectJoinRequest()
  const cancel = useCancelProjectJoinRequest()
  const [term, setTerm] = React.useState('')

  const filtered = React.useMemo(() => {
    const value = term.trim().toLowerCase()
    if (!value) return projects ?? []
    return (projects ?? []).filter((project) => {
      const haystack = [
        project.name,
        project.key,
        project.team?.name ?? '',
        project.lead?.full_name ?? '',
        project.lead?.email ?? '',
      ]
        .join(' ')
        .toLowerCase()
      return haystack.includes(value)
    })
  }, [projects, term])

  return (
    <div className="space-y-4 p-3 sm:p-4">
      <div className="rounded-2xl border border-border bg-background p-4">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              Discover
            </p>
            <h1 className="mt-1 text-xl font-semibold">Find projects</h1>
          </div>
        </div>

        <div className="mt-4 flex items-center gap-2 rounded-xl border border-border bg-surface px-3 py-2">
          <Search className="size-4 text-muted-foreground" />
          <input
            value={term}
            onChange={(event) => setTerm(event.target.value)}
            placeholder="Search by project name, key or team"
            className="w-full bg-transparent text-sm outline-none placeholder:text-muted-foreground"
          />
        </div>
      </div>

      {isLoading ? (
        <div className="grid gap-3 md:grid-cols-2">
          {[0, 1, 2, 3].map((index) => (
            <Skeleton key={index} className="h-32 rounded-xl" />
          ))}
        </div>
      ) : filtered.length ? (
        <div className="grid gap-3 md:grid-cols-2">
          {filtered.map((project) => {
            const status = project.joinRequest?.status ?? null
            const canRequest = !project.isTeamMember && !status
            const isPending = status === 'pending'
            const isApproved = status === 'approved'

            return (
              <Card key={project.id} className="p-4">
                <div className="flex items-start gap-3">
                  <ProjectIcon icon={project.icon} color={project.color} size="lg" />
                  <div className="min-w-0 flex-1">
                    <h2 className="truncate text-sm font-semibold">{project.name}</h2>
                    <p className="font-mono text-2xs text-muted-foreground">{project.key}</p>
                  </div>
                </div>

                <p className="mt-3 text-xs text-muted-foreground">
                  {project.description || 'No description yet.'}
                </p>

                <div className="mt-3 space-y-2 text-xs text-muted-foreground">
                  <div className="flex items-center gap-2">
                    <UserRound className="size-3.5" />
                    <span>{project.lead ? displayName(project.lead) : 'No lead yet'}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <ShieldCheck className="size-3.5" />
                    <span>{project.team ? `Team: ${project.team.name}` : 'No team assigned'}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <UserRoundPlus className="size-3.5" />
                    <span>
                      {project.isTeamMember ? 'You are already a member' : isPending ? 'Request pending' : isApproved ? 'Approved' : 'Not connected yet'}
                    </span>
                  </div>
                </div>

                <div className="mt-4 flex gap-2">
                  {canRequest ? (
                    <Button
                      variant="primary"
                      size="sm"
                      loading={request.isPending}
                      onClick={async () => {
                        try {
                          await request.mutateAsync({ projectId: project.id, userId: userId! })
                        } catch (error) {
                          toastError(error, 'Could not submit join request')
                        }
                      }}
                    >
                      Request to join
                    </Button>
                  ) : null}

                  {isPending ? (
                    <Button
                      variant="secondary"
                      size="sm"
                      loading={cancel.isPending}
                      onClick={async () => {
                        if (!project.joinRequest) return
                        try {
                          await cancel.mutateAsync({ requestId: project.joinRequest.id })
                        } catch (error) {
                          toastError(error, 'Could not cancel the request')
                        }
                      }}
                    >
                      Cancel request
                    </Button>
                  ) : null}

                  {project.isTeamMember ? (
                    <Button variant="secondary" size="sm" disabled>
                      Member
                    </Button>
                  ) : null}
                </div>
              </Card>
            )
          })}
        </div>
      ) : (
        <EmptyState
          title="No matching projects"
          description="Try another search term or ask an admin to add you to a project team."
        />
      )}
    </div>
  )
}

function toastError(error: unknown, fallback: string) {
  const message = errorMessage(error, fallback)
  toast.error(message)
}
