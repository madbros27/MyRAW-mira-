'use client'

import * as React from 'react'
import { toast } from 'sonner'

import { useWorkspaceContext } from '@/components/providers/workspace-provider'
import { Button } from '@/components/ui/button'
import { Field, Input, Textarea } from '@/components/ui/input'
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
  EmptyState,
} from '@/components/ui/primitives'
import { formatDate } from '@/lib/format'
import { can } from '@/lib/permissions'
import { useMembers, useUpdateWorkspace } from '@/lib/queries/workspaces'
import { useProjects } from '@/lib/queries/projects'
import { errorMessage } from '@/lib/utils'

export default function WorkspaceSettingsPage() {
  const { workspace, workspaceId, role } = useWorkspaceContext()
  const { data: members } = useMembers(workspaceId)
  const { data: projects } = useProjects(workspaceId, true)
  const update = useUpdateWorkspace()

  const [form, setForm] = React.useState({ name: '', description: '' })

  React.useEffect(() => {
    setForm({
      name: workspace?.name ?? '',
      description: workspace?.description ?? '',
    })
  }, [workspace])

  if (!can.manageWorkspace(role)) {
    return (
      <div className="p-4 sm:p-8">
        <EmptyState
          title="Workspace settings are restricted"
          description="Only workspace admins can rename the workspace or change its details."
        />
      </div>
    )
  }

  const dirty =
    workspace &&
    (form.name !== workspace.name || form.description !== (workspace.description ?? ''))

  return (
    <div className="max-w-2xl space-y-4 p-3 sm:p-4">
      <Card>
        <form
          onSubmit={async (event) => {
            event.preventDefault()
            if (!workspace) return
            try {
              await update.mutateAsync({
                id: workspace.id,
                name: form.name.trim(),
                description: form.description.trim() || null,
              })
              toast.success('Workspace updated')
            } catch (error) {
              toast.error(errorMessage(error, 'Could not save the workspace'))
            }
          }}
        >
          <CardHeader>
            <CardTitle>Workspace details</CardTitle>
            <CardDescription>
              The workspace is the boundary for permissions: members only ever see projects and
              issues that belong to it.
            </CardDescription>
          </CardHeader>

          <div className="space-y-4 px-4 pb-4 sm:px-5">
            <Field label="Name" htmlFor="workspace-name" required>
              <Input
                id="workspace-name"
                value={form.name}
                onChange={(event) => setForm((prev) => ({ ...prev, name: event.target.value }))}
                maxLength={80}
                required
              />
            </Field>

            <Field label="Description" htmlFor="workspace-description">
              <Textarea
                id="workspace-description"
                value={form.description}
                onChange={(event) =>
                  setForm((prev) => ({ ...prev, description: event.target.value }))
                }
                rows={3}
                placeholder="What does this team work on?"
              />
            </Field>

            <Field
              label="URL slug"
              htmlFor="workspace-slug"
              hint="Generated when the workspace was created and used internally."
            >
              <Input
                id="workspace-slug"
                value={workspace?.slug ?? ''}
                readOnly
                disabled
                className="font-mono"
              />
            </Field>

            <div className="flex justify-end">
              <Button type="submit" variant="primary" disabled={!dirty} loading={update.isPending}>
                Save changes
              </Button>
            </div>
          </div>
        </form>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>At a glance</CardTitle>
        </CardHeader>
        <dl className="grid grid-cols-2 gap-px overflow-hidden rounded-b-xl border-t border-border bg-border sm:grid-cols-4">
          {[
            { label: 'Members', value: members?.length ?? 0 },
            { label: 'Projects', value: projects?.length ?? 0 },
            {
              label: 'Archived',
              value: projects?.filter((project) => project.is_archived).length ?? 0,
            },
            { label: 'Created', value: formatDate(workspace?.created_at) },
          ].map((item) => (
            <div key={item.label} className="bg-surface px-4 py-3">
              <dt className="text-2xs uppercase tracking-wide text-muted-foreground">
                {item.label}
              </dt>
              <dd className="mt-0.5 text-lg font-semibold tabular-nums">{item.value}</dd>
            </div>
          ))}
        </dl>
      </Card>

      <Card className="border-destructive/30">
        <CardHeader>
          <CardTitle className="text-destructive">Deleting a workspace</CardTitle>
          <CardDescription>
            Only the workspace owner can delete a workspace, and only from the database — it
            removes every project, issue, comment and attachment with no way back. Remove
            individual projects instead if that is what you need.
          </CardDescription>
        </CardHeader>
      </Card>
    </div>
  )
}
