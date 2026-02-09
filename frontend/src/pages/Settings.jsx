import { useState, useEffect } from 'react'
import { Layout } from '../components/layout/Layout'
import { Card } from '../components/ui/Card'
import { Input } from '../components/ui/Input'
import { Button } from '../components/ui/Button'
import { getSettings, createSettings, updateSettings } from '../lib/api'
import { fetchExchangeRate } from '../lib/exchangeRate'
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

export function Settings() {
  const [settings, setSettings] = useState(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [fetchingRate, setFetchingRate] = useState(false)
  const [message, setMessage] = useState(null)

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

  if (loading || !settings) {
    return (
      <Layout>
        <div className="py-8 text-center text-gray-500">Loading settings…</div>
      </Layout>
    )
  }

  const num = (v) => (v === '' || v == null ? '' : Number(v))

  return (
    <Layout>
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-bold text-gray-900">Settings</h1>
        <Button disabled={saving} onClick={handleSave}>
          {saving ? 'Saving…' : 'Save'}
        </Button>
      </div>

      {message && (
        <p className="mb-4 rounded-lg bg-gray-100 px-3 py-2 text-sm text-gray-700">
          {message}
        </p>
      )}

      <Card className="mb-6">
        <h2 className="mb-3 text-lg font-semibold text-gray-900">
          Default markups
        </h2>
        <p className="mb-4 text-sm text-gray-500">
          Used when creating a new quote.
        </p>
        <div className="grid gap-4 sm:grid-cols-2">
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

      <Card className="mb-6">
        <h2 className="mb-3 text-lg font-semibold text-gray-900">
          Exchange rate (USD → CAD)
        </h2>
        <p className="mb-4 text-sm text-gray-500">
          Used for converting material costs and quote totals. Fetch from Bank of Canada or enter manually.
        </p>
        <div className="flex flex-wrap items-end gap-4">
          <Input
            type="number"
            step="0.0001"
            label="Rate"
            value={settings.exchange_rate_usd_to_cad ?? ''}
            onChange={(e) =>
              handleChange('exchange_rate_usd_to_cad', e.target.value === '' ? '' : num(e.target.value))
            }
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
          <p className="mt-2 text-sm text-gray-500">
            Last updated: {format(new Date(settings.exchange_rate_last_updated), 'MMM d, yyyy HH:mm')}
          </p>
        )}
        <div className="mt-4">
          <label className="flex cursor-pointer items-center gap-2">
            <input
              type="checkbox"
              checked={!!settings.exchange_rate_auto_update}
              onChange={(e) => handleChange('exchange_rate_auto_update', e.target.checked)}
              className="rounded border-gray-300"
            />
            <span className="text-sm font-medium text-gray-700">
              Auto-update rate (e.g. on app load)
            </span>
          </label>
          <p className="mt-1 text-xs text-gray-500">
            When enabled, the app can refresh the rate automatically. Manual fetch still available above.
          </p>
        </div>
      </Card>

      <Card className="mb-6">
        <h2 className="mb-3 text-lg font-semibold text-gray-900">
          Default hourly rates (CAD)
        </h2>
        <p className="mb-4 text-sm text-gray-500">
          Used when creating a new quote.
        </p>
        <div className="grid gap-4 sm:grid-cols-2">
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

      <Card className="mb-6">
        <h2 className="mb-3 text-lg font-semibold text-gray-900">
          Session
        </h2>
        <p className="mb-4 text-sm text-gray-500">
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
    </Layout>
  )
}
