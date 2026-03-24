import { useState, useEffect } from 'react'
import { Link, useParams, useNavigate } from 'react-router-dom'
import { format } from 'date-fns'
import { Layout } from '../components/layout/Layout'
import { Card } from '../components/ui/Card'
import { Button } from '../components/ui/Button'
import { Input } from '../components/ui/Input'
import { Badge } from '../components/ui/Badge'
import { ConfirmDialog } from '../components/ui/ConfirmDialog'
import {
  getCustomer,
  updateCustomer,
  deleteCustomer,
  getJobs,
  getQuotes,
} from '../lib/api'

const JOB_STATUS_LABELS = {
  planning: 'Planning',
  in_progress: 'In progress',
  done: 'Done',
  cancelled: 'Cancelled',
}
const QUOTE_STATUS_LABELS = { draft: 'Draft', sent: 'Sent', won: 'Won', lost: 'Lost' }

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

function formatDate(d) {
  if (!d) return '—'
  const x = typeof d === 'string' ? new Date(d) : d
  return Number.isNaN(x.getTime()) ? '—' : format(x, 'MMM d, yyyy')
}

export function CustomerDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [customer, setCustomer] = useState(null)
  const [jobs, setJobs] = useState([])
  const [quotes, setQuotes] = useState([])
  const [loading, setLoading] = useState(true)
  const [form, setForm] = useState({ name: '', company: '', email: '', phone: '', address: '', notes: '' })
  const [saving, setSaving] = useState(false)
  const [deleteConfirm, setDeleteConfirm] = useState(false)

  useEffect(() => {
    if (!id) return
    let cancelled = false
    setLoading(true)
    Promise.all([
      getCustomer(id),
      getJobs({ filter: `customer = "${id}"`, perPage: 500 }),
      getQuotes({ filter: `customer = "${id}"`, perPage: 500 }),
    ])
      .then(([custRes, jobsRes, quotesRes]) => {
        if (cancelled) return
        setCustomer(custRes)
        setForm({
          name: custRes?.name ?? '',
          company: custRes?.company ?? '',
          email: custRes?.email ?? '',
          phone: custRes?.phone ?? '',
          address: custRes?.address ?? '',
          notes: custRes?.notes ?? '',
        })
        setJobs(jobsRes?.items ?? [])
        const quoteItems = quotesRes?.items ?? []
        quoteItems.sort((a, b) => new Date(b.updated || b.created || 0) - new Date(a.updated || a.created || 0))
        setQuotes(quoteItems)
      })
      .catch((e) => {
        if (!cancelled) console.error(e)
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => { cancelled = true }
  }, [id])

  const handleSave = () => {
    if (!customer || !form.name?.trim()) return
    setSaving(true)
    const payload = {
      name: form.name.trim(),
      company: form.company?.trim() || '',
      email: form.email?.trim() || '',
      phone: form.phone?.trim() || '',
      address: form.address?.trim() || '',
      notes: form.notes?.trim() || '',
    }
    updateCustomer(customer.id, payload)
      .then((updated) => setCustomer(updated))
      .catch(console.error)
      .finally(() => setSaving(false))
  }

  const handleDelete = () => {
    if (!customer) return
    deleteCustomer(customer.id)
      .then(() => navigate('/customers'))
      .catch(console.error)
  }

  const wonRevenue = quotes
    .filter((q) => q.status === 'won')
    .reduce((sum, q) => sum + (Number(q.final_total_cad) || 0), 0)

  if (loading || !customer) {
    return (
      <Layout>
        <div className="py-8 text-center text-gray-500 dark:text-gray-400">
          {loading ? 'Loading…' : 'Customer not found.'}
        </div>
      </Layout>
    )
  }

  const displayName = customer.company || customer.name || 'Customer'

  return (
    <Layout>
      <div className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <Link to="/customers" className="text-sm text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white">
            ← Customers
          </Link>
          <h1 className="text-2xl font-bold text-gray-900 dark:text-white">{displayName}</h1>
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="lg:col-span-2 space-y-6">
          <Card>
            <h2 className="mb-4 font-semibold text-gray-900 dark:text-white">Details</h2>
            <div className="grid gap-3 sm:grid-cols-2">
              <Input
                label="Company"
                value={form.company}
                onChange={(e) => setForm((p) => ({ ...p, company: e.target.value }))}
              />
              <Input
                label="Name"
                value={form.name}
                onChange={(e) => setForm((p) => ({ ...p, name: e.target.value }))}
              />
              <Input
                label="Email"
                type="email"
                value={form.email}
                onChange={(e) => setForm((p) => ({ ...p, email: e.target.value }))}
              />
              <Input
                label="Phone"
                value={form.phone}
                onChange={(e) => setForm((p) => ({ ...p, phone: e.target.value }))}
              />
              <div className="sm:col-span-2">
                <Input
                  label="Address"
                  value={form.address}
                  onChange={(e) => setForm((p) => ({ ...p, address: e.target.value }))}
                />
              </div>
              <div className="sm:col-span-2">
                <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">Notes</label>
                <textarea
                  className="w-full rounded-input border-2 border-gray-300 px-3 py-2 focus:border-primary-from focus:outline-none dark:border-gray-600 dark:bg-gray-700 dark:text-gray-100"
                  rows={3}
                  value={form.notes}
                  onChange={(e) => setForm((p) => ({ ...p, notes: e.target.value }))}
                />
              </div>
            </div>
            <div className="mt-4 flex gap-2">
              <Button disabled={saving || !form.name?.trim()} onClick={handleSave}>
                {saving ? 'Saving…' : 'Save'}
              </Button>
              <Button variant="danger" onClick={() => setDeleteConfirm(true)}>
                Delete customer
              </Button>
            </div>
          </Card>

          <Card>
            <h2 className="mb-4 font-semibold text-gray-900 dark:text-white">Jobs</h2>
            {jobs.length === 0 ? (
              <p className="text-sm text-gray-500 dark:text-gray-400">No jobs for this customer.</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="customer-detail-table w-full min-w-[520px] table-fixed">
                  <thead>
                    <tr className="border-b border-gray-200 text-left text-sm text-gray-600 dark:border-gray-600 dark:text-gray-300">
                      <th className="w-[18%] pb-2 pr-4 font-medium">Job #</th>
                      <th className="w-[22%] pb-2 pr-4 font-medium">Status</th>
                      <th className="w-[30%] pb-2 pr-4 font-medium">Ship date</th>
                      <th className="w-[30%] pb-2 font-medium">Delivered date</th>
                    </tr>
                  </thead>
                  <tbody>
                    {jobs.map((job) => (
                      <tr key={job.id} className="border-b border-gray-100 hover:bg-gray-50/50 dark:border-gray-700 dark:hover:bg-gray-700/50">
                        <td className="w-[18%] py-2 pr-4 align-middle overflow-hidden">
                          <Link
                            to={`/jobs/${job.id}`}
                            className="block truncate font-medium text-primary-from hover:underline"
                            title={job.job_number || ''}
                          >
                            {job.job_number || '—'}
                          </Link>
                        </td>
                        <td className="w-[22%] whitespace-nowrap py-2 pr-4 align-middle">
                          <Badge status={job.status}>
                            {JOB_STATUS_LABELS[job.status] ?? job.status ?? '—'}
                          </Badge>
                        </td>
                        <td className="w-[30%] py-2 pr-4 align-middle text-gray-700 dark:text-gray-300 whitespace-nowrap">
                          {formatDate(job.ship_date)}
                        </td>
                        <td className="w-[30%] py-2 align-middle text-gray-700 dark:text-gray-300 whitespace-nowrap">
                          {formatDate(job.delivered_date)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>

          <Card>
            <h2 className="mb-4 font-semibold text-gray-900 dark:text-white">Quotes</h2>
            {quotes.length === 0 ? (
              <p className="text-sm text-gray-500 dark:text-gray-400">No quotes for this customer.</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="customer-detail-table w-full min-w-[520px] table-fixed">
                  <thead>
                    <tr className="border-b border-gray-200 text-left text-sm text-gray-600 dark:border-gray-600 dark:text-gray-300">
                      <th className="w-[18%] pb-2 pr-4 font-medium">Job #</th>
                      <th className="w-[22%] pb-2 pr-4 font-medium">Status</th>
                      <th className="w-[30%] pb-2 pr-4 font-medium">Total</th>
                      <th className="w-[30%] pb-2 font-medium">Updated</th>
                    </tr>
                  </thead>
                  <tbody>
                    {quotes.map((q) => (
                      <tr key={q.id} className="border-b border-gray-100 hover:bg-gray-50/50 dark:border-gray-700 dark:hover:bg-gray-700/50">
                        <td className="w-[18%] py-2 pr-4 align-middle overflow-hidden">
                          <Link
                            to={`/quotes/${q.id}`}
                            className="block truncate font-medium text-primary-from hover:underline"
                            title={q.job_number || ''}
                          >
                            {q.job_number || '—'}
                          </Link>
                        </td>
                        <td className="w-[22%] whitespace-nowrap py-2 pr-4 align-middle">
                          <Badge status={q.status}>
                            {QUOTE_STATUS_LABELS[q.status] ?? q.status ?? '—'}
                          </Badge>
                        </td>
                        <td className="w-[30%] py-2 pr-4 align-middle tabular-nums">{formatCurrency(q.final_total_cad)}</td>
                        <td className="w-[30%] py-2 align-middle text-gray-700 dark:text-gray-300 whitespace-nowrap">
                          {formatDate(q.updated)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
        </div>

        <div className="space-y-4">
          <Card>
            <h2 className="mb-3 font-semibold text-gray-900 dark:text-white">Summary</h2>
            <div className="space-y-3">
              <div>
                <p className="text-sm text-gray-600 dark:text-gray-300">Revenue (won quotes)</p>
                <p className="text-xl font-bold text-gray-900 dark:text-white">{formatCurrency(wonRevenue)}</p>
              </div>
              <div>
                <p className="text-sm text-gray-600 dark:text-gray-300">Jobs</p>
                <p className="text-xl font-bold text-gray-900 dark:text-white">{jobs.length}</p>
              </div>
              <div>
                <p className="text-sm text-gray-600 dark:text-gray-300">Quotes</p>
                <p className="text-xl font-bold text-gray-900 dark:text-white">{quotes.length}</p>
              </div>
            </div>
          </Card>
        </div>
      </div>

      <ConfirmDialog
        open={deleteConfirm}
        onClose={() => setDeleteConfirm(false)}
        onConfirm={handleDelete}
        title="Delete customer"
        message={`Delete "${displayName}"? This won't remove them from existing quotes or jobs.`}
        confirmLabel="Delete"
      />
    </Layout>
  )
}
