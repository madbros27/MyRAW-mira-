/**
 * UI-side mirror of the Row-Level Security policies.
 *
 * These helpers decide what to *show*. They are deliberately not the security
 * boundary — Postgres is (see `supabase/migrations/*_rls.sql`). Keeping the two
 * in sync means a viewer never sees a button that would fail server-side.
 */

import type { WorkspaceRole } from '@/lib/types/database'

const RANK: Record<WorkspaceRole, number> = {
  admin: 4,
  lead: 3,
  member: 2,
  viewer: 1,
}

export function atLeast(role: WorkspaceRole | undefined, minimum: WorkspaceRole) {
  if (!role) return false
  return RANK[role] >= RANK[minimum]
}

export const can = {
  /** Create and edit issues, comment, attach files. */
  writeIssues: (role?: WorkspaceRole) => atLeast(role, 'member'),
  /** Project settings, workflow, labels, sprint lifecycle. */
  manageProject: (role?: WorkspaceRole) => atLeast(role, 'lead'),
  /** Create and delete projects. */
  createProject: (role?: WorkspaceRole) => atLeast(role, 'lead'),
  deleteProject: (role?: WorkspaceRole) => atLeast(role, 'lead'),
  /** Delete any issue (members may still delete issues they reported). */
  deleteAnyIssue: (role?: WorkspaceRole) => atLeast(role, 'lead'),
  /** Workspace settings and membership. */
  manageWorkspace: (role?: WorkspaceRole) => atLeast(role, 'admin'),
  manageMembers: (role?: WorkspaceRole) => atLeast(role, 'admin'),
  manageSprints: (role?: WorkspaceRole) => atLeast(role, 'lead'),
  manageTeams: (role?: WorkspaceRole) => atLeast(role, 'admin'),
  manageRoles: (role?: WorkspaceRole) => atLeast(role, 'admin'),
  approveJoinRequests: (role?: WorkspaceRole) => atLeast(role, 'lead'),
}

export function canDeleteIssue(
  role: WorkspaceRole | undefined,
  reporterId: string | null,
  userId: string | undefined
) {
  if (can.deleteAnyIssue(role)) return true
  return can.writeIssues(role) && !!reporterId && reporterId === userId
}

export function canEditComment(authorId: string | null, userId: string | undefined) {
  return !!authorId && authorId === userId
}

export function canDeleteComment(
  role: WorkspaceRole | undefined,
  authorId: string | null,
  userId: string | undefined
) {
  return canEditComment(authorId, userId) || can.manageProject(role)
}
