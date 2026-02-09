import { Routes, Route, Navigate } from 'react-router-dom'
import { AuthGuard } from './components/AuthGuard'
import { Login } from './pages/Login'
import { Dashboard } from './pages/Dashboard'
import { QuotesList } from './pages/QuotesList'
import { QuoteDetail } from './pages/QuoteDetail'
import { JobsBoard } from './pages/JobsBoard'
import { JobDetail } from './pages/JobDetail'
import { Customers } from './pages/Customers'
import { Vendors } from './pages/Vendors'
import { Settings } from './pages/Settings'

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route element={<AuthGuard />}>
        <Route path="/" element={<Dashboard />} />
        <Route path="/quotes" element={<QuotesList />} />
        <Route path="/quotes/new" element={<QuoteDetail />} />
        <Route path="/quotes/:id" element={<QuoteDetail />} />
        <Route path="/jobs" element={<JobsBoard />} />
        <Route path="/jobs/:id" element={<JobDetail />} />
        <Route path="/customers" element={<Customers />} />
        <Route path="/vendors" element={<Vendors />} />
        <Route path="/settings" element={<Settings />} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}
