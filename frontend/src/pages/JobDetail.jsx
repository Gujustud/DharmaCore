import { useState, useEffect } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { Layout } from '../components/layout/Layout'
import { Card } from '../components/ui/Card'
import { Input } from '../components/ui/Input'
import { Button } from '../components/ui/Button'
import { ConfirmDialog } from '../components/ui/ConfirmDialog'
import { generateTrackingLink } from '../lib/calculations'
import { getJob, updateJob, deleteJob } from '../lib/api'
import { format } from 'date-fns'
import { PartImages } from '../components/PartImages'

const STATUS_OPTIONS = [
  { value: 'planning', label: 'Planning' },
  { value: 'in_progress', label: 'In Progress' },
  { value: 'done', label: 'Done' },
  { value: 'cancelled', label: 'Cancelled' },
]

const TRACKING_STATUS_OPTIONS = [
  { value: 'not_shipped', label: 'Not shipped' },
  { value: 'in_transit', label: 'In transit' },
  { value: 'delivered', label: 'Delivered' },
]

const STATUS_PILL_CLASS = {
  planning: 'bg-blue-100 text-blue-800 border-blue-200',
  in_progress: 'bg-amber-100 text-amber-800 border-amber-200',
  done: 'bg-green-100 text-green-800 border-green-200',
  cancelled: 'bg-gray-100 text-gray-600 border-gray-200',
}

const TRACKING_PILL_CLASS = {
  not_shipped: 'bg-gray-100 text-gray-600 border-gray-200',
  in_transit: 'bg-amber-50 text-amber-800 border-amber-200',
  delivered: 'bg-green-100 text-green-800 border-green-200',
}

function dateInputValue(d) {
  if (!d) return ''
  const x = typeof d === 'string' ? new Date(d) : d
  return format(x, 'yyyy-MM-dd')
}

/** Notion-style row: label left (fixed width), value right. */
function Row({ label, value, emptyLabel = 'Empty', children }) {
  const isEmpty = value == null || value === ''
  return (
    <div className="flex items-center gap-4 py-[10px] border-b border-gray-100 last:border-0">
      <span className="w-[140px] shrink-0 text-sm font-medium text-gray-500">
        {label}
      </span>
      <div className="min-w-0 flex-1 text-sm text-gray-900">
        {children != null ? children : (isEmpty ? <span className="text-gray-400">{emptyLabel}</span> : value)}
      </div>
    </div>
  )
}

export function JobDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [job, setJob] = useState(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [deleteConfirm, setDeleteConfirm] = useState(false)

  useEffect(() => {
    let cancelled = false
    async function load() {
      setLoading(true)
      try {
        const j = await getJob(id)
        if (!cancelled) setJob(j)
      } catch (e) {
        if (!cancelled) console.error(e)
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    load()
    return () => { cancelled = true }
  }, [id])

  const handleChange = (updates) => {
    setJob((prev) => (prev ? { ...prev, ...updates } : updates))
  }

  const link1 = job?.tracking_number_1
    ? generateTrackingLink(job.tracking_number_1)
    : ''
  const link2 = job?.tracking_number_2
    ? generateTrackingLink(job.tracking_number_2)
    : ''

  const save = async () => {
    if (!job) return
    setSaving(true)
    try {
      await updateJob(job.id, {
        status: job.status,
        due_date: job.due_date || null,
        completion_date: job.completion_date || null,
        ship_date: job.ship_date || null,
        tracking_status: job.tracking_status,
        tracking_number_1: job.tracking_number_1 || '',
        tracking_number_2: job.tracking_number_2 || '',
        wave_invoice_number: job.wave_invoice_number || '',
        po_number: job.po_number || '',
        material_lot: job.material_lot || '',
        material_source: job.material_source || '',
        material_notes: job.material_notes || '',
        project_notes: job.project_notes || '',
        notes: job.notes || '',
      })
    } catch (e) {
      console.error(e)
    } finally {
      setSaving(false)
    }
  }

  const handleDelete = async () => {
    if (!job?.id) return
    try {
      await deleteJob(job.id)
      navigate('/jobs')
    } catch (e) {
      console.error(e)
    }
  }

  if (loading || !job) {
    return (
      <Layout>
        <div className="py-8 text-center text-gray-500">Loading…</div>
      </Layout>
    )
  }

  const quoteId = job.expand?.quote?.id || job.quote
  const statusClass = STATUS_PILL_CLASS[job.status] || STATUS_PILL_CLASS.planning
  const trackingClass = TRACKING_PILL_CLASS[job.tracking_status] || TRACKING_PILL_CLASS.not_shipped

  return (
    <Layout>
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-bold text-gray-900">
          Job: {job.job_number}
        </h1>
        <div className="flex gap-2">
          {quoteId && (
            <Link to={`/quotes/${quoteId}`}>
              <Button variant="secondary">View Quote →</Button>
            </Link>
          )}
          <Button variant="secondary" onClick={() => navigate('/jobs')}>
            Back to Jobs
          </Button>
          <Button variant="secondary" disabled={saving} onClick={save}>
            {saving ? 'Saving…' : 'Save'}
          </Button>
          <Button
            variant="secondary"
            disabled={saving}
            onClick={() => setDeleteConfirm(true)}
          >
            Delete job
          </Button>
        </div>
      </div>

      <div className="flex flex-col gap-6 lg:flex-row lg:items-start">
        {/* Left column - Job details */}
        <div className="min-w-0 flex-1 lg:flex-1">
          <Card>
            <div className="divide-y divide-gray-100">
          <Row label="Status" value={job.status} emptyLabel="">
            <select
              className={`rounded-full border px-3 py-1 text-sm font-medium ${statusClass}`}
              value={job.status ?? 'planning'}
              onChange={(e) => handleChange({ status: e.target.value })}
            >
              {STATUS_OPTIONS.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
          </Row>

          <Row label="Ship Date" value={job.ship_date} emptyLabel="Empty">
            <input
              type="date"
              className="rounded-input border border-gray-300 px-2 py-1 text-sm focus:border-primary-from focus:outline-none"
              value={dateInputValue(job.ship_date)}
              onChange={(e) => handleChange({ ship_date: e.target.value || null })}
            />
          </Row>

          <Row label="Tracking Status" value={job.tracking_status} emptyLabel="">
            <select
              className={`rounded-full border px-3 py-1 text-sm font-medium ${trackingClass}`}
              value={job.tracking_status ?? 'not_shipped'}
              onChange={(e) => handleChange({ tracking_status: e.target.value })}
            >
              {TRACKING_STATUS_OPTIONS.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
          </Row>

          <Row label="# Tracking Number" value={job.tracking_number_1}>
            <input
              type="text"
              className="w-full max-w-sm rounded-input border border-gray-300 px-2 py-1 text-sm focus:border-primary-from focus:outline-none"
              value={job.tracking_number_1 ?? ''}
              onChange={(e) => handleChange({ tracking_number_1: e.target.value })}
            />
          </Row>

          <Row label="Tracking Link" value={link1}>
            {link1 ? (
              <a
                href={link1}
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary-from underline hover:no-underline"
              >
                {link1.length > 45 ? link1.slice(0, 42) + '…' : link1}
              </a>
            ) : null}
          </Row>

          <Row label="Due Date" value={job.due_date} emptyLabel="Empty">
            <input
              type="date"
              className="rounded-input border border-gray-300 px-2 py-1 text-sm focus:border-primary-from focus:outline-none"
              value={dateInputValue(job.due_date)}
              onChange={(e) => handleChange({ due_date: e.target.value || null })}
            />
          </Row>

          <Row label="Job" value={job.job_number}>
            <span className="text-gray-900">{job.job_number}</span>
          </Row>

          <Row label="Invoice" value={job.wave_invoice_number}>
            <input
              type="text"
              className="w-full max-w-[200px] rounded-input border border-gray-300 px-2 py-1 text-sm focus:border-primary-from focus:outline-none"
              value={job.wave_invoice_number ?? ''}
              onChange={(e) => handleChange({ wave_invoice_number: e.target.value })}
            />
          </Row>

          <Row label="PO #" value={job.po_number}>
            <input
              type="text"
              className="w-full max-w-[200px] rounded-input border border-gray-300 px-2 py-1 text-sm focus:border-primary-from focus:outline-none"
              value={job.po_number ?? ''}
              onChange={(e) => handleChange({ po_number: e.target.value })}
            />
          </Row>

          <Row label="Completion" value={job.completion_date} emptyLabel="Empty">
            <input
              type="date"
              className="rounded-input border border-gray-300 px-2 py-1 text-sm focus:border-primary-from focus:outline-none"
              value={dateInputValue(job.completion_date)}
              onChange={(e) =>
                handleChange({ completion_date: e.target.value || null })
              }
            />
          </Row>

          <Row label="Material LOT" value={job.material_lot}>
            <input
              type="text"
              className="w-full max-w-[200px] rounded-input border border-gray-300 px-2 py-1 text-sm focus:border-primary-from focus:outline-none"
              value={job.material_lot ?? ''}
              onChange={(e) => handleChange({ material_lot: e.target.value })}
            />
          </Row>

          <Row label="Material source" value={job.material_source}>
            <input
              type="text"
              className="w-full max-w-[200px] rounded-input border border-gray-300 px-2 py-1 text-sm focus:border-primary-from focus:outline-none"
              value={job.material_source ?? ''}
              onChange={(e) => handleChange({ material_source: e.target.value })}
            />
          </Row>

          <Row label="Tracking 2" value={job.tracking_number_2}>
            <input
              type="text"
              className="w-full max-w-sm rounded-input border border-gray-300 px-2 py-1 text-sm focus:border-primary-from focus:outline-none"
              value={job.tracking_number_2 ?? ''}
              onChange={(e) => handleChange({ tracking_number_2: e.target.value })}
            />
          </Row>

          <Row label="Tracking Link 2" value={link2}>
            {link2 ? (
              <a
                href={link2}
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary-from underline hover:no-underline"
              >
                {link2.length > 45 ? link2.slice(0, 42) + '…' : link2}
              </a>
            ) : null}
          </Row>

          <Row label="Attachments" value="" emptyLabel="Empty">
            <span className="text-gray-400">Empty</span>
          </Row>
            </div>
          </Card>
        </div>

        {/* Right column - Images and Notes */}
        <div className="w-full lg:flex-1 lg:sticky lg:top-4 space-y-6">
          <Card>
            <PartImages
              record={job}
              collectionName="jobs"
              title=""
              onUpdate={(updated) => {
                setJob((prev) => ({ ...prev, ...updated }))
              }}
            />
          </Card>

          <Card>
            <h2 className="mb-3 text-sm font-semibold text-gray-700">Notes</h2>
            <div className="space-y-3">
              <div>
                <label className="mb-1 block text-sm font-medium text-gray-500">
                  Project notes
                </label>
                <textarea
                  className="w-full rounded-input border border-gray-300 px-3 py-2 text-sm focus:border-primary-from focus:outline-none"
                  rows={3}
                  value={job.project_notes ?? ''}
                  onChange={(e) => handleChange({ project_notes: e.target.value })}
                />
              </div>
              {job.parts_description && (
                <div>
                  <p className="mb-1 text-sm font-medium text-gray-500">
                    Parts in this job
                  </p>
                  <pre className="whitespace-pre-wrap rounded bg-gray-50 p-2 text-sm text-gray-800">
                    {job.parts_description}
                  </pre>
                </div>
              )}
            </div>
          </Card>
        </div>
      </div>

      <ConfirmDialog
        open={deleteConfirm}
        onClose={() => setDeleteConfirm(false)}
        onConfirm={handleDelete}
        title="Delete job"
        message="Are you sure you want to delete this job?"
        confirmLabel="Delete"
      />
    </Layout>
  )
}
