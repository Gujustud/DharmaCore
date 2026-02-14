/**
 * Map a CSV row (from Notion export) to normalized quote data.
 * Tries common Notion/CSV header names (case-insensitive).
 */
function getCell(row, ...keys) {
  const lower = (s) => (s == null ? '' : String(s).toLowerCase().trim())
  const rowKeys = Object.keys(row || {})
  for (const key of keys) {
    const k = rowKeys.find((r) => lower(r) === lower(key))
    if (k != null && row[k] != null && String(row[k]).trim() !== '') {
      return String(row[k]).trim()
    }
  }
  return ''
}

const STATUS_MAP = {
  draft: 'draft',
  sent: 'sent',
  won: 'won',
  lost: 'lost',
  done: 'won',
  'in progress': 'sent',
  'in-progress': 'sent',
  cancelled: 'lost',
  canceled: 'lost',
  archived: 'lost',
  planning: 'draft',
  backlog: 'draft',
}

/**
 * Normalize a single CSV row into quote data (without PocketBase-specific defaults).
 *
 * @param {Record<string, any>} row - One CSV row (header → value)
 * @param {object} defaults - Default values from settings (currently used only for engineer fallback)
 * @returns {{
 *   job_number: string,
 *   customer_name: string,
 *   customer_code: string,
 *   status: string,
 *   engineer: string,
 *   po_number: string,
 *   wave_quote_number: string,
 *   final_total_cad?: number,
 * } | null}
 */
export function csvRowToQuote(row, defaults) {
  const jobField = getCell(row, 'Job', 'Name', 'Job #', 'Job Number', 'job_number')
  if (!jobField) return null

  let jobNumber = ''
  let customerFromJob = ''

  // Try to parse patterns like "02052025 - MRL" (job number + customer suffix)
  const match = jobField.match(/^\s*([0-9]{8})\s*[-–—]\s*(.+)$/)
  if (match) {
    jobNumber = match[1].trim()
    customerFromJob = match[2].trim()
  } else {
    jobNumber = jobField.trim()
  }

  if (!jobNumber) return null

  let customerCode = ''
  if (customerFromJob) {
    // First token (e.g. "MRL" from "MRL", or "MRL something")
    customerCode = customerFromJob.split(/[ ,]/)[0].trim()
  }

  const customerFromColumn = getCell(row, 'Customer', 'Company', 'customer_name', 'Customer Name')
  const customerName = customerFromJob || customerFromColumn || ''

  const statusRaw = getCell(row, 'Status', 'status')
  const normalizedStatus = statusRaw.toLowerCase()
  const status = STATUS_MAP[normalizedStatus] || 'draft'

  const engineer = getCell(row, 'Engineer', 'engineer') || (defaults?.engineer ?? '—')
  const poNumber = getCell(row, 'PO Number', 'PO', 'po_number', 'Po Number')
  const waveQuote = getCell(row, 'Wave Quote', 'Wave Quote Number', 'wave_quote_number')
  const attachments = getCell(row, 'Attachments', 'Attachment')
  const totalStr = getCell(row, 'Total', 'Final Total', 'final_total_cad', 'Total (CAD)')

  const num = (v) => {
    if (!v) return undefined
    const n = Number(String(v).replace(/[^0-9.-]/g, ''))
    return Number.isNaN(n) ? undefined : n
  }

  const result = {
    job_number: jobNumber,
    customer_name: customerName,
    customer_code: customerCode,
    status,
    engineer,
    po_number: poNumber || '',
    wave_quote_number: waveQuote || '',
    notes: attachments || '',
  }

  const total = num(totalStr)
  if (total != null) result.final_total_cad = total

  return result
}
