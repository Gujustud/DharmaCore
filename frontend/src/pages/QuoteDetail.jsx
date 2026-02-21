import { useState, useEffect, useMemo } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { Layout } from '../components/layout/Layout'
import { Card } from '../components/ui/Card'
import { Input } from '../components/ui/Input'
import { Button } from '../components/ui/Button'
import { ConfirmDialog } from '../components/ui/ConfirmDialog'
import { Modal } from '../components/ui/Modal'
import { LineItemCard } from '../components/quote/LineItemCard'
import { QuoteTotals } from '../components/quote/QuoteTotals'
import { PartImages } from '../components/PartImages'
import {
  calculateLineItem,
  calculateQuoteTotals,
  generateJobNumber,
  generatePartsDescription,
  round2,
} from '../lib/calculations'
import { fetchExchangeRate } from '../lib/exchangeRate'
import {
  getQuote,
  createQuote,
  updateQuote,
  deleteQuote,
  getQuoteLineItems,
  createLineItem,
  updateLineItem,
  deleteLineItem,
  getAlloys,
  ensureAlloy,
  getCustomers,
  createCustomer,
  getVendors,
  getSettings,
  getJobByQuote,
  createJob,
} from '../lib/api'

const STATUS_OPTIONS = [
  { value: 'draft', label: 'Draft' },
  { value: 'sent', label: 'Sent' },
  { value: 'won', label: 'Won' },
  { value: 'lost', label: 'Lost' },
]

function getQuoteSettings(quote) {
  return {
    exchange_rate_usd_to_cad: quote?.exchange_rate_usd_to_cad ?? 1.3,
    final_markup_percent: quote?.final_markup_percent ?? 0,
    shipping_markup_percent: quote?.shipping_markup_percent ?? 30,
    subcontractor_markup_percent: quote?.subcontractor_markup_percent ?? 0,
    hourly_rate_programming: quote?.hourly_rate_programming ?? 350,
    hourly_rate_setup: quote?.hourly_rate_setup ?? 350,
    hourly_rate_first_run: quote?.hourly_rate_first_run ?? 350,
    hourly_rate_production: quote?.hourly_rate_production ?? 269,
  }
}

export function QuoteDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [quote, setQuote] = useState(null)
  const [lineItems, setLineItems] = useState([])
  const [customers, setCustomers] = useState([])
  const [vendors, setVendors] = useState([])
  const [alloyOptions, setAlloyOptions] = useState([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(() => id === 'new' || !id)
  const [deleteConfirm, setDeleteConfirm] = useState(false)
  const [jobId, setJobId] = useState(null)
  const [fetchingRate, setFetchingRate] = useState(false)
  const [saveError, setSaveError] = useState(null)
  const [saveSuccess, setSaveSuccess] = useState(false)
  const [addCustomerOpen, setAddCustomerOpen] = useState(false)
  const [newCustomerForm, setNewCustomerForm] = useState({ name: '', company: '', email: '', phone: '' })
  const [addingCustomer, setAddingCustomer] = useState(false)
  const [exchangeRateInput, setExchangeRateInput] = useState(undefined)
  // When user edits Programming $/hr, copy to Setup/First run/Production unless they've been manually edited
  const [ratesEditedByUser, setRatesEditedByUser] = useState({
    setup: false,
    firstRun: false,
    production: false,
  })

  // Treat as new only when URL is new and we don't yet have a saved quote id (avoids re-create after first save before nav completes)
  const isNew = (!id || id === 'new') && !quote?.id

  // Ensure API record has created/updated on the plain object (SDK may return Record instance)
  const normalizeQuoteRecord = (r) => {
    if (!r || typeof r !== 'object') return r
    const plain = typeof r.publicExport === 'function' ? r.publicExport() : { ...r }
    return {
      ...plain,
      created: plain.created ?? r.created ?? plain.updated ?? r.updated,
      updated: plain.updated ?? r.updated ?? plain.created ?? r.created,
    }
  }

  // Prefer our own quote_created_date field; fall back to PB created/updated
  const quoteCreatedDate = useMemo(() => {
    const raw = quote?.quote_created_date ?? quote?.created ?? quote?.updated
    if (raw == null || raw === '') return null
    try {
      const d = new Date(raw)
      return isNaN(d.getTime()) ? null : d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
    } catch {
      return null
    }
  }, [quote?.quote_created_date, quote?.created, quote?.updated])

  // Reset "rates edited by user" when switching to a different quote
  useEffect(() => {
    setRatesEditedByUser({ setup: false, firstRun: false, production: false })
  }, [quote?.id])

  const quoteSettings = useMemo(() => getQuoteSettings(quote), [quote])

  const calculatedLineItems = useMemo(
    () =>
      lineItems.map((item) => calculateLineItem(item, quoteSettings)),
    [lineItems, quoteSettings]
  )

  const calculatedQuote = useMemo(
    () => calculateQuoteTotals(quote || {}, calculatedLineItems),
    [quote, calculatedLineItems]
  )

  const alloySuggestions = useMemo(() => {
    const fromItems = (lineItems || [])
      .map((i) => (i.alloy != null ? String(i.alloy).trim() : ''))
      .filter(Boolean)
    return [...new Set([...alloyOptions, ...fromItems])].sort((a, b) =>
      a.localeCompare(b, undefined, { sensitivity: 'base' })
    )
  }, [alloyOptions, lineItems])

  useEffect(() => {
    let cancelled = false
    const LOAD_TIMEOUT_MS = 8000

    async function load() {
      setLoading(true)
      try {
        const timeoutPromise = new Promise((_, reject) =>
          setTimeout(() => reject(new Error('Load timeout')), LOAD_TIMEOUT_MS)
        )

        const loadPromise = (async () => {
          const [customersSettled, vendorsSettled, settingsSettled] =
            await Promise.allSettled([
              getCustomers(),
              getVendors(),
              getSettings(),
            ])
          const customersRes = customersSettled.status === 'fulfilled' ? customersSettled.value : null
          const vendorsRes = vendorsSettled.status === 'fulfilled' ? vendorsSettled.value : null
          const settings = settingsSettled.status === 'fulfilled' ? settingsSettled.value : null

          if (cancelled) return
          setCustomers(customersRes?.items ?? [])
          setVendors(vendorsRes?.items ?? [])

          // Only fetch by id when URL has a real record id (never call getQuote('new'))
          if (!id || id === 'new') {
            if (!quote?.id) {
              const jobNumber = generateJobNumber()
              const defaults = {
                job_number: jobNumber,
                engineer: '',
                status: 'draft',
                shipping_markup_percent: settings?.default_shipping_markup_percent ?? 30,
                final_markup_percent: settings?.default_final_markup_percent ?? 0,
                subcontractor_markup_percent: 0,
                exchange_rate_usd_to_cad: settings?.exchange_rate_usd_to_cad ?? 1.3,
                hourly_rate_programming: settings?.default_hourly_rate_programming ?? 350,
                hourly_rate_setup: settings?.default_hourly_rate_setup ?? 350,
                hourly_rate_first_run: settings?.default_hourly_rate_first_run ?? 350,
                hourly_rate_production: settings?.default_hourly_rate_production ?? 269,
              }
              setQuote(defaults)
              setLineItems([{ line_number: 1, part_quantity: 1 }])
            }
            getAlloys()
              .then((alloys) => { if (!cancelled) setAlloyOptions(alloys ?? []) })
              .catch(() => { if (!cancelled) setAlloyOptions([]) })
          } else {
            const [q, items] = await Promise.all([
              getQuote(id),
              getQuoteLineItems(id),
            ])
            if (cancelled) return
            setQuote(normalizeQuoteRecord(q))
            setLineItems(
              (items || []).length
                ? items
                : [{ line_number: 1, part_quantity: 1 }]
            )
            const job = await getJobByQuote(id)
            if (job) setJobId(job.id)
            getAlloys()
              .then((alloys) => { if (!cancelled) setAlloyOptions(alloys ?? []) })
              .catch(() => { if (!cancelled) setAlloyOptions([]) })
            ;(items || []).forEach((item) => {
              const name = item.alloy != null ? String(item.alloy).trim() : ''
              if (name) ensureAlloy(name).catch(() => {})
            })
          }
        })()

        await Promise.race([loadPromise, timeoutPromise])
      } catch (e) {
        if (!cancelled) {
          console.error(e)
          if (isNew) {
            setQuote({
              job_number: generateJobNumber(),
              engineer: '',
              status: 'draft',
              shipping_markup_percent: 30,
              final_markup_percent: 0,
              subcontractor_markup_percent: 0,
              exchange_rate_usd_to_cad: 1.3,
              hourly_rate_programming: 350,
              hourly_rate_setup: 350,
              hourly_rate_first_run: 350,
              hourly_rate_production: 269,
            })
            setLineItems([{ line_number: 1, part_quantity: 1 }])
            setCustomers([])
            setVendors([])
          }
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    load()
    return () => { cancelled = true }
  }, [id, isNew])

  const handleQuoteChange = (updates) => {
    setQuote((prev) => (prev ? { ...prev, ...updates } : updates))
  }

  const handleLineItemChange = (index, nextItem) => {
    setLineItems((prev) => {
      const copy = [...prev]
      copy[index] = { ...copy[index], ...nextItem }
      return copy
    })
  }

  const handleAddLineItem = () => {
    const nextNum = Math.max(0, ...lineItems.map((i) => i.line_number || 0)) + 1
    setLineItems((prev) => [...prev, { line_number: nextNum, part_quantity: 1 }])
  }

  const handleDeleteLineItem = (index) => {
    setLineItems((prev) => prev.filter((_, i) => i !== index))
  }

  const handleDuplicateLineItem = (index) => {
    const source = lineItems[index]
    const nextNum = Math.max(0, ...lineItems.map((i) => i.line_number || 0)) + 1
    const copy = { ...source, id: undefined, line_number: nextNum }
    setLineItems((prev) => {
      const out = [...prev]
      out.splice(index + 1, 0, copy)
      return out
    })
  }

  const handleAddCustomer = async () => {
    const name = newCustomerForm.name?.trim()
    if (!name) return
    setAddingCustomer(true)
    try {
      const created = await createCustomer({
        name,
        company: newCustomerForm.company?.trim() || '',
        email: newCustomerForm.email?.trim() || '',
        phone: newCustomerForm.phone?.trim() || '',
      })
      const res = await getCustomers()
      setCustomers(res?.items ?? [])
      handleQuoteChange({ customer: created.id, customer_name: created.company || created.name })
      setAddCustomerOpen(false)
      setNewCustomerForm({ name: '', company: '', email: '', phone: '' })
    } catch (e) {
      console.error(e)
    } finally {
      setAddingCustomer(false)
    }
  }

  const saveQuote = async (statusOverride) => {
    if (!quote) return
    setSaving(true)
    setSaveError(null)
    try {
      const raw = {
        ...quote,
        ...(statusOverride && { status: statusOverride }),
        materials_total: calculatedQuote.materials_total,
        tooling_total: calculatedQuote.tooling_total,
        labor_total: calculatedQuote.labor_total,
        subcontractor_total: calculatedQuote.subcontractor_total,
        subtotal: calculatedQuote.subtotal,
        final_total_cad: calculatedQuote.final_total_cad,
        final_total_usd: calculatedQuote.final_total_usd,
      }
      const toSave = { ...raw }
      if (typeof toSave.customer === 'object' && toSave.customer?.id) {
        toSave.customer = toSave.customer.id
      }
      if (isNew) {
        delete toSave.id
        delete toSave.created
        delete toSave.updated
        delete toSave.expand
        // Custom field: add "quote_created_date" (Date) to quotes collection in PB Admin
        toSave.quote_created_date = new Date().toISOString()
        if (toSave.engineer === '' || toSave.engineer == null) {
          toSave.engineer = '—'
        }
        if (!toSave.job_number || String(toSave.job_number).trim() === '') {
          toSave.job_number = generateJobNumber()
        }
      } else {
        delete toSave.quote_created_date
      }
      let quoteId = quote.id
      if (isNew) {
        const created = await createQuote(toSave)
        quoteId = created.id
        setQuote((p) => ({ ...p, ...normalizeQuoteRecord(created) }))
        if (id === 'new') navigate(`/quotes/${quoteId}`, { replace: true })
      } else {
        const updated = await updateQuote(quoteId, toSave)
        setQuote((p) => ({ ...p, ...normalizeQuoteRecord(updated) }))
      }

      const currentIds = new Set(
        lineItems.filter((i) => i.id).map((i) => i.id)
      )
      const existingItems = await getQuoteLineItems(quoteId)
      for (const old of existingItems) {
        if (old.id && !currentIds.has(old.id)) {
          await deleteLineItem(old.id)
        }
      }
      for (const item of calculatedLineItems) {
        const name = item.alloy != null ? String(item.alloy).trim() : ''
        if (name) await ensureAlloy(name).catch(() => {})
      }
      for (let i = 0; i < calculatedLineItems.length; i++) {
        const item = calculatedLineItems[i]
        
        // Process material_cost_cad
        let materialCostCad = null
        if (item.material_cost_cad != null && item.material_cost_cad !== '') {
          const num = Number(item.material_cost_cad)
          if (!isNaN(num)) materialCostCad = round2(num)
        }
        
        // Process material_shipping_cost
        let materialShippingCost = 0
        if (item.material_shipping_cost != null && item.material_shipping_cost !== '') {
          const num = Number(item.material_shipping_cost)
          if (!isNaN(num)) materialShippingCost = round2(num)
        }
        
        const payload = {
          quote: quoteId,
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
          usd_cost: round2(item.usd_cost ?? 0),
          material_shipping_cost: materialShippingCost,
          testing_cost: round2(item.testing_cost ?? 0),
          tooling_total_cost: round2(item.tooling_total_cost ?? 0),
          tooling_description: item.tooling_description,
          programming_hours: item.programming_hours ?? 0,
          setup_hours: item.setup_hours ?? 0,
          first_run_hours: item.first_run_hours ?? 0,
          production_hours_total: item.production_hours_total ?? 0,
          labor_note: item.labor_note || undefined,
          subcontractor_1: item.subcontractor_1 || undefined,
          subcontractor_1_service: item.subcontractor_1_service,
          subcontractor_1_cost: round2(item.subcontractor_1_cost ?? 0),
          subcontractor_1_shipping: round2(item.subcontractor_1_shipping ?? 0),
          subcontractor_2: item.subcontractor_2 || undefined,
          subcontractor_2_service: item.subcontractor_2_service,
          subcontractor_2_cost: round2(item.subcontractor_2_cost ?? 0),
          subcontractor_2_shipping: round2(item.subcontractor_2_shipping ?? 0),
          heat_treat_cost: round2(item.heat_treat_cost ?? 0),
          inspection_cost: round2(item.inspection_cost ?? 0),
          packaging_cost: round2(item.packaging_cost ?? 0),
          shipping_cost: round2(item.shipping_cost ?? 0),
          previous_quote_reference: item.previous_quote_reference,
          material_actual_cost_cad: round2(item.material_actual_cost_cad ?? 0),
          material_cost_cad: materialCostCad,
          material_with_markup: round2(item.material_with_markup ?? 0),
          labor_cost: round2(item.labor_cost ?? 0),
          subcontractor_1_total: round2(item.subcontractor_1_total ?? 0),
          subcontractor_2_total: round2(item.subcontractor_2_total ?? 0),
          line_total_cad: round2(item.line_total_cad ?? 0),
          price_per_part_cad: round2(item.price_per_part_cad ?? 0),
          price_per_part_usd: round2(item.price_per_part_usd ?? 0),
          quote_part_price_cad: item.quote_part_price_cad != null && item.quote_part_price_cad !== '' ? round2(Number(item.quote_part_price_cad)) : undefined,
        }
        if (item.id) {
          await updateLineItem(item.id, payload)
        } else {
          const created = await createLineItem(payload)
          setLineItems((prev) => {
            const copy = [...prev]
            copy[i] = { ...copy[i], id: created.id }
            return copy
          })
        }
      }

      const finalStatus = statusOverride || quote.status
      if (finalStatus === 'won' && !jobId) {
        const firstMaterialVendor = lineItems.find((item) => item.material_vendor)?.material_vendor || null
        const job = await createJob({
          quote: quoteId,
          job_number: quote.job_number,
          customer: quote.customer || undefined,
          customer_name: quote.customer_name || '',
          parts_description: generatePartsDescription(calculatedLineItems),
          status: 'planning',
          po_number: quote.po_number || '',
          material_source_vendor: firstMaterialVendor || undefined,
        })
        setJobId(job.id)
      }
      setSaveSuccess(true)
      setTimeout(() => setSaveSuccess(false), 3000)
      navigate('/quotes')
    } catch (e) {
      console.error(e)
      const isDuplicateJob =
        e?.status === 400 &&
        (e?.data?.job_number || /unique|failed to .* record/i.test(String(e?.message ?? '')))
      const message = isDuplicateJob
        ? 'Duplicate job #'
        : (e?.response?.message ?? e?.message ?? 'Save failed. Check the console.')
      setSaveError(message)
    } finally {
      setSaving(false)
    }
  }

  const handleCopy = async () => {
    if (!quote) return
    setSaving(true)
    try {
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
      for (let i = 0; i < calculatedLineItems.length; i++) {
        const item = calculatedLineItems[i]
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
          material_cost_cad: item.material_cost_cad != null && item.material_cost_cad !== '' && !isNaN(Number(item.material_cost_cad)) ? Number(item.material_cost_cad) : null,
          material_shipping_cost: item.material_shipping_cost != null && item.material_shipping_cost !== '' && !isNaN(Number(item.material_shipping_cost)) ? Number(item.material_shipping_cost) : 0,
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
        })
      }
      navigate(`/quotes/${created.id}`)
    } catch (e) {
      console.error(e)
    } finally {
      setSaving(false)
    }
  }

  const handleDelete = async () => {
    if (!quote?.id) return
    try {
      await deleteQuote(quote.id)
      navigate('/quotes')
    } catch (e) {
      console.error(e)
    }
  }

  const handleFetchRate = async () => {
    setFetchingRate(true)
    try {
      const rate = await fetchExchangeRate()
      if (rate != null) {
        setExchangeRateInput(undefined)
        handleQuoteChange({ exchange_rate_usd_to_cad: round2(rate) })
      }
    } finally {
      setFetchingRate(false)
    }
  }

  if (loading || !quote) {
    return (
      <Layout>
        <div className="py-8 text-center text-gray-500 dark:text-gray-400">Loading…</div>
      </Layout>
    )
  }

  const selectedCustomer = quote.customer ? customers.find((c) => c.id === quote.customer) : null
  const customerName =
    quote.customer_name ||
    (selectedCustomer ? (selectedCustomer.company || selectedCustomer.name) : '') ||
    ''

  return (
    <Layout>
      <div className="flex flex-col gap-6 lg:flex-row lg:items-start lg:pt-0">
        <div className="min-w-0 flex-1 pt-0">
          <Card className="mb-6">
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="grid gap-4 sm:col-span-2 sm:grid-cols-3">
                <Input
                  label="Job number"
                  value={quote.job_number ?? ''}
                  onChange={(e) => handleQuoteChange({ job_number: e.target.value })}
                />
                <Input
                  label="Quote #"
                  value={quote.wave_quote_number ?? ''}
                  onChange={(e) => handleQuoteChange({ wave_quote_number: e.target.value })}
                />
                <Input
                  label="PO number"
                  value={quote.po_number ?? ''}
                  onChange={(e) => handleQuoteChange({ po_number: e.target.value })}
                />
              </div>
              <div>
                <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
                  Customer
                </label>
                <select
                  className="w-full rounded-input border-2 border-gray-300 px-3 py-2 focus:border-primary-from focus:outline-none dark:border-gray-600 dark:bg-gray-700 dark:text-gray-100"
                  value={quote.customer ?? ''}
                  onChange={(e) => {
                    const val = e.target.value
                    if (val === '__add__') {
                      setNewCustomerForm({ name: '', company: '', email: '', phone: '' })
                      setAddCustomerOpen(true)
                      return
                    }
                    const cId = val || null
                    const c = cId ? customers.find((x) => x.id === cId) : null
                    handleQuoteChange({
                      customer: cId,
                      customer_name: (c?.company || c?.name) ?? '',
                    })
                  }}
                >
                  <option value="">— Select —</option>
                  {customers.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.company || c.name}
                    </option>
                  ))}
                  <option value="__add__">+ Add customer</option>
                </select>
              </div>
              <Input
                label="Engineer"
                value={quote.engineer ?? ''}
                onChange={(e) => handleQuoteChange({ engineer: e.target.value })}
              />
              <div className="sm:col-span-2">
                <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
                  Status
                </label>
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="flex flex-wrap items-center gap-2">
                    {STATUS_OPTIONS.map((o) => (
                      <Button
                        key={o.value}
                        type="button"
                        variant={(quote.status ?? 'draft') === o.value ? 'primary' : 'secondary'}
                        className="!py-2"
                        onClick={() => handleQuoteChange({ status: o.value })}
                      >
                        {o.label}
                      </Button>
                    ))}
                    {quote.status === 'won' && jobId && (
                      <Button
                        type="button"
                        variant="secondary"
                        className="!py-2"
                        onClick={() => navigate(`/jobs/${jobId}`)}
                      >
                        View Job
                      </Button>
                    )}
                  </div>
                  <p className="shrink-0 text-sm text-gray-500 dark:text-gray-400">
                    <span className="font-medium text-gray-700 dark:text-gray-300">Quote created date:</span>{' '}
                    {quoteCreatedDate ?? '—'}
                  </p>
                </div>
              </div>
            </div>

          </Card>

          <Card className="mb-6">
            <div className="grid grid-cols-1 gap-x-6 gap-y-1 md:grid-cols-2 md:grid-rows-[auto_1fr] md:min-h-[220px]">
              <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
                Project notes
              </label>
              <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
                Project images
              </label>
              <div className="min-h-0">
                <textarea
                  className="h-full min-h-[140px] w-full rounded-input border-2 border-gray-300 px-3 py-2 text-sm focus:border-primary-from focus:outline-none dark:border-gray-600 dark:bg-gray-700 dark:text-gray-100"
                  rows={6}
                  placeholder="Notes about this project..."
                  value={quote?.notes ?? ''}
                  onChange={(e) => handleQuoteChange({ notes: e.target.value })}
                />
              </div>
              <div className="flex min-h-0 flex-col">
                <PartImages
                  record={quote}
                  collectionName="quotes"
                  title=""
                  fillHeight
                  onUpdate={(updated) => {
                    setQuote((prev) => ({ ...prev, ...normalizeQuoteRecord(updated) }))
                  }}
                />
              </div>
            </div>
          </Card>

          <div className="mb-4">
            <h2 className="text-lg font-semibold text-gray-900 dark:text-white">Line items</h2>
          </div>
          {lineItems.map((item, index) => (
            <LineItemCard
              key={item.id ?? `new-${index}`}
              lineItem={item}
              quoteSettings={quoteSettings}
              calculated={calculatedLineItems[index]}
              vendors={vendors}
              lineIndex={index}
              alloySuggestions={alloySuggestions}
              onChange={(next) => handleLineItemChange(index, next)}
              onDelete={() => handleDeleteLineItem(index)}
              onDuplicate={() => handleDuplicateLineItem(index)}
              onAddPart={handleAddLineItem}
            />
          ))}
        </div>
        <aside className="lg:w-[500px] lg:shrink-0 lg:sticky lg:top-20 lg:self-start lg:max-h-[calc(100vh-6rem)] lg:overflow-y-auto lg:pt-0">
          <QuoteTotals quote={calculatedQuote} />
          {jobId && (
            <Card className="mt-6">
              <h3 className="mb-2 text-sm font-semibold text-gray-900 dark:text-white">
                Actual time / machining notes
              </h3>
              <textarea
                className="min-h-[80px] w-full rounded-input border-2 border-gray-300 px-3 py-2 text-sm focus:border-primary-from focus:outline-none dark:border-gray-600 dark:bg-gray-700 dark:text-gray-100"
                rows={3}
                value={quote?.actual_time_notes ?? ''}
                onChange={(e) => handleQuoteChange({ actual_time_notes: e.target.value })}
              />
            </Card>
          )}
          <Card className="mt-6">
            <button
              type="button"
              onClick={() => setSettingsOpen((o) => !o)}
              className="flex w-full items-center justify-between text-left font-medium text-gray-700 dark:text-gray-300"
            >
              Settings
              <span>{settingsOpen ? '▼' : '▶'}</span>
            </button>
            {settingsOpen && (
              <div className="mt-3 grid gap-3 sm:grid-cols-2">
                <Input
                  type="number"
                  label="Shipping markup %"
                  value={quote.shipping_markup_percent ?? ''}
                  onChange={(e) =>
                    handleQuoteChange({
                      shipping_markup_percent: Number(e.target.value) || 0,
                    })
                  }
                />
                <Input
                  type="number"
                  label="Final markup %"
                  value={quote.final_markup_percent ?? ''}
                  onChange={(e) =>
                    handleQuoteChange({
                      final_markup_percent: Number(e.target.value) || 0,
                    })
                  }
                />
                <Input
                  type="number"
                  label="Subcontractor markup %"
                  value={quote.subcontractor_markup_percent ?? ''}
                  onChange={(e) =>
                    handleQuoteChange({
                      subcontractor_markup_percent: Number(e.target.value) || 0,
                    })
                  }
                />
                <div className="flex gap-2 sm:col-span-2">
                  <Input
                    type="number"
                    step="any"
                    label="Exchange rate (USD→CAD)"
                    value={exchangeRateInput !== undefined ? exchangeRateInput : (quote.exchange_rate_usd_to_cad ?? '')}
                    onChange={(e) => setExchangeRateInput(e.target.value)}
                    onBlur={() => {
                      const raw = exchangeRateInput
                      setExchangeRateInput(undefined)
                      if (raw === '') return
                      const n = Number(raw)
                      if (!Number.isNaN(n) && n >= 0) {
                        handleQuoteChange({ exchange_rate_usd_to_cad: round2(n) })
                      }
                    }}
                  />
                  <Button
                    type="button"
                    variant="secondary"
                    className="self-end"
                    disabled={fetchingRate}
                    onClick={handleFetchRate}
                  >
                    {fetchingRate ? '…' : 'Fetch'}
                  </Button>
                </div>
                <Input
                  type="number"
                  label="Programming $/hr"
                  value={quote.hourly_rate_programming ?? ''}
                  onChange={(e) => {
                    const v = round2(Number(e.target.value) || 0)
                    const updates = { hourly_rate_programming: v }
                    if (!ratesEditedByUser.setup) updates.hourly_rate_setup = v
                    if (!ratesEditedByUser.firstRun) updates.hourly_rate_first_run = v
                    if (!ratesEditedByUser.production) updates.hourly_rate_production = v
                    handleQuoteChange(updates)
                  }}
                />
                <Input
                  type="number"
                  label="Setup $/hr"
                  value={quote.hourly_rate_setup ?? ''}
                  onChange={(e) => {
                    setRatesEditedByUser((p) => ({ ...p, setup: true }))
                    handleQuoteChange({ hourly_rate_setup: round2(Number(e.target.value) || 0) })
                  }}
                />
                <Input
                  type="number"
                  label="First run $/hr"
                  value={quote.hourly_rate_first_run ?? ''}
                  onChange={(e) => {
                    setRatesEditedByUser((p) => ({ ...p, firstRun: true }))
                    handleQuoteChange({
                      hourly_rate_first_run: round2(Number(e.target.value) || 0),
                    })
                  }}
                />
                <Input
                  type="number"
                  label="Production $/hr"
                  value={quote.hourly_rate_production ?? ''}
                  onChange={(e) => {
                    setRatesEditedByUser((p) => ({ ...p, production: true }))
                    handleQuoteChange({
                      hourly_rate_production: round2(Number(e.target.value) || 0),
                    })
                  }}
                />
              </div>
            )}
          </Card>
          {saveError && (
            <div className="mt-4 rounded border border-danger bg-red-50 p-3 text-sm text-danger">
              {saveError}
            </div>
          )}
          {saveSuccess && (
            <div className="mt-4 rounded border border-success bg-green-50 p-3 text-sm text-success">
              Saved.
            </div>
          )}
          <div className="mt-4 flex flex-nowrap gap-2">
            <Button
              disabled={saving}
              onClick={() => saveQuote()}
            >
              {saving ? 'Saving…' : 'Save'}
            </Button>
            <Button
              variant="secondary"
              disabled={saving}
              onClick={() => saveQuote('sent')}
            >
              Sent
            </Button>
            <Button variant="secondary" disabled={saving} onClick={handleCopy}>
              Copy
            </Button>
            {!isNew && (
              <Button
                variant="danger"
                disabled={saving}
                onClick={() => setDeleteConfirm(true)}
              >
                Delete
              </Button>
            )}
          </div>
        </aside>
      </div>

      <Modal
        open={addCustomerOpen}
        onClose={() => !addingCustomer && setAddCustomerOpen(false)}
        title="Add customer"
      >
        <div className="space-y-3">
          <Input
            label="Name"
            value={newCustomerForm.name}
            onChange={(e) => setNewCustomerForm((p) => ({ ...p, name: e.target.value }))}
            placeholder="Required"
          />
          <Input
            label="Company"
            value={newCustomerForm.company}
            onChange={(e) => setNewCustomerForm((p) => ({ ...p, company: e.target.value }))}
          />
          <Input
            label="Email"
            type="email"
            value={newCustomerForm.email}
            onChange={(e) => setNewCustomerForm((p) => ({ ...p, email: e.target.value }))}
          />
          <Input
            label="Phone"
            value={newCustomerForm.phone}
            onChange={(e) => setNewCustomerForm((p) => ({ ...p, phone: e.target.value }))}
          />
          <div className="flex gap-2 pt-2">
            <Button disabled={addingCustomer || !newCustomerForm.name?.trim()} onClick={handleAddCustomer}>
              {addingCustomer ? 'Adding…' : 'Add & select'}
            </Button>
            <Button variant="secondary" disabled={addingCustomer} onClick={() => setAddCustomerOpen(false)}>
              Cancel
            </Button>
          </div>
        </div>
      </Modal>

      <ConfirmDialog
        open={deleteConfirm}
        onClose={() => setDeleteConfirm(false)}
        onConfirm={handleDelete}
        title="Delete quote"
        message="Are you sure you want to delete this quote? Line items will be deleted too."
        confirmLabel="Delete"
      />
    </Layout>
  )
}
