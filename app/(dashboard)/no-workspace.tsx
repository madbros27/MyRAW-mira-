'use client'

import { LogOut, Plus } from 'lucide-react'
import { useRouter } from 'next/navigation'
import * as React from 'react'
import { toast } from 'sonner'

import { setActiveWorkspace } from '@/app/actions'
import { Wordmark } from '@/components/layout/logo'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/primitives'
import { Field, Input } from '@/components/ui/input'
import { useCreateWorkspace } from '@/lib/queries/workspaces'
import { errorMessage } from '@/lib/utils'

/**
 * Shown when the signed-in account belongs to no workspace — usually because
 * an admin removed them, or because the demo bootstrap did not run.
 */
export function NoWorkspace({ email }: { email: string }) {
  const router = useRouter()
  const create = useCreateWorkspace()
  const [name, setName] = React.useState('')

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault()
    if (!name.trim()) return
    try {
      const workspace = await create.mutateAsync({ name: name.trim() })
      await setActiveWorkspace(workspace.id)
      router.refresh()
    } catch (error) {
      toast.error(errorMessage(error, 'Could not create the workspace'))
    }
  }

  return (
    <main className="flex min-h-dvh items-center justify-center bg-canvas p-4">
      <Card className="w-full max-w-md p-6 shadow-md">
        <Wordmark />
        <h1 className="mt-5 text-lg font-semibold">Create your first workspace</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          You are signed in as <span className="font-medium text-foreground">{email}</span> but
          you do not belong to a workspace yet. Create one, or ask an administrator to add you to
          an existing workspace.
        </p>

        <form onSubmit={handleSubmit} className="mt-5 space-y-4">
          <Field label="Workspace name" htmlFor="ws-name" required>
            <Input
              id="ws-name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="Acme Engineering"
              maxLength={80}
              autoFocus
              required
            />
          </Field>
          <Button type="submit" variant="primary" className="w-full" loading={create.isPending}>
            <Plus />
            Create workspace
          </Button>
        </form>

        <form action="/auth/signout" method="post" className="mt-4">
          <Button type="submit" variant="ghost" size="sm" className="w-full">
            <LogOut />
            Sign out
          </Button>
        </form>
      </Card>
    </main>
  )
}
