import { Header } from './Header'
import { IdleLogout } from '../IdleLogout'

export function Layout({ children }) {
  return (
    <div className="min-h-screen bg-gray-50">
      <IdleLogout />
      <Header />
      <main className="mx-auto max-w-[1600px] px-4 py-6">{children}</main>
    </div>
  )
}
