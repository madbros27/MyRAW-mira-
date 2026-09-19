/**
 * Application-level shapes: the joined rows MIRA actually renders, plus the
 * filter model shared by the board, the backlog and the query builder.
 */

import type {
  AttachmentRow,
  ActivityLogRow,
  CommentRow,
  IssuePriority,
  IssueRow,
  IssueType,
  LabelRow,
  NotificationRow,
  PermissionRow,
  ProfileRow,
  ProjectRow,
  ProjectStatusRow,
  SavedFilterRow,
  SprintRow,
  StatusCategory,
  WorkspaceRole,
  WorkspaceRow,
} from './database'

export type Profile = ProfileRow
export type Workspace = WorkspaceRow
export type Project = ProjectRow
export type ProjectStatus = ProjectStatusRow
export type Sprint = SprintRow
export type Label = LabelRow
export type Notification = NotificationRow
export type SavedFilter = Omit<SavedFilterRow, 'query'> & { query: IssueFilter }

export type WorkspaceWithRole = Workspace & { role: WorkspaceRole }

export type Member = {
  workspace_id: string
  user_id: string
  role: WorkspaceRole
  created_at: string
  profile: Profile | null
}

export type Team = {
  id: string
  workspace_id: string
  name: string
  description: string | null
  created_by: string
  created_at: string
  updated_at: string
  lead?: Pick<Profile, 'id' | 'full_name' | 'avatar_url' | 'email'> | null
  members?: Member[]
  project_count?: number
}

export type ProjectWithMeta = Project & {
  lead: Pick<Profile, 'id' | 'full_name' | 'avatar_url' | 'email'> | null
  statuses?: ProjectStatus[]
  team?: { id: string; name: string } | null
}

export type RolePermission = {
  role_id: string
  permission_id: string
  permission: Pick<PermissionRow, 'id' | 'key' | 'name' | 'description'> | null
}

export type RoleWithPermissions = {
  id: string
  workspace_id: string
  name: string
  description: string | null
  is_system: boolean
  created_by: string | null
  created_at: string
  updated_at: string
  permissions: PermissionRow[]
}

export type IssueSummary = IssueRow & {
  status: Pick<ProjectStatus, 'id' | 'name' | 'category' | 'color' | 'position'> | null
  assignee: Pick<Profile, 'id' | 'full_name' | 'avatar_url' | 'email'> | null
  reporter: Pick<Profile, 'id' | 'full_name' | 'avatar_url' | 'email'> | null
  project: Pick<Project, 'id' | 'key' | 'name' | 'color'> | null
  labels: Label[]
  sprint: Pick<Sprint, 'id' | 'name' | 'status'> | null
  epic: Pick<IssueRow, 'id' | 'title' | 'issue_number'> | null
  subtask_count: number
  comment_count: number
}

export type Comment = CommentRow & {
  author: Pick<Profile, 'id' | 'full_name' | 'avatar_url' | 'email'> | null
  revision_count: number
}

export type Attachment = AttachmentRow & {
  uploader: Pick<Profile, 'id' | 'full_name' | 'avatar_url'> | null
  signed_url?: string | null
}

export type Activity = ActivityLogRow & {
  actor: Pick<Profile, 'id' | 'full_name' | 'avatar_url'> | null
}

export type Watcher = {
  issue_id: string
  user_id: string
  profile: Pick<Profile, 'id' | 'full_name' | 'avatar_url' | 'email'> | null
}

/** The "JQL-lite" filter model. Every field is optional and ANDed together. */
export type IssueFilter = {
  text?: string
  types?: IssueType[]
  priorities?: IssuePriority[]
  statusIds?: string[]
  statusCategories?: StatusCategory[]
  assigneeIds?: (string | 'unassigned')[]
  reporterIds?: string[]
  labelIds?: string[]
  sprintIds?: (string | 'none' | 'active')[]
  epicIds?: string[]
  dueFrom?: string
  dueTo?: string
  createdFrom?: string
  createdTo?: string
  overdue?: boolean
  sort?: IssueSort
}

export type IssueSort =
  | 'rank'
  | 'created_desc'
  | 'created_asc'
  | 'updated_desc'
  | 'priority'
  | 'due_date'
  | 'story_points'

export const EMPTY_FILTER: IssueFilter = {}

export function isFilterEmpty(filter: IssueFilter): boolean {
  return !countActiveFilters(filter)
}

export function countActiveFilters(filter: IssueFilter): number {
  let count = 0
  if (filter.text?.trim()) count++
  if (filter.types?.length) count++
  if (filter.priorities?.length) count++
  if (filter.statusIds?.length) count++
  if (filter.statusCategories?.length) count++
  if (filter.assigneeIds?.length) count++
  if (filter.reporterIds?.length) count++
  if (filter.labelIds?.length) count++
  if (filter.sprintIds?.length) count++
  if (filter.epicIds?.length) count++
  if (filter.dueFrom || filter.dueTo) count++
  if (filter.createdFrom || filter.createdTo) count++
  if (filter.overdue) count++
  return count
}

/** Result of the burndown computation used by the sprint report. */
export type BurndownPoint = {
  date: string
  label: string
  remaining: number | null
  ideal: number
  completed: number
}

export type VelocityPoint = {
  sprint: string
  committed: number
  completed: number
}
