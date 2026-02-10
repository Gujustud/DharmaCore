import { Navigate, useLocation, Outlet } from 'react-router-dom'
import { pb } from '../lib/pocketbase'

function isJobsOnly() {
  return pb.authStore.model?.role === 'jobs_only'
}

export function AuthGuard() {
  const location = useLocation()
  const isAuth = pb.authStore.isValid

  if (!isAuth) {
    return <Navigate to="/login" state={{ from: location }} replace />
  }

  if (isJobsOnly() && (location.pathname === '/quotes' || location.pathname.startsWith('/quotes/'))) {
    return <Navigate to="/jobs" replace />
  }

  return <Outlet />
}
