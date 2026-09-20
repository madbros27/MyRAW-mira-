import Link from 'next/link'

import { createSupabaseServerClient } from '@/lib/supabase/server'
import { InviteActions } from './invite-actions'

export const dynamic = 'force-dynamic'

export default async function InvitationPage({
  params,
}: {
  params: Promise<{ token: string }>
}) {
  const { token } = await params
  const supabase = await createSupabaseServerClient()
  const [{ data: preview }, { data: userResult }] = await Promise.all([
    supabase.rpc('get_project_invitation_preview', { p_token: token }),
    supabase.auth.getUser(),
  ])

  const invitation = preview?.[0]
  const next = `/invite/${encodeURIComponent(token)}`

  if (!invitation) {
    return (
      <main className="flex min-h-dvh items-center justify-center bg-canvas p-4">
        <section className="w-full max-w-md rounded-2xl border border-border bg-background p-6 shadow-sm">
          <h1 className="text-xl font-semibold">Invitation unavailable</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            This invitation does not exist or is no longer available.
          </p>
          <Link className="mt-5 inline-flex text-sm font-medium text-primary" href="/login">
            Return to sign in
          </Link>
        </section>
      </main>
    )
  }

  const isPending = invitation.status === 'pending'
  const isAuthenticated = Boolean(userResult.user)

  return (
    <main className="flex min-h-dvh items-center justify-center bg-canvas p-4">
      <section className="w-full max-w-md rounded-2xl border border-border bg-background p-6 shadow-sm">
        <p className="text-xs font-medium uppercase tracking-[0.2em] text-muted-foreground">
          MIRA invitation
        </p>
        <h1 className="mt-3 text-xl font-semibold">
          {isPending ? 'You\'ve been invited to join this project' : 'Invitation is no longer active'}
        </h1>
        <dl className="mt-6 space-y-3 text-sm">
          <div className="flex justify-between gap-4 border-b border-border pb-3">
            <dt className="text-muted-foreground">Project</dt>
            <dd className="text-right font-medium">{invitation.project_name}</dd>
          </div>
          {invitation.team_name ? (
            <div className="flex justify-between gap-4 border-b border-border pb-3">
              <dt className="text-muted-foreground">Team</dt>
              <dd className="text-right font-medium">{invitation.team_name}</dd>
            </div>
          ) : null}
          <div className="flex justify-between gap-4 border-b border-border pb-3">
            <dt className="text-muted-foreground">Invited by</dt>
            <dd className="text-right font-medium">{invitation.inviter_name}</dd>
          </div>
          <div className="flex justify-between gap-4">
            <dt className="text-muted-foreground">Status</dt>
            <dd className="text-right font-medium capitalize">{invitation.status}</dd>
          </div>
        </dl>

        {isPending && isAuthenticated ? (
          <InviteActions token={token} />
        ) : isPending ? (
          <div className="mt-6 grid gap-2 sm:grid-cols-2">
            <Link
              href={`/login?next=${encodeURIComponent(next)}`}
              className="inline-flex h-10 items-center justify-center rounded-lg bg-primary px-4 text-sm font-medium text-primary-foreground"
            >
              Sign in & join
            </Link>
            <Link
              href={`/signup?next=${encodeURIComponent(next)}`}
              className="inline-flex h-10 items-center justify-center rounded-lg border border-border px-4 text-sm font-medium"
            >
              Create account & join
            </Link>
          </div>
        ) : null}
      </section>
    </main>
  )
}
