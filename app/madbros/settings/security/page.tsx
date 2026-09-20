'use client'

import * as React from 'react'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import { Field, Input } from '@/components/ui/input'
import { getSupabaseBrowserClient } from '@/lib/supabase/client'
import { errorMessage } from '@/lib/utils'

export default function MadbrosSecurityPage() {
  const [password, setPassword] = React.useState('')
  const [confirm, setConfirm] = React.useState('')
  const [pending, setPending] = React.useState(false)

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault()

    if (!password.trim()) {
      toast.error('Password is required.')
      return
    }

    if (password.length < 8) {
      toast.error('Password must be at least 8 characters long.')
      return
    }

    if (password !== confirm) {
      toast.error('Passwords do not match.')
      return
    }

    setPending(true)

    try {
      const supabase = getSupabaseBrowserClient()
      const { error } = await supabase.auth.updateUser({ password })
      if (error) throw error
      toast.success('Password updated successfully.')
      setPassword('')
      setConfirm('')
    } catch (caught) {
      toast.error(errorMessage(caught, 'Unable to update password'))
    } finally {
      setPending(false)
    }
  }

  return (
    <main className="min-h-dvh bg-canvas p-4 sm:p-6">
      <div className="mx-auto max-w-xl rounded-2xl border border-border bg-background p-6 shadow-sm">
        <p className="text-xs font-medium uppercase tracking-[0.2em] text-muted-foreground">
          Madbros
        </p>
        <h1 className="mt-3 text-xl font-semibold">Security</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Update the system administrator credential using Supabase Auth.
        </p>

        <form onSubmit={handleSubmit} className="mt-6 space-y-4">
          <Field label="New password" htmlFor="new-password" required>
            <Input
              id="new-password"
              type="password"
              autoComplete="new-password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              placeholder="Enter a new password"
              required
            />
          </Field>

          <Field label="Confirm password" htmlFor="confirm-password" required>
            <Input
              id="confirm-password"
              type="password"
              autoComplete="new-password"
              value={confirm}
              onChange={(event) => setConfirm(event.target.value)}
              placeholder="Repeat the new password"
              required
            />
          </Field>

          <Button type="submit" variant="primary" size="lg" loading={pending} className="w-full">
            Update password
          </Button>
        </form>
      </div>
    </main>
  )
}
