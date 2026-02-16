import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { startOfMonth, endOfMonth, isWithinInterval, parseISO, format } from 'date-fns'
import { Layout } from '../components/layout/Layout'
import { Card } from '../components/ui/Card'
import { Button } from '../components/ui/Button'
import { Input } from '../components/ui/Input'
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
  const [search, setSearch] = useState('')

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

  const activeJobsAll = jobs.filter(
    (j) => j.status === 'planning' || j.status === 'in_progress'
  )
  const inProgressCount = jobs.filter((j) => j.status === 'in_progress').length
  const doneJobs = jobs.filter((j) => j.status === 'done')
  const doneThisMonth = doneJobs.filter((j) => {
    const d = toDate(j.completion_date || j.updated)
    return d && isWithinInterval(d, { start: monthStart, end: monthEnd })
  }).length

  const searchLower = search.trim().toLowerCase()
  const activeJobs = searchLower
    ? activeJobsAll.filter((j) => {
        const jobNum = String(j.job_number ?? '').toLowerCase()
        const cust = String((j.expand?.customer?.company || j.customer_name) ?? '').toLowerCase()
        return jobNum.includes(searchLower) || cust.includes(searchLower)
      })
    : activeJobsAll

  function jobNumberToDate(jobNumber) {
    const s = String(jobNumber ?? '').replace(/\D/g, '')
    if (s.length !== 8) return 0
    const mm = parseInt(s.slice(0, 2), 10)
    const dd = parseInt(s.slice(2, 4), 10)
    const yyyy = parseInt(s.slice(4, 8), 10)
    const d = new Date(yyyy, mm - 1, dd)
    return isNaN(d.getTime()) ? 0 : d.getTime()
  }

  const recentQuotesAll = [...quotes].sort((a, b) => {
    const ta = jobNumberToDate(a.job_number)
    const tb = jobNumberToDate(b.job_number)
    return tb - ta // newest date first (descending)
  }).slice(0, 6)
  const recentQuotes = searchLower
    ? recentQuotesAll.filter((q) => {
        const jobNum = String(q.job_number ?? '').toLowerCase()
        const cust = String((q.expand?.customer?.company || q.customer_name) ?? '').toLowerCase()
        return jobNum.includes(searchLower) || cust.includes(searchLower)
      })
    : recentQuotesAll

  const customerDisplay = (q) => q.expand?.customer?.company || q.customer_name || '—'

  return (
    <Layout>
      <div className="mb-6 flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">DharmaCore</h1>
        <div className="flex flex-nowrap items-center gap-3">
          <Input
            type="search"
            placeholder="Search jobs and quotes…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="min-w-0 max-w-[220px] shrink-0"
          />
          {!isJobsOnly && (
            <Link to="/quotes/new" className="shrink-0">
              <Button>New Quote</Button>
            </Link>
          )}
        </div>
      </div>

      {loading ? (
        <p className="py-4 text-center text-gray-500 dark:text-gray-400">Loading…</p>
      ) : (
        <>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Card>
              <p className="text-sm text-gray-600 dark:text-gray-300">Active</p>
              <p className="text-2xl font-bold text-gray-900 dark:text-white">{activeJobs.length}</p>
            </Card>
            <Card>
              <p className="text-sm text-gray-600 dark:text-gray-300">In progress</p>
              <p className="text-2xl font-bold text-gray-900 dark:text-white">{inProgressCount}</p>
            </Card>
            <Card>
              <p className="text-sm text-gray-600 dark:text-gray-300">Done</p>
              <p className="text-2xl font-bold text-gray-900 dark:text-white">{doneJobs.length}</p>
            </Card>
            <Card>
              <p className="text-sm text-gray-600 dark:text-gray-300">Done this month</p>
              <p className="text-2xl font-bold text-gray-900 dark:text-white">{doneThisMonth}</p>
            </Card>
          </div>

          <Card className="mt-6">
            <h2 className="mb-2 font-semibold text-gray-900 dark:text-white">Active Jobs</h2>
            {activeJobs.length === 0 ? (
              <p className="text-sm text-gray-500 dark:text-gray-400">
                No active jobs. Jobs appear when a quote is marked Won.
              </p>
            ) : (
              <div className="overflow-x-auto">
                <table className="dashboard-table w-full min-w-[500px] table-fixed">
                  <colgroup>
                    <col style={{ width: '10%' }} />
                    <col style={{ width: '42%' }} />
                    <col style={{ width: '22%' }} />
                    <col style={{ width: '26%' }} />
                  </colgroup>
                  <thead>
                    <tr className="border-b border-gray-200 text-left text-sm text-gray-600 dark:border-gray-600 dark:text-gray-300">
                      <th className="pb-2 pr-4 font-medium">Job #</th>
                      <th className="pb-2 pr-4 font-medium">Customer</th>
                      <th className="pb-2 pr-4 font-medium">Status</th>
                      <th className="pb-2 font-medium">Ship date</th>
                    </tr>
                  </thead>
                  <tbody>
                    {activeJobs.map((j) => (
                      <tr key={j.id} className="align-middle border-b border-gray-100 dark:border-gray-700">
                        <td className="py-2 pr-4 font-medium text-gray-900 dark:text-white align-middle">
                          <Link to={`/jobs/${j.id}`} className="text-primary-from hover:underline">
                            {j.job_number || '—'}
                          </Link>
                        </td>
                        <td className="py-2 pr-4 text-gray-700 dark:text-gray-300 align-middle">
                          <Link to={`/jobs/${j.id}`} className="text-primary-from hover:underline">
                            {j.expand?.customer?.company || j.customer_name || '—'}
                          </Link>
                        </td>
                        <td className="whitespace-nowrap py-2 pr-4 align-middle">
                          <Badge status={j.status}>{jobStatusLabel(j.status)}</Badge>
                        </td>
                        <td className="py-2 pr-4 align-middle">
                          {j.ship_date
                            ? format(
                                typeof j.ship_date === 'string'
                                  ? parseISO(j.ship_date)
                                  : j.ship_date,
                                'MMM d'
                              )
                            : '—'}
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
              <h2 className="mb-2 font-semibold text-gray-900 dark:text-white">Recent Quotes</h2>
              {recentQuotes.length === 0 ? (
                <p className="text-sm text-gray-500 dark:text-gray-400">No quotes yet. Create one from Quotes.</p>
              ) : (
                <div className="overflow-x-auto">
                  <table className="dashboard-table w-full min-w-[500px] table-fixed">
                    <colgroup>
                      <col style={{ width: '10%' }} />
                      <col style={{ width: '42%' }} />
                      <col style={{ width: '22%' }} />
                      <col style={{ width: '26%' }} />
                    </colgroup>
                    <thead>
                      <tr className="border-b border-gray-200 text-left text-sm text-gray-600 dark:border-gray-600 dark:text-gray-300">
                        <th className="pb-2 pr-4 font-medium">Job #</th>
                        <th className="pb-2 pr-4 font-medium">Customer</th>
                        <th className="pb-2 pr-4 font-medium">Status</th>
                        <th className="pb-2 font-medium">Total</th>
                      </tr>
                    </thead>
                    <tbody>
                      {recentQuotes.map((q) => (
                        <tr key={q.id} className="align-middle border-b border-gray-100 dark:border-gray-700">
                          <td className="py-2 pr-4 align-middle">
                            <Link
                              to={`/quotes/${q.id}`}
                              className="font-medium text-primary-from hover:underline"
                            >
                              {q.job_number || '—'}
                            </Link>
                          </td>
                          <td className="py-2 pr-4 text-gray-700 dark:text-gray-300 align-middle">
                            <Link to={`/quotes/${q.id}`} className="text-primary-from hover:underline">
                              {customerDisplay(q)}
                            </Link>
                          </td>
                          <td className="whitespace-nowrap py-2 pr-4 align-middle">
                            <Badge status={q.status}>{q.status || 'draft'}</Badge>
                          </td>
                          <td className="py-2 pr-4 tabular-nums align-middle">
                            {formatCurrency(q.final_total_cad)}
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
