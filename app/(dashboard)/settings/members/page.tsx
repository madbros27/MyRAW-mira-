'use client'

import { MoreHorizontal, UserMinus } from 'lucide-react'
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
  Skeleton,
} from '@/components/ui/primitives'
import { ROLE_META, WORKSPACE_ROLES } from '@/lib/constants'
import { formatDate } from '@/lib/format'
import { can } from '@/lib/permissions'
import { useMembers, useRemoveMember, useUpdateMemberRole } from '@/lib/queries/workspaces'
import type { Member } from '@/lib/types/app'
import type { WorkspaceRole } from '@/lib/types/database'
import { displayName, errorMessage } from '@/lib/utils'

export default function MembersSettingsPage() {
  const { workspaceId, workspace, userId, role } = useWorkspaceContext()
  const { data: members, isLoading } = useMembers(workspaceId)

  const updateRole = useUpdateMemberRole(workspaceId)
  const removeMember = useRemoveMember(workspaceId)

  const [removing, setRemoving] = React.useState<Member | null>(null)

  const canManage = can.manageMembers(role)
  const admins = (members ?? []).filter((member) => member.role === 'admin')

  return (
    <div className="max-w-3xl space-y-4 p-3 sm:p-4">
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
            ? 'You will lose access to every project in this workspace until an admin re-adds you.'
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
