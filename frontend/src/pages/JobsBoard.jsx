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
import { format } from 'date-fns'

const COLUMNS = [
  { id: 'planning', label: 'Planning', color: 'bg-blue-50 border-blue-200' },
  { id: 'in_progress', label: 'In Progress', color: 'bg-amber-50 border-amber-200' },
  { id: 'done', label: 'Done', color: 'bg-green-50 border-green-200' },
  { id: 'cancelled', label: 'Cancelled', color: 'bg-gray-100 border-gray-200' },
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
        'cursor-grab rounded-lg border-2 bg-white p-3 shadow card transition hover:shadow-md ' +
        (isDragOverlay ? 'cursor-grabbing shadow-lg' : '')
      }
    >
      <p className="font-medium text-gray-900">{job.job_number}</p>
      <p className="text-sm text-gray-600">{job.customer_name || '—'}</p>
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
      className={`flex overflow-hidden rounded-lg border-2 bg-white shadow transition hover:shadow-md ${isDragging ? 'opacity-50' : ''}`}
    >
      <div
        {...listeners}
        {...attributes}
        className="w-2 shrink-0 cursor-grab bg-gray-200 hover:bg-gray-300 active:cursor-grabbing"
        title="Drag to move"
      />
      <Link
        to={`/jobs/${job.id}`}
        className="min-w-0 flex-1 p-3 text-inherit no-underline hover:bg-gray-50/50"
      >
        <p className="font-medium text-gray-900">{job.job_number}</p>
        <p className="text-sm text-gray-600">{job.customer_name || '—'}</p>
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
      <h3 className="mb-3 font-semibold text-gray-800">{label}</h3>
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
  const [view, setView] = useState('board')
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
        <div className="py-8 text-center text-gray-500">Loading jobs…</div>
      </Layout>
    )
  }

  const mult = sortDir === 'asc' ? 1 : -1
  const sortedJobs = [...jobs].sort((a, b) => {
    if (sortKey === 'job_number') {
      return mult * String(a.job_number || '').localeCompare(String(b.job_number || ''), undefined, { numeric: true })
    }
    if (sortKey === 'customer') {
      const ca = a.customer_name || ''
      const cb = b.customer_name || ''
      return mult * String(ca).localeCompare(String(cb))
    }
    return 0
  })

  return (
    <Layout>
      <div className="mb-6 flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-2xl font-bold text-gray-900">Jobs</h1>
        <div className="flex flex-wrap items-center gap-4">
          {view === 'list' && (
            <>
              <span className="text-sm font-medium text-gray-600">Sort by</span>
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
              <span className="text-sm font-medium text-gray-600">Order</span>
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
              onClick={() => setView('board')}
            >
              Board
            </Button>
            <Button
              variant={view === 'list' ? 'primary' : 'secondary'}
              className="!py-1 !text-sm"
              onClick={() => setView('list')}
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
            <p className="py-8 text-center text-gray-500">No jobs yet.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[500px]">
                <thead>
                  <tr className="border-b border-gray-200 text-left text-sm text-gray-600">
                    <th className="pb-2 pr-4 font-medium">Job #</th>
                    <th className="pb-2 pr-4 font-medium">Customer</th>
                    <th className="pb-2 pr-4 font-medium">Status</th>
                    <th className="pb-2 pr-4 font-medium">Due date</th>
                    <th className="pb-2 pr-4 font-medium">Ship date</th>
                  </tr>
                </thead>
                <tbody>
                  {sortedJobs.map((job) => (
                    <tr
                      key={job.id}
                      className="border-b border-gray-100 hover:bg-gray-50/50"
                    >
                      <td className="py-3 pr-4">
                        <Link
                          to={`/jobs/${job.id}`}
                          className="font-medium text-primary-from hover:underline"
                        >
                          {job.job_number || '—'}
                        </Link>
                      </td>
                      <td className="py-3 pr-4 text-gray-700">
                        {job.customer_name || '—'}
                      </td>
                      <td className="py-3 pr-4">
                        <span
                          className={
                            'rounded-full border px-2 py-0.5 text-xs font-medium ' +
                            (COLUMNS.find((c) => c.id === (job.status || 'planning'))
                              ?.color ?? 'bg-gray-100 border-gray-200')
                          }
                        >
                          {statusLabel(job.status)}
                        </span>
                      </td>
                      <td className="py-3 pr-4 text-gray-700">
                        {formatDate(job.due_date)}
                      </td>
                      <td className="py-3 pr-4 text-gray-700">
                        {formatDate(job.ship_date)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      )}
    </Layout>
  )
}
