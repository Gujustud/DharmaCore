import { Navigate, useLocation, Outlet } from 'react-router-dom'
import { pb } from '../lib/pocketbase'

export function AuthGuard() {
  const location = useLocation()
  const isAuth = pb.authStore.isValid

  if (!isAuth) {
    return <Navigate to="/login" state={{ from: location }} replace />
  }

  return <Outlet />
}
