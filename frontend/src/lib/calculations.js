/**
 * Quote and line item calculation functions.
 * Matches CNC_QUOTE_TRACKER_PLAN_V3 formulas. Handles null/zero edge cases.
 */

/**
 * Calculate all computed fields for a line item.
 * @param {Object} lineItem - The line item data
 * @param {Object} quoteSettings - Parent quote settings (rates, markups, exchange rate)
 * @returns {Object} - Line item with calculated fields
 */
export function calculateLineItem(lineItem, quoteSettings) {
  const {
    usd_cost = 0,
    material_cost_cad,
    material_shipping_cost = 0,
    testing_cost = 0,
    tooling_total_cost = 0,
    programming_hours = 0,
    setup_hours = 0,
    first_run_hours = 0,
    production_hours_total = 0,
    subcontractor_1_cost = 0,
    subcontractor_1_shipping = 0,
    subcontractor_2_cost = 0,
    subcontractor_2_shipping = 0,
    heat_treat_cost = 0,
    inspection_cost = 0,
    packaging_cost = 0,
    shipping_cost = 0,
    part_quantity = 1,
  } = lineItem

  const exchange_rate_usd_to_cad = Number(quoteSettings?.exchange_rate_usd_to_cad) || 0
  const final_markup_percent = Number(quoteSettings?.final_markup_percent) ?? 0
  const shipping_markup_percent = Number(quoteSettings?.shipping_markup_percent) ?? 0
  const subcontractor_markup_percent = Number(quoteSettings?.subcontractor_markup_percent) ?? 0
  const hourly_rate_programming = Number(quoteSettings?.hourly_rate_programming) ?? 0
  const hourly_rate_setup = Number(quoteSettings?.hourly_rate_setup) ?? 0
  const hourly_rate_first_run = Number(quoteSettings?.hourly_rate_first_run) ?? 0
  const hourly_rate_production = Number(quoteSettings?.hourly_rate_production) ?? 0

  // 1. MATERIAL COSTS
  // Actual cost CAD: use manual entry (local purchase) or convert USD at exchange rate
  const manualCad = material_cost_cad != null && material_cost_cad !== '' ? Number(material_cost_cad) : NaN
  const material_actual_cost_cad = !isNaN(manualCad) ? manualCad : usd_cost * exchange_rate_usd_to_cad
  // Standard cost = (testing + actual cost CAD) with shipping markup, then add shipping fee (no markup on shipping)
  const material_with_markup =
    (testing_cost + material_actual_cost_cad) * (1 + shipping_markup_percent / 100) + material_shipping_cost

  // 2. TOOLING (direct input)
  const tooling_total = tooling_total_cost

  // 3. LABOR COSTS
  const labor_cost =
    programming_hours * hourly_rate_programming +
    setup_hours * hourly_rate_setup +
    first_run_hours * hourly_rate_first_run +
    production_hours_total * hourly_rate_production

  // 4. SUBCONTRACTOR COSTS (with quote-level markup applied to what you charge the customer)
  const sub1Base = subcontractor_1_cost + subcontractor_1_shipping
  const sub2Base = subcontractor_2_cost + subcontractor_2_shipping
  const subcontractor_1_total = sub1Base * (1 + subcontractor_markup_percent / 100)
  const subcontractor_2_total = sub2Base * (1 + subcontractor_markup_percent / 100)

  // 5. LINE ITEM TOTAL
  const line_total_cad =
    material_with_markup +
    tooling_total +
    labor_cost +
    subcontractor_1_total +
    subcontractor_2_total +
    heat_treat_cost +
    inspection_cost +
    packaging_cost +
    shipping_cost

  // 6. PER-PART PRICING (avoid division by zero)
  const price_per_part_cad = part_quantity > 0 ? line_total_cad / part_quantity : 0
  const price_per_part_usd =
    exchange_rate_usd_to_cad > 0 ? price_per_part_cad / exchange_rate_usd_to_cad : 0

  // 7. QUOTED PER-PART: use optional override or apply final markup to price-per-part
  const overrideCad =
    lineItem.quote_part_price_cad != null && lineItem.quote_part_price_cad !== ''
      ? Number(lineItem.quote_part_price_cad)
      : NaN
  const quoted_price_per_part_cad =
    !isNaN(overrideCad) && overrideCad >= 0
      ? overrideCad
      : price_per_part_cad * (1 + final_markup_percent / 100)
  const quoted_price_per_part_usd =
    exchange_rate_usd_to_cad > 0 ? quoted_price_per_part_cad / exchange_rate_usd_to_cad : 0

  return {
    ...lineItem,
    material_actual_cost_cad,
    material_with_markup,
    labor_cost,
    subcontractor_1_total,
    subcontractor_2_total,
    line_total_cad,
    price_per_part_cad,
    price_per_part_usd,
    quoted_price_per_part_cad,
    quoted_price_per_part_usd,
  }
}

/**
 * Calculate quote-level totals from all line items.
 * @param {Object} quote - The quote record
 * @param {Array} lineItems - Array of line items (already calculated via calculateLineItem)
 * @returns {Object} - Quote with calculated totals
 */
export function calculateQuoteTotals(quote, lineItems) {
  const final_markup_percent = Number(quote?.final_markup_percent) ?? 0
  const exchange_rate_usd_to_cad = Number(quote?.exchange_rate_usd_to_cad) || 0

  const materials_total = (lineItems || []).reduce(
    (sum, item) => sum + (item.material_with_markup ?? 0),
    0
  )
  const tooling_total = (lineItems || []).reduce(
    (sum, item) => sum + (item.tooling_total_cost ?? 0),
    0
  )
  const labor_total = (lineItems || []).reduce((sum, item) => sum + (item.labor_cost ?? 0), 0)
  const subcontractor_total = (lineItems || []).reduce(
    (sum, item) =>
      sum + (item.subcontractor_1_total ?? 0) + (item.subcontractor_2_total ?? 0),
    0
  )
  const subtotal = (lineItems || []).reduce(
    (sum, item) => sum + (item.line_total_cad ?? 0),
    0
  )

  // Quote total = sum of (quoted per part × qty) so it matches line-level quoted values and overrides
  const final_total_cad = (lineItems || []).reduce(
    (sum, item) =>
      sum + (item.quoted_price_per_part_cad ?? 0) * (item.part_quantity ?? 0),
    0
  )
  const final_total_usd =
    exchange_rate_usd_to_cad > 0 ? final_total_cad / exchange_rate_usd_to_cad : 0

  return {
    ...quote,
    materials_total,
    tooling_total,
    labor_total,
    subcontractor_total,
    subtotal,
    final_total_cad,
    final_total_usd,
  }
}

/**
 * Generate job number from date. Format: MMDDYYYY.
 * @param {Date} [date=new Date()] - Date object (default: today)
 * @returns {string} - Job number
 */
export function generateJobNumber(date = new Date()) {
  const d = date instanceof Date ? date : new Date(date)
  const month = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  const year = String(d.getFullYear())
  return `${month}${day}${year}`
}

/**
 * Generate parts description from quote line items.
 * @param {Array} lineItems - Quote line items
 * @returns {string} - Formatted parts list (one line per part)
 */
export function generatePartsDescription(lineItems) {
  if (!Array.isArray(lineItems) || lineItems.length === 0) return ''
  return lineItems
    .map((item) => {
      const partNum = item.part_number || 'Unnamed Part'
      const qty = item.part_quantity ?? 1
      return `• ${partNum} (qty ${qty})`
    })
    .join('\n')
}

/**
 * Generate tracking URL from tracking number (FedEx, UPS, Canada Post, Purolator).
 * @param {string} [trackingNumber] - Tracking number
 * @returns {string} - Tracking URL or empty string
 */
export function generateTrackingLink(trackingNumber) {
  if (!trackingNumber || typeof trackingNumber !== 'string') return ''
  const clean = trackingNumber.replace(/\s/g, '').toUpperCase()
  if (!clean) return ''

  if (/^\d{12,14}$/.test(clean)) {
    return `https://www.fedex.com/fedextrack/?tracknumbers=${clean}`
  }
  if (/^1Z/.test(clean)) {
    return `https://www.ups.com/track?tracknum=${clean}`
  }
  if (/^\d{13}$/.test(clean)) {
    return `https://www.canadapost-postescanada.ca/track-reperage/en#/search?searchFor=${clean}`
  }
  if (/^P/.test(clean)) {
    return `https://www.purolator.com/en/shipping/tracker?pin=${clean}`
  }
  // DHL Express (e.g. 10-digit)
  if (/^\d{9,11}$/.test(clean)) {
    return `https://www.mydhl.express.dhl/ca/en/tracking.html#/tracking?trackingnumber=${clean}`
  }
  return ''
}
