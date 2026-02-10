import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { startOfMonth, endOfMonth, isWithinInterval, parseISO, format } from 'date-fns'
import { Layout } from '../components/layout/Layout'
import { Card } from '../components/ui/Card'
import { Button } from '../components/ui/Button'
import { Badge } from '../components/ui/Badge'
import { getQuotes, getJobs } from '../lib/api'
import { pb } from '../lib/pocketbase'

function formatCurrency(n) {
  if (n == null || n === '') return '—'
  const num = Number(n)
  if (Number.isNaN(num)) return '—'
  return new Intl.NumberFormat('en-CA', {
    style: 'currency',
    currency: 'CAD',
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(num)
}

function toDate(s) {
  if (!s) return null
  try {
    return typeof s === 'string' ? parseISO(s) : s
  } catch {
    return null
  }
}

const JOB_STATUS_LABELS = {
  planning: 'Planning',
  in_progress: 'In progress',
  done: 'Done',
  cancelled: 'Cancelled',
}
function jobStatusLabel(status) {
  return JOB_STATUS_LABELS[status] ?? status ?? '—'
}

export function Dashboard() {
  const isJobsOnly = pb.authStore.model?.role === 'jobs_only'
  const [quotes, setQuotes] = useState([])
  const [jobs, setJobs] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    const promises = isJobsOnly ? [getJobs()] : [getQuotes(), getJobs()]
    Promise.all(promises)
      .then((results) => {
        if (cancelled) return
        const quotesRes = isJobsOnly ? null : results[0]
        const jobsRes = isJobsOnly ? results[0] : results[1]
        if (!isJobsOnly && quotesRes) {
          const quoteItems = quotesRes?.items ?? []
          quoteItems.sort((a, b) => new Date(b.created || 0) - new Date(a.created || 0))
          setQuotes(quoteItems)
        }
        const jobItems = jobsRes?.items ?? []
        jobItems.sort((a, b) => new Date(b.updated || 0) - new Date(a.updated || 0))
        setJobs(jobItems)
      })
      .catch((e) => {
        if (e?.status !== 0 && !e?.message?.includes('autocancelled')) console.error(e)
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => { cancelled = true }
  }, [isJobsOnly])

  const now = new Date()
  const monthStart = startOfMonth(now)
  const monthEnd = endOfMonth(now)

  const quotesThisMonth = quotes.filter((q) => {
    const d = toDate(q.created)
    return d && isWithinInterval(d, { start: monthStart, end: monthEnd })
  })
  const wonQuotes = quotes.filter((q) => q.status === 'won')
  const wonThisMonth = wonQuotes.filter((q) => {
    const d = toDate(q.updated)
    return d && isWithinInterval(d, { start: monthStart, end: monthEnd })
  })
  const pendingQuotes = quotes.filter((q) => q.status === 'sent')
  const revenueThisMonth = wonThisMonth.reduce(
    (sum, q) => sum + (Number(q.final_total_cad) || 0),
    0
  )
  const winRate =
    quotes.filter((q) => q.status === 'won' || q.status === 'lost').length > 0
      ? Math.round(
          (wonQuotes.length /
            quotes.filter((q) => q.status === 'won' || q.status === 'lost').length) *
            100
        )
      : 0

  const recentQuotes = [...quotes].sort((a, b) => {
    const ta = new Date(a.created || 0).getTime()
    const tb = new Date(b.created || 0).getTime()
    return tb - ta
  }).slice(0, 10)

  const activeJobs = jobs.filter(
    (j) => j.status === 'planning' || j.status === 'in_progress'
  )

  const customerDisplay = (q) => q.expand?.customer?.company || q.customer_name || '—'

  return (
    <Layout>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">DharmaCore</h1>
          <p className="text-gray-600">Manage your shop operations</p>
        </div>
        {!isJobsOnly && (
          <Link to="/quotes/new">
            <Button>+ New Quote</Button>
          </Link>
        )}
      </div>

      {loading ? (
        <p className="py-4 text-center text-gray-500">Loading…</p>
      ) : (
        <>
          {!isJobsOnly && (
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <Card>
                <p className="text-sm text-gray-600">Quotes this month</p>
                <p className="text-2xl font-bold">{quotesThisMonth.length}</p>
              </Card>
              <Card>
                <p className="text-sm text-gray-600">Won</p>
                <p className="text-2xl font-bold">
                  {wonQuotes.length}
                  {quotes.length > 0 && (
                    <span className="ml-1 text-sm font-normal text-gray-500">
                      ({winRate}% win rate)
                    </span>
                  )}
                </p>
              </Card>
              <Card>
                <p className="text-sm text-gray-600">Pending</p>
                <p className="text-2xl font-bold">{pendingQuotes.length}</p>
              </Card>
              <Card>
                <p className="text-sm text-gray-600">Revenue this month</p>
                <p className="text-2xl font-bold">{formatCurrency(revenueThisMonth)}</p>
              </Card>
            </div>
          )}

          <Card className={isJobsOnly ? '' : 'mt-6'}>
            <h2 className="mb-2 font-semibold">Active Jobs</h2>
            {activeJobs.length === 0 ? (
              <p className="text-sm text-gray-500">
                No active jobs. Jobs appear when a quote is marked Won.
              </p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[400px]">
                  <thead>
                    <tr className="border-b border-gray-200 text-left text-sm text-gray-600">
                      <th className="pb-2 pr-4 font-medium">Job #</th>
                      <th className="pb-2 pr-4 font-medium">Customer</th>
                      <th className="pb-2 pr-4 font-medium">Status</th>
                      <th className="pb-2 font-medium">Ship date</th>
                      <th className="pb-2 font-medium">Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {activeJobs.map((j) => (
                      <tr key={j.id} className="border-b border-gray-100">
                        <td className="py-2 pr-4 font-medium">{j.job_number || '—'}</td>
                        <td className="py-2 pr-4 text-gray-700">
                          {j.expand?.customer?.company || j.customer_name || '—'}
                        </td>
                        <td className="py-2 pr-4">
                          <Badge status={j.status}>{jobStatusLabel(j.status)}</Badge>
                        </td>
                        <td className="py-2 pr-4">
                          {j.ship_date
                            ? format(
                                typeof j.ship_date === 'string'
                                  ? parseISO(j.ship_date)
                                  : j.ship_date,
                                'MMM d'
                              )
                            : '—'}
                        </td>
                        <td className="py-2">
                          <Link to={`/jobs/${j.id}`}>
                            <Button variant="secondary" className="!py-1 !text-sm">
                              View →
                            </Button>
                          </Link>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            <Link to="/jobs" className="mt-3 inline-block text-primary-from hover:underline">
              Jobs Board →
            </Link>
          </Card>

          {!isJobsOnly && (
            <Card className="mt-4">
              <h2 className="mb-2 font-semibold">Recent Quotes</h2>
              {recentQuotes.length === 0 ? (
                <p className="text-sm text-gray-500">No quotes yet. Create one from Quotes.</p>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full min-w-[400px]">
                    <thead>
                      <tr className="border-b border-gray-200 text-left text-sm text-gray-600">
                        <th className="pb-2 pr-4 font-medium">Job #</th>
                        <th className="pb-2 pr-4 font-medium">Customer</th>
                        <th className="pb-2 pr-4 font-medium">Status</th>
                        <th className="pb-2 pr-4 font-medium">Total</th>
                        <th className="pb-2 font-medium">Action</th>
                      </tr>
                    </thead>
                    <tbody>
                      {recentQuotes.map((q) => (
                        <tr key={q.id} className="border-b border-gray-100">
                          <td className="py-2 pr-4">
                            <Link
                              to={`/quotes/${q.id}`}
                              className="font-medium text-primary-from hover:underline"
                            >
                              {q.job_number || '—'}
                            </Link>
                          </td>
                          <td className="py-2 pr-4 text-gray-700">{customerDisplay(q)}</td>
                          <td className="py-2 pr-4">
                            <Badge status={q.status}>{q.status || 'draft'}</Badge>
                          </td>
                          <td className="py-2 pr-4 tabular-nums">
                            {formatCurrency(q.final_total_cad)}
                          </td>
                          <td className="py-2">
                            <Link to={`/quotes/${q.id}`}>
                              <Button variant="secondary" className="!py-1 !text-sm">
                                View →
                              </Button>
                            </Link>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
              <Link to="/quotes" className="mt-3 inline-block text-primary-from hover:underline">
                All Quotes →
              </Link>
            </Card>
          )}
        </>
      )}
    </Layout>
  )
}
