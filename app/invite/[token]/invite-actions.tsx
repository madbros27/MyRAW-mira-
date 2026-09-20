'use client'

import { useRouter } from 'next/navigation'
import * as React from 'react'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import { getSupabaseBrowserClient } from '@/lib/supabase/client'
import { errorMessage } from '@/lib/utils'

export function InviteActions({ token }: { token: string }) {
  const router = useRouter()
  const [pending, setPending] = React.useState(false)

  async function accept() {
    setPending(true)
    try {
      const supabase = getSupabaseBrowserClient()
      const { data: projectId, error } = await supabase.rpc('accept_project_invitation', {
        p_token: token,
      })
      if (error) throw error

      const { data: project, error: projectError } = await supabase
        .from('projects')
        .select('key')
        .eq('id', projectId)
        .single()
      if (projectError) throw projectError

      toast.success('You joined the project.')
      router.push(`/projects/${project.key}/board`)
      router.refresh()
    } catch (caught) {
      toast.error(errorMessage(caught, 'Unable to accept this invitation'))
      setPending(false)
    }
  }

  return (
    <div className="mt-6">
      <Button type="button" variant="primary" size="lg" className="w-full" loading={pending} onClick={accept}>
        Accept invitation
      </Button>
    </div>
  )
}
