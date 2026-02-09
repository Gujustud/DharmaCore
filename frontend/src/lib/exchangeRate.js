/**
 * Fetch current USD to CAD exchange rate from Bank of Canada.
 * @returns {Promise<number|null>} - Rate or null on error
 */
export async function fetchExchangeRate() {
  try {
    const res = await fetch(
      'https://www.bankofcanada.ca/valet/observations/FXUSDCAD/json?recent=1'
    )
    const data = await res.json()
    const observations = data?.observations
    if (observations && observations.length > 0) {
      const v = observations[0].FXUSDCAD?.v
      return v != null ? Number(v) : null
    }
    return null
  } catch {
    return null
  }
}
