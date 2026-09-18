/**
 * Database types for the MIRA schema.
 *
 * Hand-maintained to mirror `supabase/migrations`. Once your project is linked
 * you can regenerate this file instead:
 *
 *   npm run db:types
 */

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type WorkspaceRole = 'admin' | 'lead' | 'member' | 'viewer'
export type IssueType = 'epic' | 'story' | 'task' | 'bug' | 'subtask'
export type IssuePriority = 'highest' | 'high' | 'medium' | 'low' | 'lowest'
export type StatusCategory = 'todo' | 'in_progress' | 'done'
export type SprintStatus = 'planned' | 'active' | 'completed'
export type NotificationType =
  | 'assigned'
  | 'mentioned'
  | 'status_changed'
  | 'commented'
  | 'issue_created'
  | 'sprint_started'
  | 'sprint_completed'
  | 'invited'
export type InviteStatus = 'pending' | 'accepted' | 'revoked' | 'expired'

type Timestamps = {
  created_at: string
  updated_at: string
}

export type ProfileRow = Timestamps & {
  id: string
  email: string
  full_name: string | null
  avatar_url: string | null
  job_title: string | null
  timezone: string | null
}

export type WorkspaceRow = Timestamps & {
  id: string
  name: string
  slug: string
  description: string | null
  avatar_url: string | null
  owner_id: string
}

export type WorkspaceMemberRow = {
  workspace_id: string
  user_id: string
  role: WorkspaceRole
  created_at: string
}

export type ProjectRow = Timestamps & {
  id: string
  workspace_id: string
  name: string
  key: string
  description: string | null
  lead_id: string | null
  icon: string
  color: string
  is_archived: boolean
  issue_counter: number
}

export type ProjectStatusRow = {
  id: string
  project_id: string
  name: string
  category: StatusCategory
  color: string
  position: number
  wip_limit: number | null
  created_at: string
}

export type StatusTransitionRow = {
  id: string
  project_id: string
  from_status_id: string
  to_status_id: string
}

export type SprintRow = Timestamps & {
  id: string
  project_id: string
  name: string
  goal: string | null
  start_date: string | null
  end_date: string | null
  status: SprintStatus
  retrospective: string | null
  committed_points: number | null
  completed_points: number | null
  completed_at: string | null
}

export type IssueRow = Timestamps & {
  id: string
  project_id: string
  issue_number: number
  type: IssueType
  title: string
  description: string | null
  status_id: string
  priority: IssuePriority
  assignee_id: string | null
  reporter_id: string | null
  epic_id: string | null
  parent_id: string | null
  sprint_id: string | null
  story_points: number | null
  due_date: string | null
  board_position: number
  backlog_position: number
  resolved_at: string | null
}

export type LabelRow = {
  id: string
  project_id: string
  name: string
  color: string
  created_at: string
}

export type IssueLabelRow = {
  issue_id: string
  label_id: string
}

export type CommentRow = Timestamps & {
  id: string
  issue_id: string
  author_id: string | null
  body: string
  is_edited: boolean
}

export type CommentRevisionRow = {
  id: string
  comment_id: string
  body: string
  editor_id: string | null
  created_at: string
}

export type AttachmentRow = {
  id: string
  issue_id: string
  storage_path: string
  file_name: string
  file_size: number
  mime_type: string | null
  uploaded_by: string | null
  created_at: string
}

export type ActivityLogRow = {
  id: string
  issue_id: string
  actor_id: string | null
  action: string
  field_changed: string | null
  old_value: string | null
  new_value: string | null
  created_at: string
}

export type WatcherRow = {
  issue_id: string
  user_id: string
  created_at: string
}

export type NotificationRow = {
  id: string
  user_id: string
  workspace_id: string | null
  project_id: string | null
  issue_id: string | null
  actor_id: string | null
  type: NotificationType
  title: string
  body: string | null
  payload: Json
  is_read: boolean
  created_at: string
}

export type SavedFilterRow = Timestamps & {
  id: string
  workspace_id: string
  project_id: string | null
  owner_id: string
  name: string
  query: Json
  is_shared: boolean
}

export type WorkspaceInviteRow = {
  id: string
  workspace_id: string
  email: string
  role: WorkspaceRole
  invited_by: string | null
  token: string
  status: InviteStatus
  expires_at: string
  accepted_at: string | null
  created_at: string
}

/** Helper that turns a Row type into the shape accepted by `.insert()`. */
type Insertable<TRow, TRequired extends keyof TRow> = Partial<TRow> &
  Pick<TRow, TRequired>

type Table<TRow, TRequired extends keyof TRow> = {
  Row: TRow
  Insert: Insertable<TRow, TRequired>
  Update: Partial<TRow>
  Relationships: []
}

export type Database = {
  public: {
    Tables: {
      profiles: Table<ProfileRow, 'id' | 'email'>
      workspaces: Table<WorkspaceRow, 'name' | 'slug' | 'owner_id'>
      workspace_members: Table<WorkspaceMemberRow, 'workspace_id' | 'user_id'>
      projects: Table<ProjectRow, 'workspace_id' | 'name' | 'key'>
      project_statuses: Table<ProjectStatusRow, 'project_id' | 'name'>
      status_transitions: Table<
        StatusTransitionRow,
        'project_id' | 'from_status_id' | 'to_status_id'
      >
      sprints: Table<SprintRow, 'project_id' | 'name'>
      // `status_id`, `issue_number` and `reporter_id` are filled in by the
      // `assign_issue_defaults` trigger, so they are optional on insert.
      issues: Table<IssueRow, 'project_id' | 'title'>
      labels: Table<LabelRow, 'project_id' | 'name'>
      issue_labels: Table<IssueLabelRow, 'issue_id' | 'label_id'>
      comments: Table<CommentRow, 'issue_id' | 'body'>
      comment_revisions: Table<CommentRevisionRow, 'comment_id' | 'body'>
      attachments: Table<AttachmentRow, 'issue_id' | 'storage_path' | 'file_name'>
      activity_log: Table<ActivityLogRow, 'issue_id' | 'action'>
      watchers: Table<WatcherRow, 'issue_id' | 'user_id'>
      notifications: Table<NotificationRow, 'user_id' | 'type' | 'title'>
      saved_filters: Table<SavedFilterRow, 'workspace_id' | 'owner_id' | 'name'>
      workspace_invites: Table<WorkspaceInviteRow, 'workspace_id' | 'email'>
    }
    /*
     * MIRA has no database views. This must be an empty *object* type rather
     * than `Record<string, never>`: PostgREST's type helpers intersect
     * `Tables & Views`, and an index signature of `never` would collapse every
     * table type to `never`.
     */
    Views: { [_ in never]: never }
    Functions: {
      create_workspace: {
        Args: { p_name: string; p_slug?: string | null }
        Returns: WorkspaceRow
      }
      create_project: {
        Args: {
          p_workspace: string
          p_name: string
          p_key: string
          p_description?: string | null
          p_lead?: string | null
          p_icon?: string
          p_color?: string
        }
        Returns: ProjectRow
      }
      start_sprint: {
        Args: { p_sprint: string; p_start?: string; p_end?: string | null }
        Returns: SprintRow
      }
      complete_sprint: {
        Args: { p_sprint: string; p_target_sprint?: string | null }
        Returns: SprintRow
      }
      global_search: {
        Args: { p_workspace: string; p_query: string; p_limit?: number }
        Returns: SearchResultRow[]
      }
      mark_all_notifications_read: {
        Args: { p_workspace?: string | null }
        Returns: number
      }
      accept_invite: {
        Args: { p_token: string }
        Returns: string
      }
      seed_demo_for_email: {
        Args: { p_email: string }
        Returns: string
      }
    }
    Enums: {
      workspace_role: WorkspaceRole
      issue_type: IssueType
      issue_priority: IssuePriority
      status_category: StatusCategory
      sprint_status: SprintStatus
      notification_type: NotificationType
      invite_status: InviteStatus
    }
    CompositeTypes: { [_ in never]: never }
  }
}

export type SearchResultRow = {
  kind: 'issue' | 'project' | 'comment'
  id: string
  project_id: string
  project_key: string
  project_name: string
  issue_id: string | null
  issue_number: number | null
  title: string
  snippet: string | null
  rank: number
}
