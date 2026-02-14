import { Header } from './Header'
import { IdleLogout } from '../IdleLogout'
import { useTheme } from '../../contexts/ThemeContext'

export function Layout({ children }) {
  const { isDark } = useTheme()
  return (
    <div
      className={`min-h-screen ${isDark ? 'theme-dark' : 'bg-gray-50 text-gray-900'} dark:bg-gray-900 dark:text-gray-100`}
      style={isDark ? { backgroundColor: '#111827', color: '#e5e7eb' } : undefined}
    >
      <IdleLogout />
      <Header />
      <main className="mx-auto max-w-[1600px] px-4 py-6">{children}</main>
    </div>
  )
}
