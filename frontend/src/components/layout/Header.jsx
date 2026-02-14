import { Link, useLocation, useNavigate } from 'react-router-dom'
import { pb } from '../../lib/pocketbase'
import { useTheme } from '../../contexts/ThemeContext'

const fullNav = [
  { to: '/', label: 'Dashboard' },
  { to: '/quotes', label: 'Quotes' },
  { to: '/jobs', label: 'Jobs' },
  { to: '/customers', label: 'Customers' },
  { to: '/vendors', label: 'Vendors' },
  { to: '/settings', label: 'Settings' },
]

export function Header() {
  const location = useLocation()
  const navigate = useNavigate()
  const { isDark } = useTheme()
  const isAuth = pb.authStore.isValid
  const isJobsOnly = pb.authStore.model?.role === 'jobs_only'
  const nav = isJobsOnly ? fullNav.filter((item) => item.to !== '/quotes') : fullNav

  const handleLogout = () => {
    pb.authStore.clear()
    navigate('/login', { replace: true })
  }

  return (
    <header
      className="sticky top-0 z-10 border-b border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800"
      style={isDark ? { backgroundColor: '#1f2937', borderColor: '#374151', color: '#e5e7eb' } : undefined}
    >
      <div className="mx-auto flex h-14 max-w-[1600px] items-center justify-between px-4">
        <Link to="/" className="text-lg font-bold bg-gradient-to-r from-primary-from to-primary-to bg-clip-text text-transparent">
          DharmaCore
        </Link>
        <nav className="flex items-center gap-4">
          {nav.map(({ to, label }) => (
            <Link
              key={to}
              to={to}
              className={
                location.pathname === to || (to !== '/' && location.pathname.startsWith(to))
                  ? 'font-medium text-primary-from dark:text-primary-from'
                  : 'text-gray-600 hover:text-gray-900 dark:text-gray-300 dark:hover:text-white'
              }
            >
              {label}
            </Link>
          ))}
          {isAuth && (
            <button
              type="button"
              onClick={handleLogout}
              className="text-gray-600 hover:text-gray-900 dark:text-gray-300 dark:hover:text-white"
            >
              Logout
            </button>
          )}
        </nav>
      </div>
    </header>
  )
}
