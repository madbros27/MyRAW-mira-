'use client'

import { Check, ChevronsUpDown, Plus, Settings } from 'lucide-react'
import { useRouter } from 'next/navigation'
import * as React from 'react'
import { toast } from 'sonner'

import { setActiveWorkspace } from '@/app/actions'
import { useWorkspaceContext } from '@/components/providers/workspace-provider'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Field, Input } from '@/components/ui/input'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/menu'
import { Badge } from '@/components/ui/primitives'
import { ROLE_META } from '@/lib/constants'
import { useCreateWorkspace } from '@/lib/queries/workspaces'
import { cn, errorMessage, initials } from '@/lib/utils'

export function WorkspaceSwitcher({ variant = 'sidebar' }: { variant?: 'sidebar' | 'plain' }) {
  const router = useRouter()
  const { workspace, workspaces } = useWorkspaceContext()
  const [creating, setCreating] = React.useState(false)
  const [pending, setPending] = React.useState(false)

  async function switchTo(workspaceId: string) {
    if (workspaceId === workspace?.id) return
    setPending(true)
    try {
      await setActiveWorkspace(workspaceId)
      router.push('/')
      router.refresh()
    } finally {
      setPending(false)
    }
  }

  const dark = variant === 'sidebar'

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            disabled={pending}
            className={cn(
              'group flex w-full items-center gap-2.5 rounded-lg px-2 py-1.5 text-left transition-colors',
              dark
                ? 'text-sidebar-foreground hover:bg-sidebar-accent'
                : 'border border-border bg-surface hover:bg-muted'
            )}
          >
            <span
              className={cn(
                'flex size-7 shrink-0 items-center justify-center rounded-md text-2xs font-bold uppercase',
                dark ? 'bg-primary text-primary-foreground' : 'bg-primary-subtle text-primary-subtle-foreground'
              )}
            >
              {initials(workspace?.name, 'W')}
            </span>
            <span className="min-w-0 flex-1">
              <span className="block truncate text-sm font-semibold">
                {workspace?.name ?? 'No workspace'}
              </span>
              <span
                className={cn(
                  'block truncate text-2xs',
                  dark ? 'text-sidebar-muted' : 'text-muted-foreground'
                )}
              >
                {workspace ? ROLE_META[workspace.role].label : 'Create one to start'}
              </span>
            </span>
            <ChevronsUpDown
              className={cn(
                'size-3.5 shrink-0 opacity-60 transition-opacity group-hover:opacity-100'
              )}
            />
          </button>
        </DropdownMenuTrigger>

        <DropdownMenuContent align="start" className="w-64">
          <DropdownMenuLabel>Workspaces</DropdownMenuLabel>
          {workspaces.map((item) => (
            <DropdownMenuItem
              key={item.id}
              onSelect={() => switchTo(item.id)}
              className="gap-2.5"
            >
              <span className="flex size-6 shrink-0 items-center justify-center rounded-md bg-primary-subtle text-2xs font-bold uppercase text-primary-subtle-foreground">
                {initials(item.name, 'W')}
              </span>
              <span className="min-w-0 flex-1 truncate">{item.name}</span>
              <Badge variant="outline" className="shrink-0">
                {ROLE_META[item.role].label}
              </Badge>
              {item.id === workspace?.id ? (
                <Check className="size-3.5 !text-primary" />
              ) : null}
            </DropdownMenuItem>
          ))}

          <DropdownMenuSeparator />
          <DropdownMenuItem onSelect={() => setCreating(true)}>
            <Plus />
            New workspace
          </DropdownMenuItem>
          {workspace ? (
            <DropdownMenuItem onSelect={() => router.push('/settings/workspace')}>
              <Settings />
              Workspace settings
            </DropdownMenuItem>
          ) : null}
        </DropdownMenuContent>
      </DropdownMenu>

      <CreateWorkspaceDialog open={creating} onOpenChange={setCreating} />
    </>
  )
}

function CreateWorkspaceDialog({
  open,
  onOpenChange,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const router = useRouter()
  const create = useCreateWorkspace()
  const [name, setName] = React.useState('')

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault()
    if (!name.trim()) return
    try {
      const workspace = await create.mutateAsync({ name: name.trim() })
      await setActiveWorkspace(workspace.id)
      toast.success(`${workspace.name} is ready`)
      onOpenChange(false)
      setName('')
      router.push('/')
      router.refresh()
    } catch (error) {
      toast.error(errorMessage(error, 'Could not create the workspace'))
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent size="sm">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>New workspace</DialogTitle>
            <DialogDescription>
              A workspace holds its own projects, members and permissions.
            </DialogDescription>
          </DialogHeader>
          <DialogBody>
            <Field label="Name" htmlFor="workspace-name" required>
              <Input
                id="workspace-name"
                value={name}
                onChange={(event) => setName(event.target.value)}
                placeholder="Acme Engineering"
                maxLength={80}
                autoFocus
                required
              />
            </Field>
          </DialogBody>
          <DialogFooter>
            <Button type="button" variant="secondary" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button type="submit" variant="primary" loading={create.isPending}>
              Create workspace
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
