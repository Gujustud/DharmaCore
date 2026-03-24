import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import {
  DndContext,
  useDraggable,
  useDroppable,
  DragOverlay,
} from '@dnd-kit/core'
import { Layout } from '../components/layout/Layout'
import { Card } from '../components/ui/Card'
import { Button } from '../components/ui/Button'
import { Input } from '../components/ui/Input'
import { getJobs, updateJob } from '../lib/api'
import { generateTrackingLink } from '../lib/calculations'
import { format, parseISO, startOfMonth, endOfMonth, startOfYear, endOfYear, isWithinInterval } from 'date-fns'

const JOBS_VIEW_KEY = 'dharmacore_jobs_view'

const COLUMNS = [
  { id: 'planning', label: 'Planning', color: 'bg-blue-50 border-blue-200 text-blue-800 dark:bg-blue-600 dark:border-blue-500 dark:text-white' },
  { id: 'in_progress', label: 'In Progress', color: 'bg-amber-50 border-amber-200 text-amber-800 dark:bg-amber-600 dark:border-amber-500 dark:text-white' },
  { id: 'done', label: 'Done', color: 'bg-green-50 border-green-200 text-green-800 dark:bg-green-600 dark:border-green-500 dark:text-white' },
  { id: 'cancelled', label: 'Cancelled', color: 'bg-gray-100 border-gray-200 text-gray-700 dark:bg-gray-600 dark:border-gray-500 dark:text-white' },
]

function statusLabel(status) {
  return COLUMNS.find((c) => c.id === (status || 'planning'))?.label ?? status ?? 'Planning'
}

function formatDate(d) {
  if (!d) return '—'
  const x = typeof d === 'string' ? new Date(d) : d
  return format(x, 'MMM d, yyyy')
}

function companyDisplay(job) {
  return job.expand?.customer?.company || job.customer_name || '—'
}

function JobCard({ job, isDragOverlay }) {
  return (
    <div
      className={
        'cursor-grab rounded-lg border-2 bg-white p-3 shadow card transition hover:shadow-md dark:bg-gray-800 dark:border-gray-600 ' +
        (isDragOverlay ? 'cursor-grabbing shadow-lg' : '')
      }
    >
      <p className="font-medium text-gray-900 dark:text-white">{job.job_number}</p>
      <p className="text-sm text-gray-600 dark:text-gray-300">{companyDisplay(job)}</p>
    </div>
  )
}

function DraggableJobCard({
  job,
  editingCustomerJobId,
  editingCustomerValue,
  onStartEditCustomer,
  onSaveCustomer,
  onCustomerValueChange,
}) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: job.id,
    data: { job },
  })
  const isEditing = editingCustomerJobId === job.id
  return (
    <div
      ref={setNodeRef}
      className={`flex overflow-hidden rounded-lg border-2 bg-white shadow transition hover:shadow-md dark:bg-gray-800 dark:border-gray-600 ${isDragging ? 'opacity-50' : ''}`}
    >
      <div
        {...listeners}
        {...attributes}
        className="w-2 shrink-0 cursor-grab bg-gray-200 hover:bg-gray-300 active:cursor-grabbing dark:bg-gray-600 dark:hover:bg-gray-500"
        title="Drag to move"
      />
      <div className="min-w-0 flex-1 p-3">
        <Link
          to={`/jobs/${job.id}`}
          className="text-inherit no-underline hover:bg-gray-50/50 dark:hover:bg-gray-700/50"
        >
          <p className="font-medium text-gray-900 dark:text-white">{job.job_number}</p>
        </Link>
        {isEditing ? (
          <input
            type="text"
            value={editingCustomerValue}
            onChange={(e) => onCustomerValueChange(e.target.value)}
            onBlur={onSaveCustomer}
            onKeyDown={(e) => {
              if (e.key === 'Enter') onSaveCustomer()
              e.stopPropagation()
            }}
            autoFocus
            onClick={(e) => e.stopPropagation()}
            className="mt-1 w-full rounded border border-gray-300 px-2 py-1 text-sm focus:border-primary-from focus:outline-none dark:border-gray-600 dark:bg-gray-700 dark:text-gray-100"
          />
        ) : (
          <p
            role="button"
            tabIndex={0}
            onClick={(e) => {
              e.preventDefault()
              e.stopPropagation()
              onStartEditCustomer(job)
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault()
                onStartEditCustomer(job)
              }
            }}
            className="cursor-pointer text-sm text-gray-600 hover:underline dark:text-gray-300"
          >
            {companyDisplay(job)}
          </p>
        )}
      </div>
    </div>
  )
}

function DroppableColumn({
  columnId,
  label,
  color,
  jobs,
  editingCustomerJobId,
  editingCustomerValue,
  onStartEditCustomer,
  onSaveCustomer,
  onCustomerValueChange,
}) {
  const { setNodeRef, isOver } = useDroppable({ id: columnId })
  return (
    <div
      ref={setNodeRef}
      className={
        'min-h-[200px] flex-1 rounded-card border-2 p-3 transition ' +
        color +
        (isOver ? ' ring-2 ring-primary-from' : '')
      }
    >
      <h3 className="mb-3 font-semibold text-gray-800 dark:text-gray-200">{label}</h3>
      <div className="space-y-2">
        {jobs.map((job) => (
          <DraggableJobCard
            key={job.id}
            job={job}
            editingCustomerJobId={editingCustomerJobId}
            editingCustomerValue={editingCustomerValue}
            onStartEditCustomer={onStartEditCustomer}
            onSaveCustomer={onSaveCustomer}
            onCustomerValueChange={onCustomerValueChange}
          />
        ))}
      </div>
    </div>
  )
}

export function JobsBoard() {
  const [jobs, setJobs] = useState([])
  const [loading, setLoading] = useState(true)
  const [activeJob, setActiveJob] = useState(null)
  const [editingCustomerJobId, setEditingCustomerJobId] = useState(null)
  const [editingCustomerValue, setEditingCustomerValue] = useState('')
  const [search, setSearch] = useState('')
  const [view, setView] = useState(() => localStorage.getItem(JOBS_VIEW_KEY) || 'board')
  const setViewAndSave = (v) => {
    setView(v)
    localStorage.setItem(JOBS_VIEW_KEY, v)
  }
  const [sortKey, setSortKey] = useState('job_number')
  const [sortDir, setSortDir] = useState('desc')

  useEffect(() => {
    let cancelled = false
    async function load() {
      setLoading(true)
      try {
        const res = await getJobs()
        if (!cancelled) setJobs(res?.items ?? [])
      } catch (e) {
        if (!cancelled) console.error(e)
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    load()
    return () => { cancelled = true }
  }, [])

  const handleDragEnd = async (event) => {
    const { active, over } = event
    setActiveJob(null)
    if (!over || active.id === over.id) return
    const jobId = active.id
    const newStatus = over.id
    if (!COLUMNS.some((c) => c.id === newStatus)) return
    try {
      await updateJob(jobId, { status: newStatus })
      setJobs((prev) =>
        prev.map((j) => (j.id === jobId ? { ...j, status: newStatus } : j))
      )
    } catch (e) {
      console.error(e)
    }
  }

  const handleDragStart = (event) => {
    const job = jobs.find((j) => j.id === event.active.id)
    if (job) setActiveJob(job)
  }

  const startEditingCustomer = (job) => {
    setEditingCustomerJobId(job.id)
    setEditingCustomerValue(companyDisplay(job) === '—' ? '' : companyDisplay(job))
  }

  const saveCustomerEdit = async () => {
    if (!editingCustomerJobId) return
    const value = (editingCustomerValue ?? '').trim()
    try {
      await updateJob(editingCustomerJobId, { customer_name: value || undefined })
      setJobs((prev) =>
        prev.map((j) =>
          j.id === editingCustomerJobId ? { ...j, customer_name: value } : j
        )
      )
    } catch (e) {
      console.error(e)
    }
    setEditingCustomerJobId(null)
  }

  if (loading) {
    return (
      <Layout>
        <div className="py-8 text-center text-gray-500 dark:text-gray-400">Loading jobs…</div>
      </Layout>
    )
  }

  const searchLower = search.trim().toLowerCase()
  const filteredJobs = searchLower
    ? jobs.filter((j) => {
        const jobNum = String(j.job_number ?? '').toLowerCase()
        const cust = String((j.expand?.customer?.company || j.customer_name) ?? '').toLowerCase()
        return jobNum.includes(searchLower) || cust.includes(searchLower)
      })
    : jobs

  const jobsByStatus = COLUMNS.reduce((acc, col) => {
    acc[col.id] = filteredJobs.filter((j) => (j.status || 'planning') === col.id)
    return acc
  }, {})

  const now = new Date()
  const monthStart = startOfMonth(now)
  const monthEnd = endOfMonth(now)
  const yearStart = startOfYear(now)
  const yearEnd = endOfYear(now)
  function toDate(s) {
    if (!s) return null
    try {
      return typeof s === 'string' ? parseISO(s) : s
    } catch {
      return null
    }
  }
  const planningCount = jobs.filter((j) => (j.status || 'planning') === 'planning').length
  const inProgressCount = jobs.filter((j) => j.status === 'in_progress').length
  const doneJobs = jobs.filter((j) => j.status === 'done')
  const doneThisMonth = doneJobs.filter((j) => {
    const d = toDate(j.completion_date || j.ship_date || j.updated)
    return d && isWithinInterval(d, { start: monthStart, end: monthEnd })
  }).length
  const doneThisYear = doneJobs.filter((j) => {
    const d = toDate(j.completion_date || j.ship_date || j.updated)
    return d && isWithinInterval(d, { start: yearStart, end: yearEnd })
  }).length

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
  const sortedJobs = [...filteredJobs].sort((a, b) => {
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
    return 0
  })

  return (
    <Layout>
      <div className="mb-6 flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Jobs</h1>
        <div className="flex flex-nowrap items-center gap-3">
          <Input
            type="search"
            placeholder="Search…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="min-w-0 max-w-[220px] shrink-0"
          />
        </div>
      </div>

      <div className="mb-4 grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Card>
          <p className="text-sm text-gray-600 dark:text-gray-300">Planning</p>
          <p className="text-2xl font-bold text-gray-900 dark:text-white">{planningCount}</p>
        </Card>
        <Card>
          <p className="text-sm text-gray-600 dark:text-gray-300">In progress</p>
          <p className="text-2xl font-bold text-gray-900 dark:text-white">{inProgressCount}</p>
        </Card>
        <Card>
          <p className="text-sm text-gray-600 dark:text-gray-300">Done this month</p>
          <p className="text-2xl font-bold text-gray-900 dark:text-white">{doneThisMonth}</p>
        </Card>
        <Card>
          <p className="text-sm text-gray-600 dark:text-gray-300">Done this year</p>
          <p className="text-2xl font-bold text-gray-900 dark:text-white">{doneThisYear}</p>
        </Card>
      </div>

      <div className="mb-4 flex flex-wrap items-center gap-4">
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
        <span className="border-l border-gray-200 pl-4 text-sm font-medium text-gray-600 dark:border-gray-600 dark:text-gray-300">
          Order
        </span>
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
        <div className="ml-auto flex gap-3">
          <button
            type="button"
            onClick={() => setViewAndSave('board')}
            className={`text-sm font-medium cursor-pointer focus:outline-none ${view === 'board' ? 'text-gray-900 dark:text-white' : 'text-gray-600 dark:text-gray-300 hover:text-gray-900 dark:hover:text-white'}`}
          >
            Board
          </button>
          <button
            type="button"
            onClick={() => setViewAndSave('list')}
            className={`text-sm font-medium cursor-pointer focus:outline-none ${view === 'list' ? 'text-gray-900 dark:text-white' : 'text-gray-600 dark:text-gray-300 hover:text-gray-900 dark:hover:text-white'}`}
          >
            List
          </button>
        </div>
      </div>

      {view === 'board' ? (
        <DndContext onDragStart={handleDragStart} onDragEnd={handleDragEnd}>
          <div className="flex gap-4 overflow-x-auto pb-4">
            {COLUMNS.map((col) => (
              <DroppableColumn
                key={col.id}
                columnId={col.id}
                label={col.label}
                color={col.color}
                jobs={jobsByStatus[col.id] || []}
                editingCustomerJobId={editingCustomerJobId}
                editingCustomerValue={editingCustomerValue}
                onStartEditCustomer={startEditingCustomer}
                onSaveCustomer={saveCustomerEdit}
                onCustomerValueChange={setEditingCustomerValue}
              />
            ))}
          </div>

          <DragOverlay>
            {activeJob ? <JobCard job={activeJob} isDragOverlay /> : null}
          </DragOverlay>
        </DndContext>
      ) : (
        <Card>
          {sortedJobs.length === 0 ? (
            <p className="py-8 text-center text-gray-500 dark:text-gray-400">
              {jobs.length === 0 ? 'No jobs yet.' : 'No jobs match your search.'}
            </p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[500px]">
                <thead>
                  <tr className="border-b border-gray-200 text-left text-sm text-gray-600 dark:border-gray-600 dark:text-gray-300">
                    <th className="pb-2 pr-4 font-medium">Job #</th>
                    <th className="min-w-[8rem] pb-2 pr-4 font-medium">Customer</th>
                    <th className="pb-2 pr-4 font-medium whitespace-nowrap">Status</th>
                    <th className="pb-2 pr-4 font-medium whitespace-nowrap">Ship date</th>
                    <th className="pb-2 pr-4 font-medium whitespace-nowrap">Delivered</th>
                  </tr>
                </thead>
                <tbody>
                  {sortedJobs.map((job) => {
                    const trackingUrl = generateTrackingLink(job.tracking_number_1)
                    return (
                      <tr
                        key={job.id}
                        className="border-b border-gray-100 hover:bg-gray-50/50 dark:border-gray-700 dark:hover:bg-gray-700/50"
                      >
                        <td className="py-3 pr-4">
                          <Link
                            to={`/jobs/${job.id}`}
                            className="font-medium text-primary-from hover:underline"
                          >
                            {job.job_number || '—'}
                          </Link>
                        </td>
                        <td className="min-w-[8rem] py-3 pr-4 text-gray-700 dark:text-gray-300 overflow-hidden">
                          <Link
                            to={`/jobs/${job.id}`}
                            className="text-primary-from hover:underline block truncate"
                            title={companyDisplay(job)}
                          >
                            {companyDisplay(job)}
                          </Link>
                        </td>
                        <td className="py-3 pr-4 whitespace-nowrap">
                          <span
                            className={
                              'rounded-md border px-2 py-0.5 text-sm font-medium whitespace-nowrap ' +
                              (COLUMNS.find((c) => c.id === (job.status || 'planning'))
                                ?.color ?? 'bg-gray-100 border-gray-200 text-gray-700 dark:bg-gray-600 dark:border-gray-500 dark:text-white')
                            }
                          >
                            {statusLabel(job.status)}
                          </span>
                        </td>
                        <td className="py-3 pr-4 text-gray-700 dark:text-gray-300 whitespace-nowrap">
                          {job.ship_date && trackingUrl ? (
                            <a
                              href={trackingUrl}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="text-primary-from hover:underline"
                            >
                              {formatDate(job.ship_date)}
                            </a>
                          ) : (
                            formatDate(job.ship_date)
                          )}
                        </td>
                        <td className="py-3 pr-4 text-gray-700 dark:text-gray-300 whitespace-nowrap">
                          {formatDate(job.delivered_date)}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      )}
    </Layout>
  )
}
