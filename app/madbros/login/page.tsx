'use client'

import { Eye, EyeOff } from 'lucide-react'
import { useRouter } from 'next/navigation'
import * as React from 'react'

import { OAuthButtons } from '@/components/auth/oauth-buttons'
import { Button } from '@/components/ui/button'
import { Field, Input } from '@/components/ui/input'
import { Separator, Skeleton } from '@/components/ui/primitives'
import { getSupabaseBrowserClient } from '@/lib/supabase/client'
import { errorMessage } from '@/lib/utils'

export default function MadbrosLoginPage() {
  return (
    <React.Suspense fallback={<AuthFormSkeleton />}>
      <MadbrosLoginForm />
    </React.Suspense>
  )
}

function AuthFormSkeleton() {
  return (
    <div className="space-y-4">
      <Skeleton className="h-6 w-40" />
      <Skeleton className="h-3 w-56" />
      <Skeleton className="mt-6 h-16 w-full rounded-lg" />
      <Skeleton className="h-16 w-full rounded-lg" />
      <Skeleton className="h-10 w-full rounded-lg" />
    </div>
  )
}

function MadbrosLoginForm() {
  const router = useRouter()

  React.useEffect(() => {
    let ignore = false

    async function redirectIfAuthenticated() {
      const supabase = getSupabaseBrowserClient()
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user || ignore) return

      const { data: systemAdminProfile } = await supabase
        .from('profiles')
        .select('id')
        .eq('id', user.id)
        .eq('is_system_admin', true)
        .maybeSingle()

      if (!ignore) {
        router.replace(systemAdminProfile ? '/madbros' : '/')
      }
    }

    redirectIfAuthenticated()
    return () => {
      ignore = true
    }
  }, [router])

  const [email, setEmail] = React.useState('')
  const [password, setPassword] = React.useState('')
  const [showPassword, setShowPassword] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)
  const [pending, setPending] = React.useState(false)

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault()
    setError(null)
    setPending(true)

    try {
      const supabase = getSupabaseBrowserClient()
      const { error: signInError } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      })
      if (signInError) throw signInError

      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('Authentication required.')
      }

      const { data: systemAdminProfile } = await supabase
        .from('profiles')
        .select('id')
        .eq('id', user.id)
        .eq('is_system_admin', true)
        .maybeSingle()

      if (!systemAdminProfile) {
        await supabase.auth.signOut()
        setError('This account is not authorized for the Madbros system login. Please use the regular MIRA sign-in.')
        setPending(false)
        return
      }

      router.push('/madbros')
      router.refresh()
    } catch (caught) {
      const message = errorMessage(caught, 'Could not sign you in')
      setError(
        /invalid login credentials/i.test(message)
          ? 'That email and password combination does not match an account.'
          : /email not confirmed/i.test(message)
            ? 'Confirm your email address first — check your inbox for the link.'
            : message
      )
      setPending(false)
    }
  }

  return (
    <main className="flex min-h-dvh items-center justify-center bg-canvas p-4">
      <div className="w-full max-w-md rounded-2xl border border-border bg-background p-6 shadow-md">
        <p className="text-xs font-medium uppercase tracking-[0.2em] text-muted-foreground">
          Madbros admin
        </p>
        <h1 className="mt-3 text-xl font-semibold">System administrator sign in</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Use your MIRA account to access the global system administration console.
        </p>

        <form onSubmit={handleSubmit} className="mt-6 space-y-4">
          <Field label="Email" htmlFor="madbros-email" required>
            <Input
              id="madbros-email"
              type="email"
              autoComplete="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="admin@yourmira.app"
              required
              autoFocus
            />
          </Field>

          <Field label="Password" htmlFor="madbros-password" required>
            <div className="relative">
              <Input
                id="madbros-password"
                type={showPassword ? 'text' : 'password'}
                autoComplete="current-password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                placeholder="••••••••"
                required
                className="pr-9"
              />
              <button
                type="button"
                onClick={() => setShowPassword((prev) => !prev)}
                className="absolute right-1.5 top-1/2 inline-flex size-6 -translate-y-1/2 items-center justify-center rounded text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
                aria-label={showPassword ? 'Hide password' : 'Show password'}
              >
                {showPassword ? <EyeOff className="size-3.5" /> : <Eye className="size-3.5" />}
              </button>
            </div>
          </Field>

          {error ? (
            <p
              role="alert"
              className="rounded-lg border border-destructive/30 bg-destructive-subtle px-3 py-2 text-xs font-medium text-destructive"
            >
              {error}
            </p>
          ) : null}

          <Button type="submit" variant="primary" size="lg" className="w-full" loading={pending}>
            Sign in to Madbros
          </Button>
        </form>

        <div className="my-6 flex items-center gap-3">
          <Separator className="flex-1" />
          <span className="text-2xs uppercase tracking-wide text-muted-foreground">or</span>
          <Separator className="flex-1" />
        </div>

        <OAuthButtons next="/madbros" />
      </div>
    </main>
  )
}
