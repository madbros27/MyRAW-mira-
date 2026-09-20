'use client'

import { Eye, EyeOff } from 'lucide-react'
import Link from 'next/link'
import { useRouter, useSearchParams } from 'next/navigation'
import * as React from 'react'

import { OAuthButtons } from '@/components/auth/oauth-buttons'
import { Button } from '@/components/ui/button'
import { Field, Input } from '@/components/ui/input'
import { Separator, Skeleton } from '@/components/ui/primitives'
import { getSupabaseBrowserClient } from '@/lib/supabase/client'
import { errorMessage } from '@/lib/utils'

/**
 * `useSearchParams` needs a Suspense boundary above it so the shell can be
 * prerendered while the query string is read on the client.
 */
export default function LoginPage() {
  return (
    <React.Suspense fallback={<AuthFormSkeleton />}>
      <LoginForm />
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

function LoginForm() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const next = searchParams.get('next') ?? '/'
  const notice = searchParams.get('notice')

  React.useEffect(() => {
    let ignore = false

    async function redirectIfSystemAdmin() {
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

      if (!ignore && systemAdminProfile) {
        router.replace('/madbros')
      }
    }

    redirectIfSystemAdmin()
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

      const destination = systemAdminProfile ? '/madbros' : next.startsWith('/madbros') ? '/' : next
      router.push(destination)
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
    <>
      <h1 className="text-xl font-semibold">Sign in to MIRA</h1>
      <p className="mt-1 text-sm text-muted-foreground">
        New here?{' '}
        <Link
          href={next !== '/' ? `/signup?next=${encodeURIComponent(next)}` : '/signup'}
          className="font-medium text-primary hover:underline"
        >
          Create an account
        </Link>
      </p>

      {notice === 'password-updated' ? (
        <p className="mt-4 rounded-lg border border-success/30 bg-success-subtle px-3 py-2 text-xs font-medium text-success">
          Your password was updated. Sign in with the new one.
        </p>
      ) : null}

      <form onSubmit={handleSubmit} className="mt-6 space-y-4">
        <Field label="Email" htmlFor="email" required>
          <Input
            id="email"
            type="email"
            autoComplete="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            placeholder="you@company.com"
            required
            autoFocus
          />
        </Field>

        <Field
          label={
            <span className="flex w-full items-center justify-between gap-2">
              <span>Password</span>
              <Link
                href="/forgot-password"
                className="font-normal text-primary hover:underline"
              >
                Forgot it?
              </Link>
            </span>
          }
          htmlFor="password"
          required
        >
          <div className="relative">
            <Input
              id="password"
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
          Sign in
        </Button>
      </form>

      <div className="my-6 flex items-center gap-3">
        <Separator className="flex-1" />
        <span className="text-2xs uppercase tracking-wide text-muted-foreground">or</span>
        <Separator className="flex-1" />
      </div>

      <OAuthButtons next={next} />

      <p className="mt-8 text-2xs leading-relaxed text-muted-foreground">
        MIRA stores your data in your own Supabase project. Row-level security means you only
        ever see workspaces you are a member of.
      </p>
    </>
  )
}
