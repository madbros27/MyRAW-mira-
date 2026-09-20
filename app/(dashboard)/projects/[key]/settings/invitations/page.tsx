'use client'

import * as React from 'react'
import { toast } from 'sonner'

import { ProjectPage } from '@/components/projects/project-page'
import { useProjectContext } from '@/components/projects/project-provider'
import { useWorkspaceContext } from '@/components/providers/workspace-provider'
import { Button } from '@/components/ui/button'
import { Card, CardDescription, CardHeader, CardTitle, EmptyState } from '@/components/ui/primitives'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/controls'
import { Field, Input } from '@/components/ui/input'
import { useTeams } from '@/lib/queries/teams'
import { getSupabaseBrowserClient } from '@/lib/supabase/client'
import { getSiteUrl } from '@/lib/supabase/env'
import { errorMessage } from '@/lib/utils'

export default function ProjectInvitationsPage() {
  const { project } = useProjectContext()
  const { profile, role, workspaceId } = useWorkspaceContext()
  const { data: teams } = useTeams(workspaceId)
  const [email, setEmail] = React.useState('')
  const [teamId, setTeamId] = React.useState('none')
  const [link, setLink] = React.useState<string | null>(null)
  const [expiresAt, setExpiresAt] = React.useState<string | null>(null)
  const [pendingInvitationExists, setPendingInvitationExists] = React.useState(false)
  const [pending, setPending] = React.useState(false)

  const canManage = Boolean(
    project && (profile?.is_system_admin || project.owner_id === profile?.id || role === 'admin')
  )

  if (!project || !canManage) {
    return (
      <ProjectPage>
        <div className="p-4 sm:p-8">
          <EmptyState
            title="Invitations are restricted"
            description="Only the Project Owner or system administrator can invite project members."
          />
        </div>
      </ProjectPage>
    )
  }

  const currentProject = project
  const inviterName = profile?.full_name?.trim() || profile?.email || 'MIRA team'
  const mailtoUrl = link
    ? `mailto:${email.trim()}?${new URLSearchParams({
        subject: `You're invited to join ${currentProject.name} on MIRA`,
        body: [
          `Hi,`,
          `\n${inviterName} invited you to join ${currentProject.name} on MIRA.`,
          `\nOpen this link and sign in or sign up using ${email.trim()}:`,
          link,
          `\nRegards,`,
          inviterName,
        ].join('\n')
      }).toString()}`
    : null

  async function generate() {
    if (!email.trim()) return
    setPending(true)
    try {
      const supabase = getSupabaseBrowserClient()
      const { data, error } = await supabase.rpc('create_project_invitation', {
        p_project_id: currentProject.id,
        p_invited_email: email.trim(),
        p_team_id: teamId === 'none' ? null : teamId,
      })
      if (error) throw error
      const invitation = Array.isArray(data) ? data[0] : data
      const invitationLink = new URL(`/invite/${invitation.token}`, getSiteUrl()).toString()
      const existsPending = invitation.status === 'pending'
      setLink(invitationLink)
      setExpiresAt(invitation.expires_at)
      setPendingInvitationExists(existsPending)
      toast.success(
        existsPending
          ? `A pending invitation already exists for ${email.trim()}.`
          : 'Invitation generated.'
      )
    } catch (caught) {
      const message = errorMessage(caught, 'Unable to generate invitation')
      toast.error(message)
    } finally {
      setPending(false)
    }
  }

  return (
    <ProjectPage description="Invite people to this project or a specific team.">
      <div className="p-3 sm:p-4">
        <Card className="max-w-2xl">
          <CardHeader>
            <CardTitle>Project invitations</CardTitle>
            <CardDescription>
              Invitations grant project membership and optionally add the person to one team.
            </CardDescription>
          </CardHeader>
          <div className="space-y-4 px-4 pb-4 sm:px-5">
            <Field label="Email" htmlFor="invited-email" required>
              <Input
                id="invited-email"
                type="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                placeholder="person@example.com"
                required
              />
            </Field>
            <Field label="Team">
              <Select value={teamId} onValueChange={setTeamId}>
                <SelectTrigger aria-label="Invitation team">
                  <SelectValue placeholder="Project only" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">Project only</SelectItem>
                  {(teams ?? []).map((team) => (
                    <SelectItem key={team.id} value={team.id}>{team.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Button type="button" variant="primary" loading={pending} onClick={generate}>
              Generate invitation
            </Button>
            {link ? (
              <div className="space-y-2 rounded-lg border border-border bg-surface-raised p-3">
                <p className="text-sm font-medium text-foreground">
                  {pendingInvitationExists
                    ? `A pending invitation already exists for ${email.trim()}.`
                    : 'Invitation created successfully.'}
                </p>
                {expiresAt ? (
                  <p className="text-xs text-muted-foreground">
                    Expiration: {new Date(expiresAt).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })}
                  </p>
                ) : null}
                <Input readOnly value={link} aria-label="Invitation link" />
                <div className="flex flex-wrap gap-2">
                  <Button
                    type="button"
                    variant="secondary"
                    size="sm"
                    onClick={async () => {
                      try {
                        await navigator.clipboard.writeText(link)
                        toast.success('Invitation link copied to clipboard.')
                      } catch {
                        toast.error('Unable to copy the invitation link.')
                      }
                    }}
                  >
                    Copy invitation link
                  </Button>
                  {mailtoUrl ? (
                    <Button type="button" variant="secondary" size="sm" asChild>
                      <a href={mailtoUrl}>Send via Email</a>
                    </Button>
                  ) : null}
                </div>
              </div>
            ) : null}
          </div>
        </Card>
      </div>
    </ProjectPage>
  )
}
