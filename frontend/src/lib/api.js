import { pb } from './pocketbase'

export async function getQuotes(params = {}) {
  const list = await pb.collection('quotes').getList(1, params.perPage ?? 100, {
    expand: 'customer',
    ...params,
  })
  return list
}

export async function getQuote(id) {
  return pb.collection('quotes').getOne(id, { expand: 'customer' })
}

export async function createQuote(data) {
  return pb.collection('quotes').create(data)
}

export async function updateQuote(id, data) {
  return pb.collection('quotes').update(id, data)
}

export async function deleteQuote(id) {
  return pb.collection('quotes').delete(id)
}

export async function getQuoteLineItems(quoteId) {
  const list = await pb.collection('quote_line_items').getList(1, 200, {
    filter: `quote = "${quoteId}"`,
    sort: 'line_number',
    expand: 'material_vendor,subcontractor_1,subcontractor_2',
  })
  return list.items
}

/** Fetch all line items (for search by part number). Returns items only. */
export async function getAllLineItems() {
  const list = await pb.collection('quote_line_items').getList(1, 2000, {
    sort: 'line_number',
    fields: 'quote,part_number',
  })
  return list.items ?? []
}

export async function createLineItem(data) {
  return pb.collection('quote_line_items').create(data)
}

export async function updateLineItem(id, data) {
  return pb.collection('quote_line_items').update(id, data)
}

export async function deleteLineItem(id) {
  return pb.collection('quote_line_items').delete(id)
}

export async function getJobs(params = {}) {
  const list = await pb.collection('jobs').getList(1, params.perPage ?? 500, {
    expand: 'customer',
    ...params,
  })
  return list
}

export async function getJob(id) {
  return pb.collection('jobs').getOne(id, { expand: 'quote,customer,material_source_vendor' })
}

export async function createJob(data) {
  return pb.collection('jobs').create(data)
}

export async function updateJob(id, data) {
  return pb.collection('jobs').update(id, data)
}

export async function deleteJob(id) {
  return pb.collection('jobs').delete(id)
}

export async function getCustomers(params = {}) {
  const list = await pb.collection('customers').getList(1, params.perPage ?? 500, {
    sort: 'name',
    ...params,
  })
  return list
}

export async function getCustomer(id) {
  return pb.collection('customers').getOne(id)
}

export async function createCustomer(data) {
  return pb.collection('customers').create(data)
}

export async function updateCustomer(id, data) {
  return pb.collection('customers').update(id, data)
}

export async function deleteCustomer(id) {
  return pb.collection('customers').delete(id)
}

export async function getVendors(params = {}) {
  const list = await pb.collection('vendors').getList(1, params.perPage ?? 500, {
    sort: 'name',
    ...params,
  })
  return list
}

export async function getVendor(id) {
  return pb.collection('vendors').getOne(id)
}

export async function createVendor(data) {
  return pb.collection('vendors').create(data)
}

export async function updateVendor(id, data) {
  return pb.collection('vendors').update(id, data)
}

export async function deleteVendor(id) {
  return pb.collection('vendors').delete(id)
}

export async function getSettings() {
  try {
    return await pb.collection('settings').getFirstListItem('id != ""')
  } catch {
    return null
  }
}

export async function createSettings(data) {
  return pb.collection('settings').create(data)
}

export async function updateSettings(id, data) {
  return pb.collection('settings').update(id, data)
}

/** Check if a job already exists for a quote */
export async function getJobByQuote(quoteId) {
  try {
    return await pb.collection('jobs').getFirstListItem(`quote = "${quoteId}"`)
  } catch {
    return null
  }
}
