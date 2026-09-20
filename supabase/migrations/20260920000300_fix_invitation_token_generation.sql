create or replace function public.create_project_invitation(
  p_project_id uuid,
  p_invited_email text,
  p_team_id uuid default null,
  p_expires_at timestamptz default (now() + interval '7 days')
)
returns public.project_invitations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_invitation public.project_invitations;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not (
    public.is_project_owner(p_project_id, auth.uid())
    or public.is_system_admin(auth.uid())
    or (p_team_id is not null and public.can_manage_team(p_team_id, auth.uid()))
  ) then
    raise exception 'You cannot create an invitation for this project.';
  end if;

  if p_team_id is not null and not exists (
    select 1 from public.teams t
    where t.id = p_team_id
      and (t.project_id = p_project_id or exists (
        select 1 from public.projects p where p.id = p_project_id and p.team_id = t.id
      ))
  ) then
    raise exception 'Team does not belong to this project.';
  end if;

  insert into public.project_invitations (
    project_id, team_id, invited_email, invited_by, token, expires_at
  )
  values (
    p_project_id,
    p_team_id,
    lower(trim(p_invited_email)),
    auth.uid(),
    encode(extensions.gen_random_bytes(32), 'hex'),
    least(p_expires_at, now() + interval '30 days')
  )
  returning * into v_invitation;

  return v_invitation;
end;
$$;

grant execute on function public.create_project_invitation(uuid, text, uuid, timestamptz) to authenticated;
