import { Link, useLocation, useNavigate } from 'react-router-dom'
import { pb } from '../../lib/pocketbase'

const nav = [
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
  const isAuth = pb.authStore.isValid

  const handleLogout = () => {
    pb.authStore.clear()
    navigate('/login', { replace: true })
  }

  return (
    <header className="border-b border-gray-200 bg-white">
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
                  ? 'font-medium text-primary-from'
                  : 'text-gray-600 hover:text-gray-900'
              }
            >
              {label}
            </Link>
          ))}
          {isAuth && (
            <button
              type="button"
              onClick={handleLogout}
              className="text-sm text-gray-600 hover:text-gray-900"
            >
              Logout
            </button>
          )}
        </nav>
      </div>
    </header>
  )
}
