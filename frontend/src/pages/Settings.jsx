import { useState, useEffect } from 'react'
import Papa from 'papaparse'
import { Layout } from '../components/layout/Layout'
import { Card } from '../components/ui/Card'
import { Input } from '../components/ui/Input'
import { Button } from '../components/ui/Button'
import { useTheme } from '../contexts/ThemeContext'
import { getSettings, createSettings, updateSettings, getQuotes, createQuote, getCustomers } from '../lib/api'
import { fetchExchangeRate } from '../lib/exchangeRate'
import { csvRowToQuote } from '../lib/notionCsvImport'
import { pb } from '../lib/pocketbase'
import { format } from 'date-fns'

const DEFAULT_SETTINGS = {
  default_shipping_markup_percent: 30,
  default_final_markup_percent: 0,
  exchange_rate_usd_to_cad: 1.3,
  exchange_rate_auto_update: false,
  default_hourly_rate_programming: 350,
  default_hourly_rate_setup: 350,
  default_hourly_rate_first_run: 350,
  default_hourly_rate_production: 269,
  auto_logout_minutes: 0,
}

const CUSTOMER_CODE_MAP = {
  MRL: 'Meta Platforms Technologies, LLC',
  META: 'Meta Platforms Technologies, LLC',
}

const normalizeName = (s) =>
  (s == null ? '' : String(s).toLowerCase().replace(/\s+/g, ' ').trim())

export function Settings() {
  const [settings, setSettings] = useState(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [fetchingRate, setFetchingRate] = useState(false)
  const [message, setMessage] = useState(null)
  const [importFile, setImportFile] = useState(null)
  const [importing, setImporting] = useState(false)
  const [importResult, setImportResult] = useState(null)
  const [importPreview, setImportPreview] = useState([])
  const [importDefaults, setImportDefaults] = useState(null)
  const [importCustomers, setImportCustomers] = useState([])
  const [exchangeRateInput, setExchangeRateInput] = useState(undefined)
  const { isDark, setDark } = useTheme()

  useEffect(() => {
    let cancelled = false
    async function load() {
      setLoading(true)
      try {
        let s = await getSettings()
        if (!cancelled && !s) {
          s = await createSettings(DEFAULT_SETTINGS)
        }
        if (!cancelled) setSettings(s ? { ...DEFAULT_SETTINGS, ...s } : null)
      } catch (e) {
        if (!cancelled) console.error(e)
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    load()
    return () => { cancelled = true }
  }, [])

  const handleChange = (field, value) => {
    setSettings((prev) => (prev ? { ...prev, [field]: value } : null))
  }

  const handleSave = async () => {
    if (!settings?.id) return
    setSaving(true)
    setMessage(null)
    try {
      const { id, created, updated, expand, ...toSave } = settings
      await updateSettings(id, toSave)
      setMessage('Settings saved.')
      setTimeout(() => setMessage(null), 3000)
    } catch (e) {
      console.error(e)
      setMessage('Failed to save. Check the console.')
    } finally {
      setSaving(false)
    }
  }

  const handleFetchRate = async () => {
    setFetchingRate(true)
    setMessage(null)
    try {
      const rate = await fetchExchangeRate()
      if (rate != null) {
        setExchangeRateInput(undefined)
        setSettings((prev) =>
          prev
            ? {
                ...prev,
                exchange_rate_usd_to_cad: rate,
                exchange_rate_last_updated: new Date().toISOString(),
              }
            : null
        )
        setMessage(`Rate updated to ${rate.toFixed(4)}. Click Save to store.`)
      } else {
        setMessage('Could not fetch rate. Try again later.')
      }
      setTimeout(() => setMessage(null), 5000)
    } catch (e) {
      console.error(e)
      setMessage('Failed to fetch rate.')
    } finally {
      setFetchingRate(false)
    }
  }

  const handleFileSelected = async (file) => {
    setImportFile(file)
    setImportResult(null)
    setImportPreview([])
    if (!file) return

    setImporting(true)
    try {
      const text = await file.text()
      const parsed = Papa.parse(text, { header: true, skipEmptyLines: true })
      const rows = parsed.data?.filter((r) => r && Object.keys(r).length > 0) ?? []

      const settingsData = await getSettings()
      const defaults = settingsData ? { ...DEFAULT_SETTINGS, ...settingsData } : DEFAULT_SETTINGS
      setImportDefaults(defaults)

      const [quotesRes, customersRes] = await Promise.all([
        getQuotes({ perPage: 500 }),
        getCustomers({ perPage: 500 }),
      ])

      const existingJobNumbers = new Set((quotesRes?.items ?? []).map((q) => q.job_number))
      const customers = customersRes?.items ?? []
      setImportCustomers(customers)
      const customersByName = new Map(
        customers.map((c) => [normalizeName(c.company || c.name || ''), c])
      )

      const preview = []
      let index = 0

      for (const row of rows) {
        const base = csvRowToQuote(row, defaults)
        if (!base) continue

        const isDuplicate = existingJobNumbers.has(base.job_number)

        const rawCode = base.customer_code || ''
        const customerCode = rawCode.toUpperCase()
        const mappedNameFromCode = CUSTOMER_CODE_MAP[customerCode]
        const effectiveName = mappedNameFromCode || base.customer_name || ''

        const matchedCustomer =
          effectiveName && customersByName.get(normalizeName(effectiveName))

        preview.push({
          id: index++,
          include: !isDuplicate,
          isDuplicate,
          job_number: base.job_number,
          customer_code: customerCode,
          customer_name: effectiveName,
          matchedCustomerName: matchedCustomer
            ? matchedCustomer.company || matchedCustomer.name || ''
            : '',
          customerId: matchedCustomer ? matchedCustomer.id : null,
          status: base.status,
          po_number: base.po_number,
          engineer: base.engineer,
          wave_quote_number: base.wave_quote_number,
          final_total_cad: base.final_total_cad,
          notes: base.notes || '',
        })
      }

      setImportPreview(preview)
    } catch (e) {
      console.error(e)
      setImportResult({
        imported: 0,
        skipped: 0,
        error: e?.message || 'Failed to read CSV.',
      })
    } finally {
      setImporting(false)
    }
  }

  const togglePreviewRowInclude = (id) => {
    setImportPreview((rows) =>
      rows.map((r) => (r.id === id ? { ...r, include: !r.include } : r))
    )
  }

  const handlePreviewCustomerChange = (rowId, customerId) => {
    setImportPreview((rows) =>
      rows.map((r) => {
        if (r.id !== rowId) return r
        if (!customerId) {
          return { ...r, customerId: null, matchedCustomerName: '' }
        }
        const customer = importCustomers.find((c) => c.id === customerId)
        const displayName = customer ? customer.company || customer.name || '' : ''
        return {
          ...r,
          customerId,
          matchedCustomerName: displayName,
          customer_name: r.customer_name || displayName,
        }
      })
    )
  }

  const handleImportFromNotion = async () => {
    if (!importPreview.length || !importDefaults) return
    setImporting(true)
    setImportResult(null)
    try {
      let imported = 0
      let skipped = 0

      for (const row of importPreview) {
        if (!row.include) {
          skipped += 1
          continue
        }

        const payload = {
          job_number: row.job_number,
          customer: row.customerId || undefined,
          customer_name: row.customer_name || '',
          status: row.status,
          engineer: row.engineer,
          po_number: row.po_number || '',
          wave_quote_number: row.wave_quote_number || '',
          notes: row.notes || '',
          exchange_rate_usd_to_cad:
            importDefaults.exchange_rate_usd_to_cad ?? DEFAULT_SETTINGS.exchange_rate_usd_to_cad,
          hourly_rate_programming:
            importDefaults.default_hourly_rate_programming ??
            importDefaults.hourly_rate_programming ??
            DEFAULT_SETTINGS.default_hourly_rate_programming,
          hourly_rate_setup:
            importDefaults.default_hourly_rate_setup ??
            importDefaults.hourly_rate_setup ??
            DEFAULT_SETTINGS.default_hourly_rate_setup,
          hourly_rate_first_run:
            importDefaults.default_hourly_rate_first_run ??
            importDefaults.hourly_rate_first_run ??
            DEFAULT_SETTINGS.default_hourly_rate_first_run,
          hourly_rate_production:
            importDefaults.default_hourly_rate_production ??
            importDefaults.hourly_rate_production ??
            DEFAULT_SETTINGS.default_hourly_rate_production,
        }

        if (row.final_total_cad != null) {
          payload.final_total_cad = row.final_total_cad
        }

        try {
          await createQuote(payload)
          imported += 1
        } catch (e) {
          console.error('Import failed for row payload:', payload, 'error:', e, 'data:', e?.data)
          skipped += 1
        }
      }

      setImportResult({ imported, skipped })
    } catch (e) {
      console.error(e)
      setImportResult({
        imported: 0,
        skipped: 0,
        error: e?.message || 'Import failed.',
      })
    } finally {
      setImporting(false)
    }
  }

  if (loading || !settings) {
    return (
      <Layout>
        <div className="py-8 text-center text-gray-500 dark:text-gray-400">Loading settings…</div>
      </Layout>
    )
  }

  const num = (v) => (v === '' || v == null ? '' : Number(v))
  const isJobsOnly = pb.authStore.model?.role === 'jobs_only'

  return (
    <Layout>
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Settings</h1>
        <Button disabled={saving} onClick={handleSave}>
          {saving ? 'Saving…' : 'Save'}
        </Button>
      </div>

      {message && (
        <p className="mb-4 rounded-lg bg-gray-100 px-3 py-2 text-sm text-gray-700 dark:bg-gray-700 dark:text-gray-200">
          {message}
        </p>
      )}

      <div className="grid gap-4 sm:grid-cols-2 sm:items-start">
        <div className="flex flex-col gap-4">
        <Card>
          <h2 className="mb-2 text-lg font-semibold text-gray-900 dark:text-white">
            Appearance
          </h2>
          <div className="flex items-center justify-between gap-4">
            <div>
              <label htmlFor="dark-mode" className="text-sm font-medium text-gray-700 dark:text-gray-300">
                Dark mode
              </label>
              <p className="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
                Applies immediately. No need to click Save.
              </p>
            </div>
            <button
              id="dark-mode"
              type="button"
              role="switch"
              aria-checked={isDark}
              onClick={() => {
                const next = !isDark
                document.documentElement.classList.toggle('dark', next)
                try {
                  localStorage.setItem('darkMode', next ? 'true' : 'false')
                } catch (_) {}
                setDark(next)
              }}
              className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors focus:outline-none focus:ring-2 focus:ring-primary-from focus:ring-offset-2 dark:focus:ring-offset-gray-800 ${
                isDark ? 'bg-primary-from' : 'bg-gray-200 dark:bg-gray-600'
              }`}
            >
              <span
                className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition ${
                  isDark ? 'translate-x-5' : 'translate-x-0.5'
                }`}
                aria-hidden
              />
            </button>
          </div>
        </Card>

        {!isJobsOnly && (
          <Card>
            <h2 className="mb-2 text-lg font-semibold text-gray-900 dark:text-white">
              Default markups
            </h2>
            <p className="mb-3 text-sm text-gray-500 dark:text-gray-400">
              Used when creating a new quote.
            </p>
            <div className="grid gap-3 sm:grid-cols-2">
              <Input
                type="number"
                label="Shipping markup (%)"
                value={settings.default_shipping_markup_percent ?? ''}
                onChange={(e) =>
                  handleChange('default_shipping_markup_percent', num(e.target.value))
                }
              />
              <Input
                type="number"
                label="Final markup (%)"
                value={settings.default_final_markup_percent ?? ''}
                onChange={(e) =>
                  handleChange('default_final_markup_percent', num(e.target.value))
                }
              />
            </div>
          </Card>
        )}

        {!isJobsOnly && (
        <Card>
          <h2 className="mb-2 text-lg font-semibold text-gray-900 dark:text-white">
            Default hourly rates (CAD)
          </h2>
          <p className="mb-3 text-sm text-gray-500 dark:text-gray-400">
            Used when creating a new quote.
          </p>
          <div className="grid gap-3 sm:grid-cols-2">
            <Input
              type="number"
              label="Programming"
              value={settings.default_hourly_rate_programming ?? ''}
              onChange={(e) =>
                handleChange('default_hourly_rate_programming', num(e.target.value))
              }
            />
            <Input
              type="number"
              label="Setup"
              value={settings.default_hourly_rate_setup ?? ''}
              onChange={(e) =>
                handleChange('default_hourly_rate_setup', num(e.target.value))
              }
            />
            <Input
              type="number"
              label="First run"
              value={settings.default_hourly_rate_first_run ?? ''}
              onChange={(e) =>
                handleChange('default_hourly_rate_first_run', num(e.target.value))
              }
            />
            <Input
              type="number"
              label="Production"
              value={settings.default_hourly_rate_production ?? ''}
              onChange={(e) =>
                handleChange('default_hourly_rate_production', num(e.target.value))
              }
            />
          </div>
        </Card>
        )}
        </div>

        <div className="flex flex-col gap-4">
        {!isJobsOnly && (
        <Card>
          <h2 className="mb-2 text-lg font-semibold text-gray-900 dark:text-white">
            Exchange rate (USD → CAD)
          </h2>
          <p className="mb-3 text-sm text-gray-500 dark:text-gray-400">
            Used for converting material costs and quote totals. Fetch from Bank of Canada or enter manually.
          </p>
          <div className="flex flex-wrap items-end gap-3">
            <Input
              type="number"
              step="any"
              label="Rate"
              value={exchangeRateInput !== undefined ? exchangeRateInput : (settings.exchange_rate_usd_to_cad ?? '')}
              onChange={(e) => setExchangeRateInput(e.target.value)}
              onBlur={() => {
                const raw = exchangeRateInput
                setExchangeRateInput(undefined)
                if (raw === '' || raw === undefined) return
                const n = Number(raw)
                if (!Number.isNaN(n) && n >= 0) {
                  handleChange('exchange_rate_usd_to_cad', n)
                }
              }}
              className="max-w-[140px]"
            />
            <Button
              variant="secondary"
              disabled={fetchingRate}
              onClick={handleFetchRate}
            >
              {fetchingRate ? 'Fetching…' : 'Fetch latest rate'}
            </Button>
          </div>
          {settings.exchange_rate_last_updated && (
            <p className="mt-2 text-sm text-gray-500 dark:text-gray-400">
              Last updated: {format(new Date(settings.exchange_rate_last_updated), 'MMM d, yyyy HH:mm')}
            </p>
          )}
          <div className="mt-3">
            <label className="flex cursor-pointer items-center gap-2">
              <input
                type="checkbox"
                checked={!!settings.exchange_rate_auto_update}
                onChange={(e) => handleChange('exchange_rate_auto_update', e.target.checked)}
                className="rounded border-gray-300 dark:border-gray-600"
              />
              <span className="text-sm font-medium text-gray-700 dark:text-gray-300">
                Auto-update rate (e.g. on app load)
              </span>
            </label>
            <p className="mt-1 text-xs text-gray-500 dark:text-gray-400">
              When enabled, the app can refresh the rate automatically. Manual fetch still available above.
            </p>
          </div>
        </Card>
        )}

        {!isJobsOnly && (
        <Card>
          <h2 className="mb-2 text-lg font-semibold text-gray-900 dark:text-white">
            Import from Notion
          </h2>
          <p className="mb-3 text-sm text-gray-500 dark:text-gray-400">
            One-time import: export your Notion database as CSV (⋯ → Export → CSV), then upload here. Rows with a duplicate Job # are skipped. Images are not imported.
          </p>
          <div className="flex flex-wrap items-center gap-3">
            <input
              key={importResult ? `done-${importResult.imported}-${importResult.skipped}` : 'input'}
              type="file"
              accept=".csv"
              onChange={(e) => {
                const file = e.target.files?.[0] ?? null
                setImportResult(null)
                setImportPreview([])
                if (file) {
                  handleFileSelected(file)
                } else {
                  setImportFile(null)
                }
              }}
              className="block text-sm text-gray-600 file:mr-3 file:rounded file:border-0 file:bg-gray-100 file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-gray-700 hover:file:bg-gray-200 dark:text-gray-300 dark:file:bg-gray-600 dark:file:text-gray-200 dark:hover:file:bg-gray-500"
            />
            <Button
              variant="secondary"
              disabled={!importPreview.length || importing}
              onClick={handleImportFromNotion}
            >
              {importing ? 'Importing…' : 'Import'}
            </Button>
            {importPreview.length > 0 && (
              <div className="flex items-center gap-2 text-xs text-gray-600 dark:text-gray-400">
                <button
                  type="button"
                  onClick={() =>
                    setImportPreview((rows) => rows.map((r) => ({ ...r, include: false })))
                  }
                  className="underline hover:text-gray-900 dark:hover:text-white"
                >
                  Uncheck all
                </button>
                <span aria-hidden="true">·</span>
                <button
                  type="button"
                  onClick={() =>
                    setImportPreview((rows) => rows.map((r) => ({ ...r, include: true })))
                  }
                  className="underline hover:text-gray-900 dark:hover:text-white"
                >
                  Check all
                </button>
              </div>
            )}
          </div>
          {importPreview.length > 0 && (
            <div className="mt-4 overflow-x-auto">
              <table className="w-full min-w-[500px] text-sm">
                <thead>
                  <tr className="border-b border-gray-200 text-left text-gray-600 dark:border-gray-600 dark:text-gray-300">
                    <th className="pb-2 pr-3 font-medium">Import</th>
                    <th className="pb-2 pr-3 font-medium">Job #</th>
                    <th className="pb-2 pr-3 font-medium">Code</th>
                    <th className="pb-2 pr-3 font-medium">Customer name</th>
                    <th className="pb-2 pr-3 font-medium">Matched customer</th>
                    <th className="pb-2 pr-3 font-medium">Status</th>
                    <th className="pb-2 pr-3 font-medium">PO</th>
                    <th className="pb-2 font-medium">Notes</th>
                  </tr>
                </thead>
                <tbody>
                  {importPreview.map((row) => (
                    <tr key={row.id} className="border-b border-gray-100 align-top dark:border-gray-700">
                      <td className="py-2 pr-3">
                        <input
                          type="checkbox"
                          checked={row.include}
                          onChange={() => togglePreviewRowInclude(row.id)}
                          className="h-4 w-4 rounded border-gray-300 dark:border-gray-600"
                        />
                      </td>
                      <td className="py-2 pr-3 font-mono text-xs sm:text-sm">
                        {row.job_number}
                      </td>
                      <td className="py-2 pr-3 text-xs sm:text-sm">{row.customer_code}</td>
                      <td className="py-2 pr-3 text-xs sm:text-sm">
                        {row.customer_name || '—'}
                      </td>
                      <td className="py-2 pr-3 text-xs sm:text-sm">
                        <select
                          value={row.customerId || ''}
                          onChange={(e) => handlePreviewCustomerChange(row.id, e.target.value || null)}
                          className="max-w-[220px] rounded border border-gray-300 bg-white px-1 py-0.5 text-xs sm:text-sm dark:border-gray-600 dark:bg-gray-700 dark:text-gray-100"
                        >
                          <option value="">— None —</option>
                          {importCustomers.map((c) => (
                            <option key={c.id} value={c.id}>
                              {c.company || c.name || ''}
                            </option>
                          ))}
                        </select>
                        {row.matchedCustomerName && !row.customerId && (
                          <div className="mt-0.5 text-[10px] text-gray-500 dark:text-gray-400">
                            Suggested: {row.matchedCustomerName}
                          </div>
                        )}
                      </td>
                      <td className="py-2 pr-3 text-xs sm:text-sm">{row.status}</td>
                      <td className="py-2 pr-3 text-xs sm:text-sm">
                        {row.po_number || '—'}
                      </td>
                      <td className="py-2 text-xs sm:text-sm">
                        {row.isDuplicate && (
                          <span className="text-red-600">
                            Duplicate Job # (skipped by default)
                          </span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          {importResult && (
            <p className="mt-2 text-sm text-gray-700 dark:text-gray-300">
              {importResult.error ? (
                <span className="text-red-600">{importResult.error}</span>
              ) : (
                <>Imported {importResult.imported} quote{importResult.imported !== 1 ? 's' : ''}.{importResult.skipped > 0 && <> {importResult.skipped} skipped (duplicate Job #).</>}</>
              )}
            </p>
          )}
        </Card>
        )}

        <Card>
          <h2 className="mb-2 text-lg font-semibold text-gray-900 dark:text-white">
            Session
          </h2>
          <p className="mb-3 text-sm text-gray-500 dark:text-gray-400">
            Automatically log out after a period of inactivity. Set to 0 to disable.
          </p>
          <Input
            type="number"
            min={0}
            label="Auto-logout after (minutes)"
            value={settings.auto_logout_minutes ?? ''}
            onChange={(e) =>
              handleChange('auto_logout_minutes', e.target.value === '' ? '' : num(e.target.value))
            }
            className="max-w-[140px]"
          />
        </Card>
        </div>
      </div>
    </Layout>
  )
}
