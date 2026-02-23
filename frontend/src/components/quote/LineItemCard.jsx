import { useState } from 'react'
import { Card } from '../ui/Card'
import { Input } from '../ui/Input'
import { Button } from '../ui/Button'

function fmt(n) {
  return Number(n).toLocaleString('en-CA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

function round2(n) {
  if (n == null || n === '' || isNaN(Number(n))) return ''
  return Math.round(Number(n) * 100) / 100
}
// For $ fields: round to 2 decimals; empty input => undefined
function dollar(v) {
  const n = v === '' || v == null ? '' : Number(v)
  return n === '' || Number.isNaN(n) ? undefined : round2(n)
}

function Section({ title, open: initialOpen, children }) {
  const [open, setOpen] = useState(initialOpen ?? false)
  return (
    <div className="border-b border-gray-100 last:border-0 dark:border-gray-700">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="flex w-full items-center justify-between py-2 text-left text-sm font-medium text-gray-700 hover:text-gray-900 dark:text-gray-300 dark:hover:text-white"
      >
        {title}
        <span className="text-gray-400 dark:text-gray-500">{open ? '▼' : '▶'}</span>
      </button>
      {open && <div className="pb-4 pl-2">{children}</div>}
    </div>
  )
}

export function LineItemCard({
  lineItem,
  quoteSettings,
  calculated,
  vendors = [],
  alloySuggestions = [],
  onChange,
  onDelete,
  onDuplicate,
  onAddPart,
  lineIndex,
}) {
  const [detailsOpen, setDetailsOpen] = useState(true)
  const [alloyDropdownOpen, setAlloyDropdownOpen] = useState(false)
  const handle = (field, value) => {
    onChange({ ...lineItem, [field]: value })
  }
  const num = (v) => (v === '' || v == null ? '' : Number(v))
  const str = (v) => (v == null ? '' : String(v))

  const actionButtons = (
    <div className="flex flex-wrap items-center gap-2">
      {onAddPart && (
        <Button type="button" variant="secondary" onClick={onAddPart}>
          Add part
        </Button>
      )}
      {onDuplicate && (
        <Button type="button" variant="secondary" onClick={onDuplicate}>
          Duplicate part
        </Button>
      )}
      <Button type="button" variant="secondary" onClick={onDelete} className="text-danger hover:bg-red-50 dark:hover:bg-red-900/40">
        Delete part
      </Button>
    </div>
  )

  return (
    <Card className="mb-4">
      <div className="mb-3 flex flex-wrap items-center gap-3 border-b border-gray-200 pb-3 dark:border-gray-600 sm:gap-[20px]">
        <span className="shrink-0 font-medium text-gray-500 dark:text-gray-400">Part {lineIndex + 1}</span>
        <div className="min-w-0 flex-1 sm:max-w-[200px] sm:flex-initial">
          <Input
            placeholder="Part number"
            value={str(lineItem.part_number)}
            onChange={(e) => handle('part_number', e.target.value)}
            className="w-full"
          />
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <span className="font-medium text-gray-500 dark:text-gray-400">Qty</span>
          <Input
            type="number"
            min={1}
            value={lineItem.part_quantity ?? ''}
            onChange={(e) => {
              const raw = e.target.value
              if (raw === '') {
                handle('part_quantity', undefined)
                return
              }
              const n = Number(raw)
              if (!isNaN(n) && n >= 0) handle('part_quantity', n)
            }}
            className="w-14"
          />
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <span className="shrink-0 font-medium text-gray-500 dark:text-gray-400">QPP</span>
          <Input
            type="number"
            step="0.01"
            min={0}
            value={
              lineItem.quote_part_price_cad != null && lineItem.quote_part_price_cad !== ''
                ? round2(lineItem.quote_part_price_cad)
                : (calculated != null ? round2(calculated.quoted_price_per_part_cad) : '')
            }
            onChange={(e) => {
              const raw = e.target.value
              if (raw === '') {
                handle('quote_part_price_cad', undefined)
                return
              }
              const n = parseFloat(raw)
              if (!isNaN(n) && n >= 0) handle('quote_part_price_cad', Math.round(n * 100) / 100)
            }}
            className="w-[120px] min-w-0"
          />
        </div>
        <button
          type="button"
          onClick={() => setDetailsOpen((o) => !o)}
          className="ml-auto shrink-0 font-medium text-gray-700 hover:text-gray-900"
          title={detailsOpen ? 'Hide details' : 'Show details'}
        >
          {detailsOpen ? '▼' : '▶'}
        </button>
      </div>

      {detailsOpen && (
      <>
      <Section title="Materials" open>
        <div className="grid gap-2 sm:grid-cols-2">
          <div>
            <Input
              type="number"
              label={
                calculated?.material_with_markup != null
                  ? `Actual cost (CAD) (Markup cost (CAD): $${fmt(calculated.material_with_markup)})`
                  : 'Actual cost (CAD)'
              }
              value={
                // If USD is set and CAD is not explicitly set (null/undefined/empty/0), show calculated value
                // Otherwise, if CAD is explicitly set (non-zero), show CAD
                // Otherwise, show empty
                (lineItem.usd_cost != null && lineItem.usd_cost !== '' && lineItem.usd_cost !== 0 &&
                 (lineItem.material_cost_cad == null || lineItem.material_cost_cad === '' || lineItem.material_cost_cad === 0) &&
                 calculated?.material_actual_cost_cad != null && calculated.material_actual_cost_cad !== 0)
                  ? calculated.material_actual_cost_cad
                  : (lineItem.material_cost_cad != null && lineItem.material_cost_cad !== '' && lineItem.material_cost_cad !== 0
                      ? lineItem.material_cost_cad
                      : '')
              }
              onChange={(e) => {
                const raw = e.target.value
                if (raw === '') {
                  handle('material_cost_cad', undefined)
                } else {
                  const n = num(raw)
                  handle('material_cost_cad', n === '' ? undefined : round2(n))
                }
              }}
            />
          </div>
          <Input
            type="number"
            label="Actual cost (USD)"
            value={lineItem.usd_cost ?? ''}
            onChange={(e) => {
              const value = dollar(e.target.value)
              const rate = Number(quoteSettings?.exchange_rate_usd_to_cad) || 0
              const cadFromUsd =
                value != null && rate > 0 ? round2(value * rate) : undefined
              onChange({ ...lineItem, usd_cost: value ?? '', material_cost_cad: cadFromUsd })
            }}
          />
          <Input
            type="number"
            label="Shipping cost"
            value={lineItem.material_shipping_cost ?? ''}
            onChange={(e) => handle('material_shipping_cost', dollar(e.target.value) ?? '')}
          />
          <Input
            type="number"
            label="Testing cost"
            value={lineItem.testing_cost ?? ''}
            onChange={(e) => handle('testing_cost', dollar(e.target.value) ?? '')}
          />
          <div className="relative w-full">
            <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
              Alloy
            </label>
            <input
              type="text"
              placeholder="Type or select"
              value={str(lineItem.alloy)}
              onChange={(e) => {
                handle('alloy', e.target.value)
                setAlloyDropdownOpen(true)
              }}
              onFocus={() => setAlloyDropdownOpen(true)}
              onBlur={() => setTimeout(() => setAlloyDropdownOpen(false), 150)}
              className="w-full rounded-input border-2 border-gray-300 px-3 py-2 focus:border-primary-from focus:outline-none dark:border-gray-600 dark:bg-gray-700 dark:text-gray-100 dark:placeholder-gray-400"
            />
            {alloyDropdownOpen && (() => {
              const current = str(lineItem.alloy).toLowerCase()
              let options = [...new Set([...alloySuggestions, str(lineItem.alloy)].filter(Boolean))]
                .filter((a) => !current || a.toLowerCase().includes(current))
                .sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }))
              if (options.length === 0 && current) options = [str(lineItem.alloy)]
              if (options.length === 0) options = ['']
              return (
                <ul
                  className="absolute z-50 mt-1 max-h-48 w-full overflow-auto rounded-md border border-gray-200 bg-white py-1 shadow-lg dark:border-gray-600 dark:bg-gray-700"
                  onMouseDown={(e) => e.preventDefault()}
                >
                  {options.map((a) =>
                    a === '' ? (
                      <li key="__hint" className="px-3 py-2 text-sm text-gray-500 dark:text-gray-400">
                        Type to add a new alloy
                      </li>
                    ) : (
                      <li key={a}>
                        <button
                          type="button"
                          className="w-full px-3 py-2 text-left text-sm hover:bg-gray-100 dark:hover:bg-gray-600"
                          onMouseDown={() => {
                            handle('alloy', a)
                            setAlloyDropdownOpen(false)
                          }}
                        >
                          {a}
                        </button>
                      </li>
                    )
                  )}
                </ul>
              )
            })()}
          </div>
          <Input
            label="Stock size per part"
            value={str(lineItem.stock_size_per_part)}
            onChange={(e) => handle('stock_size_per_part', e.target.value)}
          />
          <Input
            type="number"
            label="Pieces"
            value={lineItem.pieces ?? ''}
            onChange={(e) => handle('pieces', num(e.target.value))}
          />
          <Input
            label="Ordered length"
            value={str(lineItem.ordered_length)}
            onChange={(e) => handle('ordered_length', e.target.value)}
          />
          <div className="flex flex-wrap items-end gap-4 sm:col-span-2">
            <div className="min-w-0 flex-1">
              <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
                Material vendor
              </label>
              <select
                className="w-full rounded-input border-2 border-gray-300 px-3 py-2 focus:border-primary-from focus:outline-none dark:border-gray-600 dark:bg-gray-700 dark:text-gray-100"
                value={lineItem.material_vendor ?? ''}
                onChange={(e) => handle('material_vendor', e.target.value || null)}
              >
                <option value="">— Select —</option>
                {vendors.map((v) => (
                  <option key={v.id} value={v.id}>
                    {v.name}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
                Vendor supplied
              </label>
              <div className="flex gap-2">
                <Button
                  type="button"
                  variant={str(lineItem.vendor_supplied).toLowerCase() === 'yes' ? 'primary' : 'secondary'}
                  className="!py-2"
                  onClick={() => handle('vendor_supplied', 'yes')}
                >
                  Yes
                </Button>
                <Button
                  type="button"
                  variant={str(lineItem.vendor_supplied).toLowerCase() === 'no' ? 'primary' : 'secondary'}
                  className="!py-2"
                  onClick={() => handle('vendor_supplied', 'no')}
                >
                  No
                </Button>
              </div>
            </div>
          </div>
          <div className="sm:col-span-2">
            <Input
              label="Material note"
              value={str(lineItem.material_note)}
              onChange={(e) => handle('material_note', e.target.value)}
            />
          </div>
        </div>
      </Section>

      <Section title="Tooling">
        <div className="flex items-end gap-4">
          <div className="w-28 shrink-0">
            <Input
              type="number"
              label="Total cost"
              value={lineItem.tooling_total_cost ?? ''}
              onChange={(e) => handle('tooling_total_cost', dollar(e.target.value) ?? '')}
            />
          </div>
          <div className="min-w-0 flex-1">
            <Input
              label="Description"
              value={str(lineItem.tooling_description)}
              onChange={(e) => handle('tooling_description', e.target.value)}
            />
          </div>
        </div>
      </Section>

      <Section title="Labor">
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          <Input
            type="number"
            step="any"
            label="Programming (hrs)"
            value={lineItem.programming_hours ?? ''}
            onChange={(e) => handle('programming_hours', e.target.value === '' ? undefined : e.target.value)}
            onBlur={(e) => {
              const v = e.target.value
              if (v === '') return
              const n = Number(v)
              if (!Number.isNaN(n) && n >= 0) handle('programming_hours', n)
            }}
          />
          <Input
            type="number"
            step="any"
            label="Setup (hrs)"
            value={lineItem.setup_hours ?? ''}
            onChange={(e) => handle('setup_hours', e.target.value === '' ? undefined : e.target.value)}
            onBlur={(e) => {
              const v = e.target.value
              if (v === '') return
              const n = Number(v)
              if (!Number.isNaN(n) && n >= 0) handle('setup_hours', n)
            }}
          />
          <Input
            type="number"
            step="any"
            label="First run (hrs)"
            value={lineItem.first_run_hours ?? ''}
            onChange={(e) => handle('first_run_hours', e.target.value === '' ? undefined : e.target.value)}
            onBlur={(e) => {
              const v = e.target.value
              if (v === '') return
              const n = Number(v)
              if (!Number.isNaN(n) && n >= 0) handle('first_run_hours', n)
            }}
          />
          <Input
            type="number"
            step="any"
            label="Production total (hrs)"
            value={lineItem.production_hours_total ?? ''}
            onChange={(e) => handle('production_hours_total', e.target.value === '' ? undefined : e.target.value)}
            onBlur={(e) => {
              const v = e.target.value
              if (v === '') return
              const n = Number(v)
              if (!Number.isNaN(n) && n >= 0) handle('production_hours_total', n)
            }}
          />
        </div>
        {calculated?.labor_cost != null && (
          <p className="mt-2 text-sm text-gray-600">
            → Labor total: ${fmt(calculated.labor_cost)}
          </p>
        )}
        <div className="mt-3">
          <label className="mb-1 block text-sm font-medium text-gray-700">
            Note
          </label>
          <textarea
            className="w-full rounded-input border-2 border-gray-300 px-3 py-2 focus:border-primary-from focus:outline-none"
            rows={2}
            value={str(lineItem.labor_note)}
            onChange={(e) => handle('labor_note', e.target.value)}
            placeholder="Labour notes…"
          />
        </div>
      </Section>

      <Section title="Subcontractors">
        <div className="space-y-4">
          <div className="grid gap-2 sm:grid-cols-2">
            <div>
              <label className="mb-1 block text-sm font-medium text-gray-700">
                Subcontractor 1
              </label>
              <select
                className="w-full rounded-input border-2 border-gray-300 px-3 py-2 focus:border-primary-from focus:outline-none"
                value={lineItem.subcontractor_1 ?? ''}
                onChange={(e) => handle('subcontractor_1', e.target.value || null)}
              >
                <option value="">— Select —</option>
                {vendors.map((v) => (
                  <option key={v.id} value={v.id}>
                    {v.name}
                  </option>
                ))}
              </select>
            </div>
            <Input
              label="Service"
              value={str(lineItem.subcontractor_1_service)}
              onChange={(e) => handle('subcontractor_1_service', e.target.value)}
            />
            <Input
              type="number"
              label="Cost"
              value={lineItem.subcontractor_1_cost ?? ''}
              onChange={(e) => handle('subcontractor_1_cost', dollar(e.target.value) ?? '')}
            />
            <Input
              type="number"
              label="Shipping"
              value={lineItem.subcontractor_1_shipping ?? ''}
              onChange={(e) => handle('subcontractor_1_shipping', dollar(e.target.value) ?? '')}
            />
          </div>
          <div className="grid gap-2 sm:grid-cols-2">
            <div>
              <label className="mb-1 block text-sm font-medium text-gray-700">
                Subcontractor 2
              </label>
              <select
                className="w-full rounded-input border-2 border-gray-300 px-3 py-2 focus:border-primary-from focus:outline-none"
                value={lineItem.subcontractor_2 ?? ''}
                onChange={(e) => handle('subcontractor_2', e.target.value || null)}
              >
                <option value="">— Select —</option>
                {vendors.map((v) => (
                  <option key={v.id} value={v.id}>
                    {v.name}
                  </option>
                ))}
              </select>
            </div>
            <Input
              label="Service"
              value={str(lineItem.subcontractor_2_service)}
              onChange={(e) => handle('subcontractor_2_service', e.target.value)}
            />
            <Input
              type="number"
              label="Cost"
              value={lineItem.subcontractor_2_cost ?? ''}
              onChange={(e) => handle('subcontractor_2_cost', dollar(e.target.value) ?? '')}
            />
            <Input
              type="number"
              label="Shipping"
              value={lineItem.subcontractor_2_shipping ?? ''}
              onChange={(e) => handle('subcontractor_2_shipping', dollar(e.target.value) ?? '')}
            />
          </div>
        </div>
        {(calculated?.subcontractor_1_total || calculated?.subcontractor_2_total) != null && (
          <p className="mt-2 text-sm text-gray-600">
            → Subcontractor total: $
            {fmt((calculated?.subcontractor_1_total ?? 0) + (calculated?.subcontractor_2_total ?? 0))}
          </p>
        )}
      </Section>

      <Section title="Post-processing">
        <div className="grid gap-2 sm:grid-cols-2">
          <Input
            type="number"
            label="Inspection"
            value={lineItem.inspection_cost ?? ''}
            onChange={(e) => handle('inspection_cost', dollar(e.target.value) ?? '')}
          />
          <Input
            type="number"
            label="Packaging"
            value={lineItem.packaging_cost ?? ''}
            onChange={(e) => handle('packaging_cost', dollar(e.target.value) ?? '')}
          />
          <Input
            type="number"
            label="Shipping"
            value={lineItem.shipping_cost ?? ''}
            onChange={(e) => handle('shipping_cost', dollar(e.target.value) ?? '')}
          />
        </div>
      </Section>

      <Section title="Reference">
        <Input
          label="Previous quote reference"
          value={str(lineItem.previous_quote_reference)}
          onChange={(e) => handle('previous_quote_reference', e.target.value)}
        />
      </Section>
      </>
      )}

      <div className="mt-4 flex flex-wrap items-center justify-between gap-4 border-t border-gray-200 pt-4">
        {calculated ? (
          <div>
            <p className="text-sm text-gray-600">
              Total (CAD): <span className="font-bold">${fmt(calculated.line_total_cad)}</span>
            </p>
            <p className="text-sm text-gray-600">
              Per part (CAD): <span className="font-bold">${fmt(calculated.price_per_part_cad)}</span>
              {' | '}Per part (USD): <span className="font-bold">${fmt(calculated.price_per_part_usd)}</span>
            </p>
            <p className="text-sm text-gray-600">
              Quoted per part (CAD): <span className="font-bold">${fmt(calculated.quoted_price_per_part_cad)}</span>
              {' | '}Quoted per part (USD): <span className="font-bold">${fmt(calculated.quoted_price_per_part_usd)}</span>
            </p>
          </div>
        ) : (
          <div />
        )}
        {actionButtons}
      </div>
    </Card>
  )
}
