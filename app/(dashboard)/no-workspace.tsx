'use client'

import { LogOut, Search } from 'lucide-react'
import Link from 'next/link'
import * as React from 'react'

import { Wordmark } from '@/components/layout/logo'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/primitives'

/**
 * Shown when the signed-in account has no workspace membership yet. This is a
 * normal onboarding state for MIRA: users discover projects and request access
 * rather than creating a workspace automatically.
 */
export function NoWorkspace({ email }: { email: string }) {
  return (
    <main className="flex min-h-dvh items-center justify-center bg-canvas p-4">
      <Card className="w-full max-w-lg p-6 shadow-md">
        <Wordmark />

        <h1 className="mt-5 text-lg font-semibold">Discover projects</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          You are signed in as <span className="font-medium text-foreground">{email}</span>, but
          you are not yet a member of a workspace. Browse active projects and submit a join
          request; access is granted after an approved request.
        </p>

        <div className="mt-5 space-y-3">
          <Button asChild variant="primary" className="w-full">
            <Link href="/projects/discover">
              <Search className="size-4" />
              Find projects
            </Link>
          </Button>

          <div className="rounded-xl border border-border bg-surface-raised px-3 py-2 text-xs text-muted-foreground">
            Project access is controlled by membership rules and approval workflows, not by
            automatic workspace creation.
          </div>
        </div>

        <div className="mt-6 flex items-center justify-between gap-3 border-t border-border pt-4">
          <p className="text-xs text-muted-foreground">Need to sign out?</p>
          <form action="/auth/signout" method="post">
            <Button type="submit" variant="ghost" size="sm">
              <LogOut className="size-4" />
              Sign out
            </Button>
          </form>
        </div>
      </Card>
    </main>
  )
}
