'use client'

/**
 * Global keyboard layer.
 *
 * Nothing fires while focus is in a field or while a dialog has focus, so
 * typing "c" in a comment box never opens the create dialog.
 */

import { useRouter } from 'next/navigation'
import * as React from 'react'

import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Kbd } from '@/components/ui/primitives'
import { useWorkspaceContext } from '@/components/providers/workspace-provider'
import { can } from '@/lib/permissions'
import { useUiStore } from '@/lib/store/ui-store'

const SHORTCUTS: { keys: string[]; label: string }[] = [
  { keys: ['c'], label: 'Create issue' },
  { keys: ['/'], label: 'Search' },
  { keys: ['⌘', 'K'], label: 'Command palette' },
  { keys: ['g', 'h'], label: 'Go to home' },
  { keys: ['g', 'm'], label: 'Go to my work' },
  { keys: ['g', 'n'], label: 'Go to notifications' },
  { keys: ['g', 'p'], label: 'Go to projects' },
  { keys: ['?'], label: 'This help' },
  { keys: ['Esc'], label: 'Close dialogs' },
  { keys: ['Space'], label: 'Pick up / drop a card (while focused)' },
]

function isTypingTarget(target: EventTarget | null) {
  if (!(target instanceof HTMLElement)) return false
  const tag = target.tagName
  return (
    tag === 'INPUT' ||
    tag === 'TEXTAREA' ||
    tag === 'SELECT' ||
    target.isContentEditable ||
    target.getAttribute('role') === 'textbox'
  )
}

export function ShortcutLayer() {
  const router = useRouter()
  const { role } = useWorkspaceContext()
  const openCreateIssue = useUiStore((state) => state.openCreateIssue)
  const setCommandOpen = useUiStore((state) => state.setCommandOpen)
  const shortcutsOpen = useUiStore((state) => state.shortcutsOpen)
  const setShortcutsOpen = useUiStore((state) => state.setShortcutsOpen)

  // "g" then a letter — a leader sequence, cleared after a second.
  const leader = React.useRef<number | null>(null)

  React.useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      const meta = event.metaKey || event.ctrlKey

      if (meta && event.key.toLowerCase() === 'k') {
        event.preventDefault()
        setCommandOpen(true)
        return
      }

      if (isTypingTarget(event.target) || event.altKey) return

      // A Radix dialog marks the rest of the page inert; skip while one is up.
      if (document.body.hasAttribute('data-scroll-locked')) return

      const key = event.key

      if (leader.current && Date.now() - leader.current < 1000) {
        const destinations: Record<string, string> = {
          h: '/',
          m: '/my-work',
          n: '/notifications',
          p: '/projects',
          s: '/search',
        }
        const href = destinations[key.toLowerCase()]
        leader.current = null
        if (href) {
          event.preventDefault()
          router.push(href)
          return
        }
      }

      if (key.toLowerCase() === 'g' && !meta) {
        leader.current = Date.now()
        return
      }

      if (key === '/' && !meta) {
        event.preventDefault()
        setCommandOpen(true)
        return
      }

      if (key === '?') {
        event.preventDefault()
        setShortcutsOpen(true)
        return
      }

      if (key.toLowerCase() === 'c' && !meta && can.writeIssues(role)) {
        event.preventDefault()
        openCreateIssue()
      }
    }

    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [openCreateIssue, role, router, setCommandOpen, setShortcutsOpen])

  return (
    <Dialog open={shortcutsOpen} onOpenChange={setShortcutsOpen}>
      <DialogContent size="sm">
        <DialogHeader>
          <DialogTitle>Keyboard shortcuts</DialogTitle>
          <DialogDescription>
            Shortcuts are ignored while you are typing in a field.
          </DialogDescription>
        </DialogHeader>
        <DialogBody>
          <dl className="divide-y divide-border">
            {SHORTCUTS.map((shortcut) => (
              <div
                key={shortcut.label}
                className="flex items-center justify-between gap-4 py-2"
              >
                <dt className="text-sm">{shortcut.label}</dt>
                <dd className="flex shrink-0 gap-1">
                  {shortcut.keys.map((key) => (
                    <Kbd key={key}>{key}</Kbd>
                  ))}
                </dd>
              </div>
            ))}
          </dl>
        </DialogBody>
      </DialogContent>
    </Dialog>
  )
}
