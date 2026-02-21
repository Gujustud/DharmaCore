import { useState, useEffect } from 'react'
import { Layout } from '../components/layout/Layout'
import { Card } from '../components/ui/Card'
import { Button } from '../components/ui/Button'
import { Input } from '../components/ui/Input'
import { Modal } from '../components/ui/Modal'
import { ConfirmDialog } from '../components/ui/ConfirmDialog'
import { getVendors, createVendor, updateVendor, deleteVendor } from '../lib/api'

const VENDOR_TYPES = [
  { value: 'material_supplier', label: 'Material supplier' },
  { value: 'subcontractor', label: 'Subcontractor' },
  { value: 'other', label: 'Other' },
]

const emptyVendor = {
  name: '',
  vendor_type: 'material_supplier',
  contact_person: '',
  email: '',
  phone: '',
  services: '',
  notes: '',
}

export function Vendors() {
  const [list, setList] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [modalOpen, setModalOpen] = useState(false)
  const [editing, setEditing] = useState(null)
  const [form, setForm] = useState(emptyVendor)
  const [saving, setSaving] = useState(false)
  const [deleteConfirm, setDeleteConfirm] = useState(null)

  function load() {
    setLoading(true)
    getVendors()
      .then((res) => setList(res?.items ?? []))
      .catch(console.error)
      .finally(() => setLoading(false))
  }

  useEffect(() => {
    load()
  }, [])

  const filtered = list.filter((v) =>
    !search ||
    [v.name, v.contact_person, v.email, v.phone, v.services].some(
      (val) => val && String(val).toLowerCase().includes(search.toLowerCase())
    )
  )

  function openNew() {
    setEditing(null)
    setForm(emptyVendor)
    setModalOpen(true)
  }

  function openEdit(vendor) {
    setEditing(vendor)
    setForm({
      name: vendor.name ?? '',
      vendor_type: vendor.vendor_type ?? 'material_supplier',
      contact_person: vendor.contact_person ?? '',
      email: vendor.email ?? '',
      phone: vendor.phone ?? '',
      services: vendor.services ?? '',
      notes: vendor.notes ?? '',
    })
    setModalOpen(true)
  }

  function handleSave() {
    if (!form.name?.trim()) return
    setSaving(true)
    const payload = {
      name: form.name.trim(),
      vendor_type: form.vendor_type,
      contact_person: form.contact_person?.trim() || '',
      email: form.email?.trim() || '',
      phone: form.phone?.trim() || '',
      services: form.services?.trim() || '',
      notes: form.notes?.trim() || '',
    }
    ;(editing ? updateVendor(editing.id, payload) : createVendor(payload))
      .then(() => {
        setModalOpen(false)
        load()
      })
      .catch(console.error)
      .finally(() => setSaving(false))
  }

  function handleDelete() {
    if (!deleteConfirm) return
    deleteVendor(deleteConfirm.id)
      .then(() => {
        setDeleteConfirm(null)
        load()
      })
      .catch(console.error)
  }

  return (
    <Layout>
      <div className="mb-6 flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Vendors</h1>
        <div className="flex flex-nowrap items-center gap-3">
          <Input
            type="search"
            placeholder="Search…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="min-w-0 max-w-[220px] shrink-0"
          />
          <Button onClick={openNew} className="whitespace-nowrap shrink-0">
            New Vendor
          </Button>
        </div>
      </div>

      <Card>
        {loading ? (
          <p className="py-8 text-center text-gray-500 dark:text-gray-400">Loading…</p>
        ) : filtered.length === 0 ? (
          <p className="py-8 text-center text-gray-500 dark:text-gray-400">
            {list.length === 0
              ? 'No vendors yet. Add one with New Vendor.'
              : 'No vendors match your search.'}
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-gray-200 text-left text-sm text-gray-600 dark:border-gray-600 dark:text-gray-300">
                  <th className="p-2 font-medium">Name</th>
                  <th className="p-2 font-medium">Type</th>
                  <th className="p-2 font-medium">Contact</th>
                  <th className="p-2 font-medium">Phone</th>
                  <th className="p-2 font-medium">Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((v) => (
                  <tr
                    key={v.id}
                    className="border-b border-gray-100 hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-700/50"
                  >
                    <td className="p-2">
                      <button
                        type="button"
                        onClick={() => openEdit(v)}
                        className="text-left text-primary-from hover:underline"
                      >
                        {v.name}
                      </button>
                    </td>
                    <td className="p-2 text-gray-900 dark:text-gray-100">
                      {VENDOR_TYPES.find((t) => t.value === v.vendor_type)?.label ??
                        v.vendor_type}
                    </td>
                    <td className="p-2 text-gray-900 dark:text-gray-100">{v.contact_person || '—'}</td>
                    <td className="p-2 text-gray-900 dark:text-gray-100">{v.phone || '—'}</td>
                    <td className="p-2">
                      <div className="flex flex-wrap items-center gap-2">
                        <Button
                          variant="secondary"
                          className="!py-1 !text-sm"
                          onClick={() => openEdit(v)}
                        >
                          Edit
                        </Button>
                        <Button
                          variant="secondary"
                          className="!py-1 !text-sm text-red-600 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-900/40"
                          onClick={() => setDeleteConfirm(v)}
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

      <Modal
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        title={editing ? 'Edit vendor' : 'New vendor'}
      >
        <div className="space-y-3">
          <Input
            label="Name"
            value={form.name}
            onChange={(e) => setForm((p) => ({ ...p, name: e.target.value }))}
            required
          />
          <div>
            <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
              Type
            </label>
            <select
              className="w-full rounded-input border-2 border-gray-300 px-3 py-2 focus:border-primary-from focus:outline-none dark:border-gray-600 dark:bg-gray-700 dark:text-gray-100"
              value={form.vendor_type}
              onChange={(e) =>
                setForm((p) => ({ ...p, vendor_type: e.target.value }))
              }
            >
              {VENDOR_TYPES.map((t) => (
                <option key={t.value} value={t.value}>
                  {t.label}
                </option>
              ))}
            </select>
          </div>
          <Input
            label="Contact person"
            value={form.contact_person}
            onChange={(e) =>
              setForm((p) => ({ ...p, contact_person: e.target.value }))
            }
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
          <div>
            <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
              Services
            </label>
            <input
              type="text"
              className="w-full rounded-input border-2 border-gray-300 px-3 py-2 focus:border-primary-from focus:outline-none dark:border-gray-600 dark:bg-gray-700 dark:text-gray-100"
              placeholder="e.g. Anodizing, Powder Coating"
              value={form.services}
              onChange={(e) =>
                setForm((p) => ({ ...p, services: e.target.value }))
              }
            />
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
              Notes
            </label>
            <textarea
              className="w-full rounded-input border-2 border-gray-300 px-3 py-2 focus:border-primary-from focus:outline-none dark:border-gray-600 dark:bg-gray-700 dark:text-gray-100"
              rows={3}
              value={form.notes}
              onChange={(e) => setForm((p) => ({ ...p, notes: e.target.value }))}
            />
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="secondary" onClick={() => setModalOpen(false)}>
              Cancel
            </Button>
            <Button disabled={saving || !form.name?.trim()} onClick={handleSave}>
              {saving ? 'Saving…' : 'Save'}
            </Button>
          </div>
        </div>
      </Modal>

      <ConfirmDialog
        open={!!deleteConfirm}
        onClose={() => setDeleteConfirm(null)}
        onConfirm={handleDelete}
        title="Delete vendor"
        message={
          deleteConfirm
            ? `Delete "${deleteConfirm.name}"? This won't remove them from existing quotes or line items.`
            : ''
        }
        confirmLabel="Delete"
      />
    </Layout>
  )
}
