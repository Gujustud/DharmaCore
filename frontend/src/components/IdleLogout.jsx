import { useEffect, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { pb } from '../lib/pocketbase'
import { getSettings } from '../lib/api'

const ACTIVITY_EVENTS = ['mousedown', 'mousemove', 'keydown', 'scroll', 'touchstart']

export function IdleLogout() {
  const navigate = useNavigate()
  const timeoutRef = useRef(null)
  const cleanupRef = useRef(null)

  useEffect(() => {
    let cancelled = false

    getSettings().then((settings) => {
      if (cancelled) return
      const minutes = Number(settings?.auto_logout_minutes ?? 0)
      if (minutes <= 0) return

      const schedule = () => {
        if (timeoutRef.current) clearTimeout(timeoutRef.current)
        timeoutRef.current = setTimeout(() => {
          pb.authStore.clear()
          navigate('/login', { replace: true })
        }, minutes * 60 * 1000)
      }

      schedule()
      ACTIVITY_EVENTS.forEach((ev) => window.addEventListener(ev, schedule))
      cleanupRef.current = () => {
        if (timeoutRef.current) clearTimeout(timeoutRef.current)
        ACTIVITY_EVENTS.forEach((ev) => window.removeEventListener(ev, schedule))
      }
    })

    return () => {
      cancelled = true
      cleanupRef.current?.()
      cleanupRef.current = null
    }
  }, [navigate])

  return null
}
