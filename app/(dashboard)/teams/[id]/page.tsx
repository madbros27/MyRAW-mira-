import { TeamDetailClient } from '@/components/teams/team-detail'

export default async function TeamDetailPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params
  return <TeamDetailClient teamId={id} />
}
