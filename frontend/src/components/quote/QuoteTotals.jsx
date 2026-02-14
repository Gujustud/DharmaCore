import { Card } from '../ui/Card'

function fmt(n) {
  return Number(n).toLocaleString('en-CA', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

export function QuoteTotals({ quote }) {
  if (!quote) return null
  const {
    materials_total = 0,
    tooling_total = 0,
    labor_total = 0,
    subcontractor_total = 0,
    subtotal = 0,
    final_markup_percent = 0,
    final_total_cad = 0,
    final_total_usd = 0,
  } = quote
  const markupAmount = subtotal * (Number(final_markup_percent) / 100)
  const revenueCad = Number(final_total_cad) || 0
  // Direct cost = materials + tooling + subcontractors (what you pay out); margin = labour + markups + profit
  const directCostCad =
    Number(materials_total) + Number(tooling_total) + Number(subcontractor_total)
  const marginPercent =
    revenueCad > 0 && revenueCad > directCostCad
      ? (((revenueCad - directCostCad) / revenueCad) * 100)
      : 0

  return (
    <Card className="sticky top-4 w-[500px] shrink-0">
      <h3 className="mb-4 font-semibold text-gray-900 dark:text-white">QUOTE TOTALS</h3>
      <div className="space-y-2 text-sm">
        <div className="flex justify-between">
          <span className="text-gray-600 dark:text-gray-300">Materials</span>
          <span className="text-gray-900 dark:text-gray-100">${fmt(materials_total)}</span>
        </div>
        <div className="flex justify-between">
          <span className="text-gray-600 dark:text-gray-300">Tooling</span>
          <span className="text-gray-900 dark:text-gray-100">${fmt(tooling_total)}</span>
        </div>
        <div className="flex justify-between">
          <span className="text-gray-600 dark:text-gray-300">Labor</span>
          <span className="text-gray-900 dark:text-gray-100">${fmt(labor_total)}</span>
        </div>
        <div className="flex justify-between">
          <span className="text-gray-600 dark:text-gray-300">Subcontractors</span>
          <span className="text-gray-900 dark:text-gray-100">${fmt(subcontractor_total)}</span>
        </div>
      </div>
      <div className="my-3 border-t border-gray-200 pt-3 dark:border-gray-600">
        <div className="flex justify-between font-medium text-gray-900 dark:text-white">
          <span>Subtotal</span>
          <span>${fmt(subtotal)}</span>
        </div>
        {Number(final_markup_percent) > 0 && (
          <div className="mt-1 flex justify-between text-gray-600 dark:text-gray-300">
            <span>Final Markup ({final_markup_percent}%)</span>
            <span>${fmt(markupAmount)}</span>
          </div>
        )}
      </div>
      <div className="border-t border-gray-200 pt-3 font-bold dark:border-gray-600">
        <div className="flex justify-between text-gray-900 dark:text-white">
          <span>TOTAL (CAD)</span>
          <span>${fmt(final_total_cad)}</span>
        </div>
        <div className="mt-1 flex justify-between text-gray-700 dark:text-gray-300">
          <span>TOTAL (USD)</span>
          <span>${fmt(final_total_usd)}</span>
        </div>
        <div className="mt-2 flex justify-between border-t border-gray-100 pt-2 text-gray-900 dark:border-gray-700 dark:text-white">
          <span>REVENUE</span>
          <span>
            ({fmt(marginPercent)}% margin) ${fmt(revenueCad)}
          </span>
        </div>
      </div>
    </Card>
  )
}
