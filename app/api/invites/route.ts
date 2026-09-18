import { NextResponse, type NextRequest } from 'next/server'

import { getSiteUrl } from '@/lib/supabase/env'
import { createSupabaseAdminClient, createSupabaseServerClient } from '@/lib/supabase/server'
import type { WorkspaceRole } from '@/lib/types/database'

const ROLES: WorkspaceRole[] = ['admin', 'lead', 'member', 'viewer']

/**
 * Create a workspace invitation.
 *
 * The row is inserted as the signed-in user, so RLS decides whether they are
 * allowed to invite at all. Only the email delivery uses the service-role key,
 * which is why this lives in a route handler instead of the browser.
 */
export async function POST(request: NextRequest) {
  let body: { workspaceId?: string; email?: string; role?: string }
  try {
    body = await request.json()
  } catch {
    return NextResponse.json({ error: 'Expected a JSON body' }, { status: 400 })
  }

  const workspaceId = body.workspaceId?.trim()
  const email = body.email?.trim().toLowerCase()
  const role = (body.role ?? 'member') as WorkspaceRole

  if (!workspaceId || !email) {
    return NextResponse.json(
      { error: 'workspaceId and email are both required' },
      { status: 400 }
    )
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return NextResponse.json({ error: 'That does not look like an email address' }, { status: 400 })
  }
  if (!ROLES.includes(role)) {
    return NextResponse.json({ error: `Unknown role "${role}"` }, { status: 400 })
  }

  const supabase = await createSupabaseServerClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) {
    return NextResponse.json({ error: 'You need to be signed in' }, { status: 401 })
  }

  // Already a member? Nothing to do.
  const { data: existingMember } = await supabase
    .from('workspace_members')
    .select('user_id, profile:profiles!workspace_members_user_id_fkey(email)')
    .eq('workspace_id', workspaceId)
    .limit(1000)

  const alreadyMember = (existingMember ?? []).some(
    (row) =>
      (row as unknown as { profile: { email: string } | null }).profile?.email?.toLowerCase() ===
      email
  )
  if (alreadyMember) {
    return NextResponse.json(
      { error: 'That person is already a member of this workspace' },
      { status: 409 }
    )
  }

  // RLS enforces that only admins and leads can insert here.
  const { data: invite, error } = await supabase
    .from('workspace_invites')
    .insert({ workspace_id: workspaceId, email, role, invited_by: user.id })
    .select('id, token, email, role')
    .single()

  if (error) {
    const isDuplicate = /duplicate key|workspace_invites_pending_unique/i.test(error.message)
    const isDenied = /row-level security/i.test(error.message)
    return NextResponse.json(
      {
        error: isDuplicate
          ? 'There is already a pending invitation for that email address'
          : isDenied
            ? 'Only workspace admins and project leads can invite people'
            : error.message,
      },
      { status: isDuplicate ? 409 : isDenied ? 403 : 400 }
    )
  }

  const inviteUrl = `${getSiteUrl()}/invite/${invite.token}`

  // Try to email the invitation. This needs the service-role key and only
  // works for addresses that do not have an account yet — everyone else simply
  // signs in and the invite is claimed automatically.
  let emailed = false
  let emailError: string | null = null

  try {
    const admin = createSupabaseAdminClient()
    const { error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
      redirectTo: inviteUrl,
    })
    if (inviteError) throw inviteError
    emailed = true
  } catch (caught) {
    emailError =
      caught instanceof Error ? caught.message : 'Email delivery is not configured'
  }

  return NextResponse.json({
    ok: true,
    inviteId: invite.id,
    inviteUrl,
    emailed,
    // Not an error for the caller: the link can always be shared manually.
    emailNotice: emailed ? null : emailError,
  })
}
