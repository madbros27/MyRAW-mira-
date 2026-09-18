/**
 * Environment access for the Supabase connection.
 *
 * Reading the variables in exactly one place means a missing value produces a
 * single, actionable error instead of an opaque "fetch failed" deep inside the
 * client.
 */

const MISSING = (name: string) =>
  `[MIRA] Missing environment variable ${name}. ` +
  `Copy .env.example to .env.local and fill in the values from ` +
  `Supabase Dashboard -> Project Settings -> API, then restart the dev server.`

export function getSupabaseUrl(): string {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!url || url.startsWith('<')) throw new Error(MISSING('NEXT_PUBLIC_SUPABASE_URL'))
  return url
}

export function getSupabaseAnonKey(): string {
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!key || key.startsWith('<')) throw new Error(MISSING('NEXT_PUBLIC_SUPABASE_ANON_KEY'))
  return key
}

/** Server-only. Bypasses RLS — never import this from a Client Component. */
export function getSupabaseServiceRoleKey(): string {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!key || key.startsWith('<')) throw new Error(MISSING('SUPABASE_SERVICE_ROLE_KEY'))
  return key
}

export function isSupabaseConfigured(): boolean {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  return Boolean(url && key && !url.startsWith('<') && !key.startsWith('<'))
}

/** Absolute origin of this deployment, used for auth redirect URLs. */
export function getSiteUrl(): string {
  const explicit = process.env.NEXT_PUBLIC_SITE_URL
  if (explicit) return explicit.replace(/\/$/, '')

  const vercel = process.env.NEXT_PUBLIC_VERCEL_URL ?? process.env.VERCEL_URL
  if (vercel) return `https://${vercel.replace(/\/$/, '')}`

  if (typeof window !== 'undefined') return window.location.origin
  return 'http://localhost:3000'
}
