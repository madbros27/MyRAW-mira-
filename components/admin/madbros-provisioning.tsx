'use client'

import * as React from 'react'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import { Field, Input } from '@/components/ui/input'
import { getSupabaseBrowserClient } from '@/lib/supabase/client'
import type { Profile } from '@/lib/types/app'
import { errorMessage } from '@/lib/utils'

export function MadbrosProvisioning({ profiles }: { profiles: Pick<Profile, 'id' | 'email' | 'full_name'>[] }) {
  const [workspaceName, setWorkspaceName] = React.useState('')
  const [projectName, setProjectName] = React.useState('')
  const [projectKey, setProjectKey] = React.useState('')
  const [ownerId, setOwnerId] = React.useState(profiles[0]?.id ?? '')
  const [pending, setPending] = React.useState(false)

  async function submit(event: React.FormEvent) {
    event.preventDefault()
    setPending(true)
    try {
      const supabase = getSupabaseBrowserClient()
      const { error } = await supabase.rpc('create_workspace_and_project', {
        p_workspace_name: workspaceName.trim(),
        p_project_name: projectName.trim(),
        p_project_key: projectKey.trim().toUpperCase(),
        p_project_owner: ownerId,
      })
      if (error) throw error

      toast.success('Workspace and project created.')
      setWorkspaceName('')
      setProjectName('')
      setProjectKey('')
    } catch (caught) {
      toast.error(errorMessage(caught, 'Unable to provision workspace and project'))
    } finally {
      setPending(false)
    }
  }

  return (
    <section className="rounded-2xl border border-border bg-background p-5 shadow-sm">
      <h2 className="text-base font-semibold">Create workspace and project</h2>
      <p className="mt-1 text-sm text-muted-foreground">
        This operation is restricted again by the system-admin RPC and creates the owner access records transactionally within project creation.
      </p>
      <form onSubmit={submit} className="mt-4 grid gap-3 sm:grid-cols-2">
        <Field label="Workspace name" htmlFor="madbros-workspace" required>
          <Input id="madbros-workspace" value={workspaceName} onChange={(event) => setWorkspaceName(event.target.value)} required />
        </Field>
        <Field label="Project name" htmlFor="madbros-project" required>
          <Input id="madbros-project" value={projectName} onChange={(event) => setProjectName(event.target.value)} required />
        </Field>
        <Field label="Project key" htmlFor="madbros-project-key" required>
          <Input id="madbros-project-key" value={projectKey} onChange={(event) => setProjectKey(event.target.value.toUpperCase().replace(/[^A-Z0-9]/g, ''))} maxLength={10} required />
        </Field>
        <Field label="Project Owner" htmlFor="madbros-owner" required>
          <select id="madbros-owner" value={ownerId} onChange={(event) => setOwnerId(event.target.value)} className="h-10 w-full rounded-lg border border-input bg-surface px-3 text-sm" required>
            {profiles.map((profile) => (
              <option key={profile.id} value={profile.id}>
                {profile.full_name || profile.email}
              </option>
            ))}
          </select>
        </Field>
        <Button type="submit" variant="primary" loading={pending} className="sm:col-span-2">
          Create workspace and project
        </Button>
      </form>
    </section>
  )
}
