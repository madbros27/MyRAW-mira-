/**
 * Session refresh + route protection, run by `middleware.ts` on every request.
 *
 * The cookie dance matters: Supabase may rotate the access token during
 * `getUser()`, and those refreshed cookies have to be written onto the
 * response that is actually returned — including redirect responses.
 */

import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

import { getSupabaseAnonKey, getSupabaseUrl, isSupabaseConfigured } from './env'
import type { Database } from '@/lib/types/database'

/** Paths reachable without a session. */
const PUBLIC_PATHS = [
  '/login',
  '/signup',
  '/madbros/login',
  '/forgot-password',
  '/reset-password',
  '/auth/callback',
  '/auth/confirm',
  '/setup',
]

function isPublicPath(pathname: string) {
  return PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(`${p}/`))
}

export async function updateSession(request: NextRequest) {
  // Without credentials there is nothing to protect — send everyone to the
  // setup page, which explains what to configure.
  if (!isSupabaseConfigured()) {
    if (request.nextUrl.pathname === '/setup') return NextResponse.next({ request })
    const url = request.nextUrl.clone()
    url.pathname = '/setup'
    url.search = ''
    return NextResponse.redirect(url)
  }

  let response = NextResponse.next({ request })

  const supabase = createServerClient<Database>(
    getSupabaseUrl(),
    getSupabaseAnonKey(),
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          for (const { name, value } of cookiesToSet) {
            request.cookies.set(name, value)
          }
          response = NextResponse.next({ request })
          for (const { name, value, options } of cookiesToSet) {
            response.cookies.set(name, value, options)
          }
        },
      },
    }
  )

  const {
    data: { user },
  } = await supabase.auth.getUser()

  const { pathname } = request.nextUrl

  const isLegacyAdminPath = pathname === '/admin' || pathname.startsWith('/admin/')
  const isMadbrosPath = pathname === '/madbros' || pathname.startsWith('/madbros/')

  if (!user && isLegacyAdminPath) {
    const url = request.nextUrl.clone()
    url.pathname = '/madbros/login'
    url.search = ''
    return copyCookies(response, NextResponse.redirect(url))
  }

  if (!user && isMadbrosPath && pathname !== '/madbros/login') {
    const url = request.nextUrl.clone()
    url.pathname = '/madbros/login'
    url.search = ''
    return copyCookies(response, NextResponse.redirect(url))
  }

  if (!user && !isPublicPath(pathname)) {
    const url = request.nextUrl.clone()
    url.pathname = '/login'
    url.search = ''
    if (pathname !== '/') url.searchParams.set('next', pathname + request.nextUrl.search)
    return copyCookies(response, NextResponse.redirect(url))
  }

  if (user && isLegacyAdminPath) {
    const url = request.nextUrl.clone()
    url.pathname = '/madbros'
    url.search = ''
    return copyCookies(response, NextResponse.redirect(url))
  }

  if (user && (isMadbrosPath || pathname === '/madbros/login')) {
    const { data: adminProfile, error } = await supabase
      .from('profiles')
      .select('id')
      .eq('id', user.id)
      .eq('is_system_admin', true)
      .maybeSingle()

    if (pathname === '/madbros/login') {
      if (!error && adminProfile) {
        const url = request.nextUrl.clone()
        url.pathname = '/madbros'
        url.search = ''
        return copyCookies(response, NextResponse.redirect(url))
      }

      const url = request.nextUrl.clone()
      url.pathname = '/'
      url.search = ''
      return copyCookies(response, NextResponse.redirect(url))
    }

    if (isMadbrosPath && pathname !== '/madbros/login' && (!adminProfile || error)) {
      const url = request.nextUrl.clone()
      url.pathname = '/'
      url.search = ''
      return copyCookies(response, NextResponse.redirect(url))
    }
  }

  if (user && (pathname === '/login' || pathname === '/signup')) {
    const { data: adminProfile, error } = await supabase
      .from('profiles')
      .select('id')
      .eq('id', user.id)
      .eq('is_system_admin', true)
      .maybeSingle()

    if (!error && adminProfile) {
      const url = request.nextUrl.clone()
      url.pathname = '/madbros'
      url.search = ''
      return copyCookies(response, NextResponse.redirect(url))
    }

    const url = request.nextUrl.clone()
    url.pathname = '/'
    url.search = ''
    return copyCookies(response, NextResponse.redirect(url))
  }

  return response
}

/** Carry any refreshed auth cookies onto a different response object. */
function copyCookies(from: NextResponse, to: NextResponse) {
  for (const cookie of from.cookies.getAll()) {
    to.cookies.set(cookie)
  }
  return to
}
