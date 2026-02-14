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
import { getJobs, updateJob } from '../lib/api'
import { generateTrackingLink } from '../lib/calculations'
import { format } from 'date-fns'

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

function JobCard({ job, isDragOverlay }) {
  return (
    <div
      className={
        'cursor-grab rounded-lg border-2 bg-white p-3 shadow card transition hover:shadow-md dark:bg-gray-800 dark:border-gray-600 ' +
        (isDragOverlay ? 'cursor-grabbing shadow-lg' : '')
      }
    >
      <p className="font-medium text-gray-900 dark:text-white">{job.job_number}</p>
      <p className="text-sm text-gray-600 dark:text-gray-300">{job.expand?.customer?.company || job.customer_name || '—'}</p>
    </div>
  )
}

function DraggableJobCard({ job }) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: job.id,
    data: { job },
  })
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
      <Link
        to={`/jobs/${job.id}`}
        className="min-w-0 flex-1 p-3 text-inherit no-underline hover:bg-gray-50/50 dark:hover:bg-gray-700/50"
      >
        <p className="font-medium text-gray-900 dark:text-white">{job.job_number}</p>
        <p className="text-sm text-gray-600 dark:text-gray-300">{job.expand?.customer?.company || job.customer_name || '—'}</p>
      </Link>
    </div>
  )
}

function DroppableColumn({ columnId, label, color, jobs }) {
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
          <DraggableJobCard key={job.id} job={job} />
        ))}
      </div>
    </div>
  )
}

export function JobsBoard() {
  const [jobs, setJobs] = useState([])
  const [loading, setLoading] = useState(true)
  const [activeJob, setActiveJob] = useState(null)
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

  const jobsByStatus = COLUMNS.reduce((acc, col) => {
    acc[col.id] = jobs.filter((j) => (j.status || 'planning') === col.id)
    return acc
  }, {})

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

  if (loading) {
    return (
      <Layout>
        <div className="py-8 text-center text-gray-500 dark:text-gray-400">Loading jobs…</div>
      </Layout>
    )
  }

  const mult = sortDir === 'asc' ? 1 : -1
  function jobNumberToDate(jobNumber) {
    const s = String(jobNumber ?? '').replace(/\D/g, '')
    if (s.length !== 8) return 0
    const mm = parseInt(s.slice(0, 2), 10)
    const dd = parseInt(s.slice(2, 4), 10)
    const yyyy = parseInt(s.slice(4, 8), 10)
    const d = new Date(yyyy, mm - 1, dd)
    return isNaN(d.getTime()) ? 0 : d.getTime()
  }
  const sortedJobs = [...jobs].sort((a, b) => {
    if (sortKey === 'job_number') {
      const ta = jobNumberToDate(a.job_number)
      const tb = jobNumberToDate(b.job_number)
      return sortDir === 'desc' ? tb - ta : ta - tb
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
        <div className="flex flex-wrap items-center gap-4">
          {view === 'list' && (
            <>
              <span className="text-sm font-medium text-gray-600 dark:text-gray-300">Sort by</span>
              <div className="flex gap-1">
                <Button
                  variant={sortKey === 'job_number' ? 'primary' : 'secondary'}
                  className="!py-1 !text-sm"
                  onClick={() => {
                    setSortKey('job_number')
                    if (sortKey !== 'job_number') setSortDir('desc')
                  }}
                >
                  Job #
                </Button>
                <Button
                  variant={sortKey === 'customer' ? 'primary' : 'secondary'}
                  className="!py-1 !text-sm"
                  onClick={() => {
                    setSortKey('customer')
                    if (sortKey !== 'customer') setSortDir('asc')
                  }}
                >
                  Customer
                </Button>
              </div>
              <span className="text-sm font-medium text-gray-600 dark:text-gray-300">Order</span>
              <div className="flex gap-1">
                <Button
                  variant={sortDir === 'asc' ? 'primary' : 'secondary'}
                  className="!py-1 !text-sm"
                  onClick={() => setSortDir('asc')}
                >
                  A→Z
                </Button>
                <Button
                  variant={sortDir === 'desc' ? 'primary' : 'secondary'}
                  className="!py-1 !text-sm"
                  onClick={() => setSortDir('desc')}
                >
                  Z→A
                </Button>
              </div>
            </>
          )}
          <div className="flex gap-2">
            <Button
              variant={view === 'board' ? 'primary' : 'secondary'}
              className="!py-1 !text-sm"
              onClick={() => setViewAndSave('board')}
            >
              Board
            </Button>
            <Button
              variant={view === 'list' ? 'primary' : 'secondary'}
              className="!py-1 !text-sm"
              onClick={() => setViewAndSave('list')}
            >
              List
            </Button>
          </div>
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
            <p className="py-8 text-center text-gray-500 dark:text-gray-400">No jobs yet.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[500px]">
                <thead>
                  <tr className="border-b border-gray-200 text-left text-sm text-gray-600 dark:border-gray-600 dark:text-gray-300">
                    <th className="pb-2 pr-4 font-medium">Job #</th>
                    <th className="pb-2 pr-4 font-medium">Customer</th>
                    <th className="pb-2 pr-4 font-medium">Status</th>
                    <th className="pb-2 pr-4 font-medium">Due date</th>
                    <th className="pb-2 pr-4 font-medium">Ship date</th>
                    <th className="pb-2 pr-4 font-medium">Tracking</th>
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
                        <td className="py-3 pr-4 text-gray-700 dark:text-gray-300">
                          {job.expand?.customer?.company || job.customer_name || '—'}
                        </td>
                        <td className="py-3 pr-4">
                          <span
                            className={
                              'rounded-full border px-2 py-0.5 text-xs font-medium ' +
                              (COLUMNS.find((c) => c.id === (job.status || 'planning'))
                                ?.color ?? 'bg-gray-100 border-gray-200 text-gray-700 dark:bg-gray-600 dark:border-gray-500 dark:text-white')
                            }
                          >
                            {statusLabel(job.status)}
                          </span>
                        </td>
                        <td className="py-3 pr-4 text-gray-700 dark:text-gray-300">
                          {formatDate(job.due_date)}
                        </td>
                        <td className="py-3 pr-4 text-gray-700 dark:text-gray-300">
                          {formatDate(job.ship_date)}
                        </td>
                        <td className="py-3 pr-4">
                          {trackingUrl ? (
                            <a
                              href={trackingUrl}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="text-primary-from hover:underline"
                            >
                              Track
                            </a>
                          ) : (
                            '—'
                          )}
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
