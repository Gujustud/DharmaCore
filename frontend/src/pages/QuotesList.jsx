import { useState, useEffect, useMemo } from 'react'
import { Link, useNavigate, useLocation } from 'react-router-dom'
import { startOfMonth, endOfMonth, isWithinInterval } from 'date-fns'
import { Layout } from '../components/layout/Layout'
import { Card } from '../components/ui/Card'
import { Button } from '../components/ui/Button'
import { Input } from '../components/ui/Input'
import { Badge } from '../components/ui/Badge'
import { ConfirmDialog } from '../components/ui/ConfirmDialog'
import { getQuotes, deleteQuote, getQuoteLineItems, createQuote, createLineItem, getJobByQuote, getAllLineItems } from '../lib/api'
import { generateJobNumber } from '../lib/calculations'

const DEBOUNCE_MS = 300

const STATUS_OPTIONS = [
  { value: '', label: 'All statuses' },
  { value: 'draft', label: 'Draft' },
  { value: 'sent', label: 'Sent' },
  { value: 'won', label: 'Won' },
  { value: 'lost', label: 'Lost' },
]

function formatCurrency(n) {
  if (n == null || n === '') return '—'
  const num = Number(n)
  if (Number.isNaN(num)) return '—'
  return new Intl.NumberFormat('en-CA', { style: 'currency', currency: 'CAD', minimumFractionDigits: 0, maximumFractionDigits: 0 }).format(num)
}

function toDate(s) {
  if (!s) return null
  try {
    let str = s
    if (typeof str === 'string' && /^\d{4}-\d{2}-\d{2} \d/.test(str)) {
      str = str.replace(' ', 'T') // PocketBase often uses space; ISO expects T
    }
    const d = typeof str === 'string' ? new Date(str) : str
    return Number.isNaN(d?.getTime()) ? null : d
  } catch {
    return null
  }
}

export function QuotesList() {
  const navigate = useNavigate()
  const location = useLocation()
  const [quotes, setQuotes] = useState([])
  const [lineItems, setLineItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [searchDebounced, setSearchDebounced] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [sortKey, setSortKey] = useState('job_number')
  const [sortDir, setSortDir] = useState('desc')
  const [deleteConfirm, setDeleteConfirm] = useState(null)
  const [copyingId, setCopyingId] = useState(null)
  const [showTotals, setShowTotals] = useState(true)

  // Debounce search input
  useEffect(() => {
    const t = setTimeout(() => setSearchDebounced(search), DEBOUNCE_MS)
    return () => clearTimeout(t)
  }, [search])

  function load() {
    setLoading(true)
    getQuotes()
      .then((res) => {
        const items = res?.items ?? []
        items.sort((a, b) => new Date(b.created || 0) - new Date(a.created || 0))
        setQuotes(items)
        return items
      })
      .then((items) => {
        if (items.length > 0) {
          return getAllLineItems().then((lis) => setLineItems(lis ?? []))
        }
      })
      .catch((e) => {
        if (e?.status !== 0 && !e?.message?.includes('autocancelled')) console.error(e)
      })
      .finally(() => setLoading(false))
  }

  // Refetch when viewing the list and when user returns to this tab so stats (e.g. Revenue this month) stay current
  useEffect(() => {
    if (location.pathname !== '/quotes') return
    load()
    const onFocus = () => load()
    window.addEventListener('focus', onFocus)
    return () => window.removeEventListener('focus', onFocus)
  }, [location.pathname])

  const lineItemsByQuote = useMemo(() => {
    const m = {}
    for (const li of lineItems) {
      const q = li.quote
      if (!m[q]) m[q] = []
      m[q].push(li)
    }
    return m
  }, [lineItems])

  const filtered = useMemo(() => {
    const searchLower = searchDebounced.trim().toLowerCase()
    const list = quotes.filter((q) => {
      const matchSearch =
        !searchLower ||
        [q.job_number, q.wave_quote_number, q.customer_name, q.expand?.customer?.name, q.expand?.customer?.company]
          .filter(Boolean)
          .some((v) => String(v).toLowerCase().includes(searchLower)) ||
        (lineItemsByQuote[q.id] ?? []).some((li) =>
          String(li.part_number || '').toLowerCase().includes(searchLower)
        )
      const matchStatus = !statusFilter || q.status === statusFilter
      return matchSearch && matchStatus
    })

    const mult = sortDir === 'asc' ? 1 : -1
    function jobNumberToDate(jobNumber) {
      const s = String(jobNumber ?? '').replace(/\D/g, '')
      const eight = s.length >= 8 ? s.slice(0, 8) : s
      if (eight.length !== 8) return 0
      const mm = parseInt(eight.slice(0, 2), 10)
      const dd = parseInt(eight.slice(2, 4), 10)
      const yyyy = parseInt(eight.slice(4, 8), 10)
      const d = new Date(yyyy, mm - 1, dd)
      return isNaN(d.getTime()) ? 0 : d.getTime()
    }
    return [...list].sort((a, b) => {
      if (sortKey === 'job_number') {
        const ta = jobNumberToDate(a.job_number)
        const tb = jobNumberToDate(b.job_number)
        const dateCmp = sortDir === 'desc' ? tb - ta : ta - tb
        if (dateCmp !== 0) return dateCmp
        const sa = String(a.job_number ?? '')
        const sb = String(b.job_number ?? '')
        return sortDir === 'desc' ? sb.localeCompare(sa) : sa.localeCompare(sb)
      }
      if (sortKey === 'customer') {
        const ca = a.expand?.customer?.company || a.customer_name || ''
        const cb = b.expand?.customer?.company || b.customer_name || ''
        return mult * String(ca).localeCompare(String(cb))
      }
      if (sortKey === 'status') {
        return mult * (String(a.status || '').localeCompare(String(b.status || '')))
      }
      if (sortKey === 'total') {
        const na = Number(a.final_total_cad) || 0
        const nb = Number(b.final_total_cad) || 0
        return mult * (na - nb)
      }
      if (sortKey === 'created') {
        return mult * (new Date(b.created || 0) - new Date(a.created || 0))
      }
      return 0
    })
  }, [quotes, searchDebounced, statusFilter, sortKey, sortDir, lineItemsByQuote])

  const handleSort = (key) => {
    if (sortKey === key) setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'))
    else {
      setSortKey(key)
      setSortDir(key === 'created' || key === 'total' ? 'desc' : 'asc')
    }
  }

  const handleDelete = async (quote) => {
    if (!quote?.id) return
    try {
      await deleteQuote(quote.id)
      setDeleteConfirm(null)
      load()
    } catch (e) {
      console.error(e)
    }
  }

  const handleCopy = async (quote) => {
    if (!quote?.id) return
    setCopyingId(quote.id)
    try {
      const items = await getQuoteLineItems(quote.id)
      const newJobNumber = generateJobNumber()
      const copy = {
        job_number: newJobNumber,
        wave_quote_number: '',
        customer: quote.customer || undefined,
        customer_name: quote.customer_name || '',
        po_number: quote.po_number || '',
        engineer: quote.engineer || '',
        status: 'draft',
        shipping_markup_percent: quote.shipping_markup_percent ?? 30,
        final_markup_percent: quote.final_markup_percent ?? 0,
        subcontractor_markup_percent: quote.subcontractor_markup_percent ?? 0,
        exchange_rate_usd_to_cad: quote.exchange_rate_usd_to_cad ?? 1.3,
        hourly_rate_programming: quote.hourly_rate_programming ?? 350,
        hourly_rate_setup: quote.hourly_rate_setup ?? 350,
        hourly_rate_first_run: quote.hourly_rate_first_run ?? 350,
        hourly_rate_production: quote.hourly_rate_production ?? 269,
      }
      const created = await createQuote(copy)
      for (let i = 0; i < (items || []).length; i++) {
        const item = items[i]
        await createLineItem({
          quote: created.id,
          line_number: item.line_number ?? i + 1,
          part_number: item.part_number,
          part_quantity: item.part_quantity ?? 1,
          alloy: item.alloy,
          stock_size_per_part: item.stock_size_per_part,
          ordered_length: item.ordered_length,
          pieces: item.pieces,
          material_note: item.material_note,
          material_vendor: item.material_vendor || undefined,
          vendor_supplied: item.vendor_supplied,
          usd_cost: item.usd_cost ?? 0,
          material_cost_cad: item.material_cost_cad != null && item.material_cost_cad !== '' ? Number(item.material_cost_cad) : undefined,
          material_shipping_cost: item.material_shipping_cost ?? 0,
          testing_cost: item.testing_cost ?? 0,
          tooling_total_cost: item.tooling_total_cost ?? 0,
          tooling_description: item.tooling_description,
          programming_hours: item.programming_hours ?? 0,
          setup_hours: item.setup_hours ?? 0,
          first_run_hours: item.first_run_hours ?? 0,
          production_hours_total: item.production_hours_total ?? 0,
          labor_note: item.labor_note || undefined,
          subcontractor_1: item.subcontractor_1 || undefined,
          subcontractor_1_service: item.subcontractor_1_service,
          subcontractor_1_cost: item.subcontractor_1_cost ?? 0,
          subcontractor_1_shipping: item.subcontractor_1_shipping ?? 0,
          subcontractor_2: item.subcontractor_2 || undefined,
          subcontractor_2_service: item.subcontractor_2_service,
          subcontractor_2_cost: item.subcontractor_2_cost ?? 0,
          subcontractor_2_shipping: item.subcontractor_2_shipping ?? 0,
          heat_treat_cost: item.heat_treat_cost ?? 0,
          inspection_cost: item.inspection_cost ?? 0,
          packaging_cost: item.packaging_cost ?? 0,
          shipping_cost: item.shipping_cost ?? 0,
          previous_quote_reference: item.previous_quote_reference,
          quote_part_price_cad: item.quote_part_price_cad != null && item.quote_part_price_cad !== '' ? Number(item.quote_part_price_cad) : undefined,
        })
      }
      navigate(`/quotes/${created.id}`)
    } catch (e) {
      console.error(e)
    } finally {
      setCopyingId(null)
    }
  }

  const handleViewJob = async (quoteId) => {
    try {
      const job = await getJobByQuote(quoteId)
      if (job?.id) navigate(`/jobs/${job.id}`)
    } catch (e) {
      console.error(e)
    }
  }

  const customerDisplay = (q) => q.expand?.customer?.company || q.customer_name || '—'

  const now = new Date()
  const monthStart = startOfMonth(now)
  const monthEnd = endOfMonth(now)
  const quoteCreatedDate = (q) => toDate(q.quote_created_date ?? q.created)
  const quotesThisMonth = quotes.filter((q) => {
    const d = quoteCreatedDate(q)
    return d && isWithinInterval(d, { start: monthStart, end: monthEnd })
  })
  const wonQuotes = quotes.filter((q) => q.status === 'won')
  const currentYear = now.getFullYear()
  const currentMonth = now.getMonth()
  const pendingQuotes = quotes.filter((q) => q.status === 'sent')
  const sumWonRevenue = (list) =>
    list.reduce((sum, q) => {
      const total = Number(q.final_total_cad)
      const sub = Number(q.subtotal)
      const value = !Number.isNaN(total) && total > 0 ? total : (!Number.isNaN(sub) && sub > 0 ? sub : 0)
      return sum + value
    }, 0)
  // Won quotes whose quote_created_date is in the current month
  const wonThisMonth = wonQuotes.filter((q) => {
    const d = quoteCreatedDate(q)
    return (
      d &&
      d.getFullYear() === currentYear &&
      d.getMonth() === currentMonth
    )
  })
  const revenueThisMonth = sumWonRevenue(wonThisMonth)
  return (
    <Layout>
      <div className="mb-6 flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">All Quotes</h1>
        <div className="flex flex-nowrap items-center gap-3">
          <Input
            type="search"
            placeholder="Search…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="min-w-0 max-w-[220px] shrink-0"
          />
          <Link to="/quotes/new" className="shrink-0">
            <Button>New Quote</Button>
          </Link>
        </div>
      </div>

      <div className="mb-4 grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Card>
          <p className="text-sm text-gray-600 dark:text-gray-300">Quotes this month</p>
          <p className="text-2xl font-bold">{quotesThisMonth.length}</p>
        </Card>
        <Card>
          <p className="text-sm text-gray-600 dark:text-gray-300">Won</p>
          <p className="text-2xl font-bold">{wonQuotes.length}</p>
        </Card>
        <Card>
          <p className="text-sm text-gray-600 dark:text-gray-300">Pending</p>
          <p className="text-2xl font-bold">{pendingQuotes.length}</p>
        </Card>
        <Card>
          <p className="text-sm text-gray-600 dark:text-gray-300">Revenue this month</p>
          <p className="text-2xl font-bold">{showTotals ? formatCurrency(revenueThisMonth) : '—'}</p>
        </Card>
      </div>

      <div className="mb-4 flex flex-wrap items-center gap-4">
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-primary-from focus:outline-none focus:ring-1 focus:ring-primary-from dark:border-gray-600 dark:bg-gray-700 dark:text-gray-100"
        >
          {STATUS_OPTIONS.map((opt) => (
            <option key={opt.value || 'all'} value={opt.value}>
              {opt.label}
            </option>
          ))}
        </select>
        <span className="ml-2 border-l border-gray-200 pl-4 dark:border-gray-600" />
        <div className="flex gap-3">
          <button
            type="button"
            onClick={() => {
              setSortKey('job_number')
              if (sortKey !== 'job_number') setSortDir('desc')
            }}
            className={`text-sm font-medium cursor-pointer focus:outline-none ${sortKey === 'job_number' ? 'text-gray-900 dark:text-white' : 'text-gray-600 dark:text-gray-300 hover:text-gray-900 dark:hover:text-white'}`}
          >
            Job #
          </button>
          <button
            type="button"
            onClick={() => {
              setSortKey('customer')
              if (sortKey !== 'customer') setSortDir('asc')
            }}
            className={`text-sm font-medium cursor-pointer focus:outline-none ${sortKey === 'customer' ? 'text-gray-900 dark:text-white' : 'text-gray-600 dark:text-gray-300 hover:text-gray-900 dark:hover:text-white'}`}
          >
            Customer
          </button>
        </div>
        <span className="text-sm font-medium text-gray-600 dark:text-gray-300">Order</span>
        <div className="flex gap-3">
          <button
            type="button"
            onClick={() => setSortDir('asc')}
            className={`text-sm font-medium cursor-pointer focus:outline-none ${sortDir === 'asc' ? 'text-gray-900 dark:text-white' : 'text-gray-600 dark:text-gray-300 hover:text-gray-900 dark:hover:text-white'}`}
          >
            A→Z
          </button>
          <button
            type="button"
            onClick={() => setSortDir('desc')}
            className={`text-sm font-medium cursor-pointer focus:outline-none ${sortDir === 'desc' ? 'text-gray-900 dark:text-white' : 'text-gray-600 dark:text-gray-300 hover:text-gray-900 dark:hover:text-white'}`}
          >
            Z→A
          </button>
        </div>
      </div>

      <Card>
        {loading ? (
          <p className="py-8 text-center text-gray-500 dark:text-gray-400">Loading…</p>
        ) : filtered.length === 0 ? (
          <p className="py-8 text-center text-gray-500 dark:text-gray-400">
            {quotes.length === 0
              ? 'No quotes yet. Create one to get started.'
              : 'No quotes match your search or filter.'}
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[600px]">
              <thead>
                <tr className="border-b border-gray-200 text-left text-sm text-gray-600 dark:border-gray-600 dark:text-gray-300">
                  <th className="pb-2 pr-4 font-medium">Job #</th>
                  <th className="min-w-[8rem] pb-2 pr-4 font-medium">Customer</th>
                  <th className="pb-2 pr-4 font-medium">Status</th>
                  <th className="pb-2 pr-4 font-medium">
                    <span className="inline-flex items-center gap-1.5">
                      Total (CAD)
                      <button
                        type="button"
                        onClick={(e) => { e.stopPropagation(); setShowTotals((v) => !v) }}
                        className="rounded p-0.5 text-gray-500 hover:text-gray-700 hover:bg-gray-200 dark:text-gray-400 dark:hover:text-gray-200 dark:hover:bg-gray-600"
                        title={showTotals ? 'Hide totals' : 'Show totals'}
                        aria-label={showTotals ? 'Hide totals' : 'Show totals'}
                      >
                        {showTotals ? (
                          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                        ) : (
                          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>
                        )}
                      </button>
                    </span>
                  </th>
                  <th className="pb-2 font-medium whitespace-nowrap">Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((q) => (
                  <tr key={q.id} className="border-b border-gray-100 hover:bg-gray-50/50 dark:border-gray-700 dark:hover:bg-gray-700/50">
                    <td className="py-3 pr-4">
                      <Link to={`/quotes/${q.id}`} className="font-medium text-primary-from hover:underline">
                        {q.job_number || '—'}
                      </Link>
                    </td>
                    <td className="min-w-[8rem] py-3 pr-4 text-gray-700 dark:text-gray-300 overflow-hidden">
                      <span className="block truncate" title={customerDisplay(q)}>{customerDisplay(q)}</span>
                    </td>
                    <td className="py-3 pr-4">
                      <Badge status={q.status}>{q.status || 'draft'}</Badge>
                    </td>
                    <td className="py-3 pr-4 tabular-nums">{showTotals ? formatCurrency(q.final_total_cad) : '—'}</td>
                    <td className="py-3 whitespace-nowrap">
                      <div className="flex flex-nowrap items-center gap-2">
                        <Link to={`/quotes/${q.id}`}>
                          <Button variant="secondary" className="!py-1 !text-sm">
                            View
                          </Button>
                        </Link>
                        <Button
                          variant="secondary"
                          className="!py-1 !text-sm"
                          onClick={() => handleCopy(q)}
                          disabled={copyingId === q.id}
                        >
                          {copyingId === q.id ? 'Copying…' : 'Copy'}
                        </Button>
                        {q.status === 'won' && (
                          <Button
                            variant="secondary"
                            className="!py-1 !text-sm"
                            onClick={() => handleViewJob(q.id)}
                          >
                            View Job
                          </Button>
                        )}
                        <Button
                          variant="secondary"
                          className="!py-1 !text-sm text-red-600 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-900/40"
                          onClick={() => setDeleteConfirm(q)}
                        >
                          Delete
                        </Button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <ConfirmDialog
        open={!!deleteConfirm}
        title="Delete quote?"
        message={
          deleteConfirm
            ? `Delete quote ${deleteConfirm.job_number || deleteConfirm.id}? This cannot be undone.`
            : ''
        }
        confirmLabel="Delete"
        danger
        onConfirm={() => deleteConfirm && handleDelete(deleteConfirm)}
        onCancel={() => setDeleteConfirm(null)}
      />
    </Layout>
  )
}
