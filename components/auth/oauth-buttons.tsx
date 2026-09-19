'use client'

import * as React from 'react'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import { getSupabaseBrowserClient } from '@/lib/supabase/client'
import { getSiteUrl } from '@/lib/supabase/env'
import { errorMessage } from '@/lib/utils'

/** Inline Google mark — no external asset, so it works offline and in CSP. */
function GoogleIcon() {
  return (
    <svg viewBox="0 0 18 18" aria-hidden className="size-4">
      <path
        fill="#4285F4"
        d="M17.64 9.2c0-.64-.06-1.25-.16-1.84H9v3.48h4.84a4.14 4.14 0 0 1-1.8 2.71v2.26h2.91c1.7-1.57 2.69-3.88 2.69-6.61Z"
      />
      <path
        fill="#34A853"
        d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.91-2.26c-.81.54-1.84.86-3.05.86-2.34 0-4.32-1.58-5.03-3.71H.96v2.34A9 9 0 0 0 9 18Z"
      />
      <path
        fill="#FBBC05"
        d="M3.97 10.71a5.41 5.41 0 0 1 0-3.42V4.95H.96a9 9 0 0 0 0 8.1l3.01-2.34Z"
      />
      <path
        fill="#EA4335"
        d="M9 3.58c1.32 0 2.51.45 3.44 1.35l2.58-2.59C13.46.89 11.43 0 9 0A9 9 0 0 0 .96 4.95l3.01 2.34C4.68 5.16 6.66 3.58 9 3.58Z"
      />
    </svg>
  )
}

export function OAuthButtons({ next }: { next?: string }) {
  const [pending, setPending] = React.useState(false)

  async function signIn() {
    setPending(true)
    const supabase = getSupabaseBrowserClient()
    const redirectTo = `${getSiteUrl()}/auth/callback${
      next ? `?next=${encodeURIComponent(next)}` : ''
    }`

    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo },
    })

    if (error) {
      setPending(false)
      toast.error(
        errorMessage(
          error,
          'Could not start Google sign-in. Enable the provider in Supabase → Authentication → Providers.'
        )
      )
    }
    // On success the browser is redirected, so the pending state stays set.
  }

  return (
    <div className="grid gap-2">
      <Button
        type="button"
        variant="secondary"
        onClick={signIn}
        loading={pending}
      >
        <GoogleIcon />
        Google
      </Button>
    </div>
  )
}
