import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { Layout } from '../components/layout/Layout'
import { Card } from '../components/ui/Card'
import { Button } from '../components/ui/Button'
import { Input } from '../components/ui/Input'
import { Modal } from '../components/ui/Modal'
import { ConfirmDialog } from '../components/ui/ConfirmDialog'
import { getCustomers, createCustomer, updateCustomer, deleteCustomer } from '../lib/api'

const emptyCustomer = {
  name: '',
  company: '',
  email: '',
  phone: '',
  address: '',
  notes: '',
}

export function Customers() {
  const [list, setList] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [modalOpen, setModalOpen] = useState(false)
  const [editing, setEditing] = useState(null)
  const [form, setForm] = useState(emptyCustomer)
  const [saving, setSaving] = useState(false)
  const [deleteConfirm, setDeleteConfirm] = useState(null)

  function load() {
    setLoading(true)
    getCustomers()
      .then((res) => setList(res?.items ?? []))
      .catch(console.error)
      .finally(() => setLoading(false))
  }

  useEffect(() => {
    load()
  }, [])

  const filtered = list.filter(
    (c) =>
      !search ||
      [c.name, c.company, c.email, c.phone].some(
        (v) => v && String(v).toLowerCase().includes(search.toLowerCase())
      )
  )

  function openNew() {
    setEditing(null)
    setForm(emptyCustomer)
    setModalOpen(true)
  }

  function handleSave() {
    if (!form.name?.trim()) return
    setSaving(true)
    const payload = {
      name: form.name.trim(),
      company: form.company?.trim() || '',
      email: form.email?.trim() || '',
      phone: form.phone?.trim() || '',
      address: form.address?.trim() || '',
      notes: form.notes?.trim() || '',
    }
    ;(editing ? updateCustomer(editing.id, payload) : createCustomer(payload))
      .then(() => {
        setModalOpen(false)
        load()
      })
      .catch(console.error)
      .finally(() => setSaving(false))
  }

  function handleDelete() {
    if (!deleteConfirm) return
    deleteCustomer(deleteConfirm.id)
      .then(() => {
        setDeleteConfirm(null)
        load()
      })
      .catch(console.error)
  }

  return (
    <Layout>
      <div className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Customers</h1>
        <Button onClick={openNew}>+ New Customer</Button>
      </div>

      <Card className="mb-4">
        <Input
          placeholder="Search by name, company, email, phone..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </Card>

      <Card>
        {loading ? (
          <p className="py-8 text-center text-gray-500 dark:text-gray-400">Loading…</p>
        ) : filtered.length === 0 ? (
          <p className="py-8 text-center text-gray-500 dark:text-gray-400">
            {list.length === 0
              ? 'No customers yet. Add one with + New Customer.'
              : 'No customers match your search.'}
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-gray-200 text-left text-sm text-gray-600 dark:border-gray-600 dark:text-gray-300">
                  <th className="p-2 font-medium">Company</th>
                  <th className="p-2 font-medium">Name</th>
                  <th className="p-2 font-medium">Phone</th>
                  <th className="p-2 font-medium">Email</th>
                  <th className="p-2 font-medium">Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((c) => (
                  <tr
                    key={c.id}
                    className="border-b border-gray-100 hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-700/50"
                  >
                    <td className="p-2">
                      <Link
                        to={`/customers/${c.id}`}
                        className="text-primary-from hover:underline"
                      >
                        {c.company || '—'}
                      </Link>
                    </td>
                    <td className="p-2">
                      <Link
                        to={`/customers/${c.id}`}
                        className="text-primary-from hover:underline"
                      >
                        {c.name}
                      </Link>
                    </td>
                    <td className="p-2 text-gray-900 dark:text-gray-100">{c.phone || '—'}</td>
                    <td className="p-2 text-gray-900 dark:text-gray-100">{c.email || '—'}</td>
                    <td className="p-2">
                      <div className="flex flex-wrap items-center gap-2">
                        <Link to={`/customers/${c.id}`}>
                          <Button variant="secondary" className="!py-1 !text-sm">
                            View
                          </Button>
                        </Link>
                        <Button
                          variant="secondary"
                          className="!py-1 !text-sm text-red-600 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-900/40"
                          onClick={() => setDeleteConfirm(c)}
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
        title={editing ? 'Edit customer' : 'New customer'}
      >
        <div className="space-y-3">
          <Input
            label="Company"
            value={form.company}
            onChange={(e) => setForm((p) => ({ ...p, company: e.target.value }))}
          />
          <Input
            label="Name"
            value={form.name}
            onChange={(e) => setForm((p) => ({ ...p, name: e.target.value }))}
            required
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
          <Input
            label="Address"
            value={form.address}
            onChange={(e) => setForm((p) => ({ ...p, address: e.target.value }))}
          />
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
        title="Delete customer"
        message={
          deleteConfirm
            ? `Delete "${deleteConfirm.name}"? This won't remove them from existing quotes.`
            : ''
        }
        confirmLabel="Delete"
      />
    </Layout>
  )
}
