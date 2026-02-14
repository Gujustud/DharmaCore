import { createContext, useContext, useEffect, useState } from 'react'

const STORAGE_KEY = 'darkMode'

const ThemeContext = createContext({
  isDark: false,
  setDark: () => {},
})

export function useTheme() {
  const ctx = useContext(ThemeContext)
  if (!ctx) throw new Error('useTheme must be used within ThemeProvider')
  return ctx
}

function applyDark(isDark) {
  if (typeof document === 'undefined') return
  const root = document.documentElement
  if (isDark) {
    root.classList.add('dark')
  } else {
    root.classList.remove('dark')
  }
  try {
    localStorage.setItem(STORAGE_KEY, isDark ? 'true' : 'false')
  } catch (_) {}
}

export function ThemeProvider({ children }) {
  const [isDark, setDarkState] = useState(() => {
    if (typeof window === 'undefined') return false
    try {
      return localStorage.getItem(STORAGE_KEY) === 'true'
    } catch {
      return false
    }
  })

  useEffect(() => {
    applyDark(isDark)
  }, [isDark])

  const setDark = (value) => {
    const next = typeof value === 'function' ? value(isDark) : value
    applyDark(next)
    setDarkState(next)
  }

  return (
    <ThemeContext.Provider value={{ isDark, setDark }}>
      {children}
    </ThemeContext.Provider>
  )
}
