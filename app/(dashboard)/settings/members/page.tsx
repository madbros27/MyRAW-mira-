'use client'

import { Copy, Mail, MoreHorizontal, Send, Trash2, UserMinus } from 'lucide-react'
import * as React from 'react'
import { toast } from 'sonner'

import { useWorkspaceContext } from '@/components/providers/workspace-provider'
import { Button } from '@/components/ui/button'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/controls'
import { Field, Input } from '@/components/ui/input'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/menu'
import {
  Avatar,
  Badge,
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
  EmptyState,
  Skeleton,
} from '@/components/ui/primitives'
import { ROLE_META, WORKSPACE_ROLES } from '@/lib/constants'
import { formatDate, formatRelative } from '@/lib/format'
import { can } from '@/lib/permissions'
import {
  useInviteMember,
  useInvites,
  useMembers,
  useRemoveMember,
  useRevokeInvite,
  useUpdateMemberRole,
} from '@/lib/queries/workspaces'
import type { Member } from '@/lib/types/app'
import type { WorkspaceRole } from '@/lib/types/database'
import { displayName, errorMessage } from '@/lib/utils'

export default function MembersSettingsPage() {
  const { workspaceId, workspace, userId, role } = useWorkspaceContext()
  const { data: members, isLoading } = useMembers(workspaceId)
  const { data: invites } = useInvites(workspaceId)

  const invite = useInviteMember(workspaceId)
  const updateRole = useUpdateMemberRole(workspaceId)
  const removeMember = useRemoveMember(workspaceId)
  const revoke = useRevokeInvite(workspaceId)

  const [email, setEmail] = React.useState('')
  const [inviteRole, setInviteRole] = React.useState<WorkspaceRole>('member')
  const [removing, setRemoving] = React.useState<Member | null>(null)
  const [lastInviteUrl, setLastInviteUrl] = React.useState<string | null>(null)

  const canManage = can.manageMembers(role)
  const pending = (invites ?? []).filter((item) => item.status === 'pending')
  const admins = (members ?? []).filter((member) => member.role === 'admin')

  async function sendInvite(event: React.FormEvent) {
    event.preventDefault()
    if (!email.trim()) return
    try {
      const result = await invite.mutateAsync({ email: email.trim(), role: inviteRole })
      setEmail('')
      setLastInviteUrl(result.inviteUrl ?? null)
      toast.success(
        result.emailed
          ? `Invitation emailed to ${email.trim()}`
          : 'Invitation created — copy the link below and share it.'
      )
    } catch (error) {
      toast.error(errorMessage(error, 'Could not send the invitation'))
    }
  }

  return (
    <div className="max-w-3xl space-y-4 p-3 sm:p-4">
      {can.inviteMembers(role) ? (
        <Card>
          <form onSubmit={sendInvite}>
            <CardHeader>
              <CardTitle>Invite teammates</CardTitle>
              <CardDescription>
                We match invitations to the email address, so the invite is accepted
                automatically when they sign up or sign in.
              </CardDescription>
            </CardHeader>

            <div className="space-y-3 px-4 pb-4 sm:px-5">
              <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
                <Field label="Email address" htmlFor="invite-email" className="flex-1" required>
                  <Input
                    id="invite-email"
                    type="email"
                    value={email}
                    onChange={(event) => setEmail(event.target.value)}
                    placeholder="teammate@company.com"
                    required
                  />
                </Field>
                <Field label="Role" className="sm:w-44">
                  <Select
                    value={inviteRole}
                    onValueChange={(value) => setInviteRole(value as WorkspaceRole)}
                  >
                    <SelectTrigger aria-label="Invite role">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {WORKSPACE_ROLES.map((item) => (
                        <SelectItem key={item} value={item}>
                          {ROLE_META[item].label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </Field>
                <Button type="submit" variant="primary" loading={invite.isPending}>
                  <Send />
                  Send invite
                </Button>
              </div>

              <p className="text-2xs text-muted-foreground">
                {ROLE_META[inviteRole].description}
              </p>

              {lastInviteUrl ? (
                <div className="flex items-center gap-2 rounded-lg border border-border bg-surface-raised px-2.5 py-2">
                  <code className="min-w-0 flex-1 truncate font-mono text-2xs">
                    {lastInviteUrl}
                  </code>
                  <Button
                    type="button"
                    variant="ghost"
                    size="xs"
                    onClick={async () => {
                      await navigator.clipboard.writeText(lastInviteUrl)
                      toast.success('Invite link copied')
                    }}
                  >
                    <Copy />
                    Copy
                  </Button>
                </div>
              ) : null}
            </div>
          </form>
        </Card>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle>Members</CardTitle>
          <CardDescription>
            {members?.length ?? 0} in {workspace?.name}. Roles are enforced by Postgres
            row-level security, not just in the interface.
          </CardDescription>
        </CardHeader>

        {isLoading ? (
          <div className="space-y-2 border-t border-border p-4">
            {[0, 1, 2].map((i) => (
              <Skeleton key={i} className="h-12 w-full rounded-lg" />
            ))}
          </div>
        ) : (
          <ul className="divide-y divide-border border-t border-border">
            {(members ?? []).map((member) => {
              const isSelf = member.user_id === userId
              const isLastAdmin = member.role === 'admin' && admins.length === 1

              return (
                <li
                  key={member.user_id}
                  className="flex flex-wrap items-center gap-3 px-4 py-3 sm:px-5"
                >
                  <Avatar
                    id={member.user_id}
                    name={member.profile?.full_name ?? member.profile?.email}
                    src={member.profile?.avatar_url}
                    size="md"
                  />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium">
                      {displayName(member.profile)}
                      {isSelf ? (
                        <span className="ml-1.5 text-2xs text-muted-foreground">you</span>
                      ) : null}
                    </p>
                    <p className="truncate text-2xs text-muted-foreground">
                      {member.profile?.email} · joined {formatDate(member.created_at)}
                    </p>
                  </div>

                  {canManage && !isLastAdmin ? (
                    <Select
                      value={member.role}
                      onValueChange={(value) =>
                        updateRole.mutate({
                          userId: member.user_id,
                          role: value as WorkspaceRole,
                        })
                      }
                    >
                      <SelectTrigger
                        size="sm"
                        className="w-auto min-w-32"
                        aria-label={`Role for ${displayName(member.profile)}`}
                      >
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {WORKSPACE_ROLES.map((item) => (
                          <SelectItem key={item} value={item}>
                            {ROLE_META[item].label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  ) : (
                    <Badge className={ROLE_META[member.role].className} size="md">
                      {ROLE_META[member.role].label}
                    </Badge>
                  )}

                  {canManage && !isLastAdmin ? (
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button
                          variant="ghost"
                          size="icon-sm"
                          aria-label={`Actions for ${displayName(member.profile)}`}
                        >
                          <MoreHorizontal />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end">
                        <DropdownMenuItem destructive onSelect={() => setRemoving(member)}>
                          <UserMinus />
                          {isSelf ? 'Leave workspace' : 'Remove from workspace'}
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  ) : null}
                </li>
              )
            })}
          </ul>
        )}
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Pending invitations</CardTitle>
          <CardDescription>
            Invitations expire after 14 days and are accepted on first sign-in.
          </CardDescription>
        </CardHeader>

        {pending.length ? (
          <ul className="divide-y divide-border border-t border-border">
            {pending.map((item) => (
              <li
                key={item.id}
                className="flex flex-wrap items-center gap-3 px-4 py-2.5 sm:px-5"
              >
                <span className="flex size-8 shrink-0 items-center justify-center rounded-full bg-muted text-muted-foreground">
                  <Mail className="size-4" />
                </span>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium">{item.email}</p>
                  <p className="text-2xs text-muted-foreground">
                    Invited {formatRelative(item.created_at)} · expires{' '}
                    {formatDate(item.expires_at)}
                  </p>
                </div>
                <Badge className={ROLE_META[item.role].className}>
                  {ROLE_META[item.role].label}
                </Badge>
                {can.inviteMembers(role) ? (
                  <>
                    <Button
                      variant="ghost"
                      size="xs"
                      onClick={async () => {
                        const url = `${window.location.origin}/invite/${item.token}`
                        await navigator.clipboard.writeText(url)
                        toast.success('Invite link copied')
                      }}
                    >
                      <Copy />
                      Link
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      onClick={() => revoke.mutate(item.id)}
                      aria-label={`Revoke the invitation for ${item.email}`}
                    >
                      <Trash2 />
                    </Button>
                  </>
                ) : null}
              </li>
            ))}
          </ul>
        ) : (
          <div className="border-t border-border px-4 py-6">
            <EmptyState
              icon={<Mail />}
              title="No pending invitations"
              description="Everyone you invited has joined, or you have not invited anyone yet."
              compact
              className="border-0 bg-transparent"
            />
          </div>
        )}
      </Card>

      <ConfirmDialog
        open={Boolean(removing)}
        onOpenChange={(open) => (open ? null : setRemoving(null))}
        title={
          removing?.user_id === userId
            ? `Leave ${workspace?.name}?`
            : `Remove ${displayName(removing?.profile)}?`
        }
        description={
          removing?.user_id === userId
            ? 'You will lose access to every project in this workspace until someone invites you back.'
            : 'They lose access immediately. Issues they reported or were assigned keep their name.'
        }
        confirmLabel={removing?.user_id === userId ? 'Leave workspace' : 'Remove member'}
        destructive
        onConfirm={async () => {
          if (!removing) return
          try {
            await removeMember.mutateAsync(removing.user_id)
            toast.success(
              removing.user_id === userId ? 'You left the workspace' : 'Member removed'
            )
            setRemoving(null)
            if (removing.user_id === userId) window.location.assign('/')
          } catch (error) {
            toast.error(errorMessage(error, 'Could not remove the member'))
          }
        }}
      />
    </div>
  )
}
