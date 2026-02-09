# CNC Quote Tracker - Development Plan v3.0
**Complete Specification with Job Tracking**  
**Optimized for Cursor AI Development**

---

## 📋 Table of Contents
1. [Project Overview](#project-overview)
2. [Tech Stack](#tech-stack)
3. [Database Schema](#database-schema)
4. [Calculation Formulas](#calculation-formulas)
5. [UI Components & Wireframes](#ui-components--wireframes)
6. [Development Phases](#development-phases)
7. [Cursor Prompts](#cursor-prompts)
8. [Folder Structure](#folder-structure)
9. [Success Criteria](#success-criteria)

---

## Project Overview

### What You're Building
A complete shop management system for your CNC machine shop that handles:
- **Quoting:** Estimate costs for customer jobs (materials, tooling, labor, subcontractors)
- **Job Tracking:** Manage active jobs from quote acceptance through delivery
- **Customers & Vendors:** Maintain relationships and history
- **Invoicing Integration:** Link to Wave accounting

### Why This App
**Replaces:**
- Excel quote sheets (hard to search, no history)
- Notion job tracking (separate system, manual data entry)

**Benefits:**
- Single source of truth for all job data
- Fast search by job #, customer, part number
- Quote → Job workflow (auto-create job when quote won)
- Compare estimated vs. actual costs
- Complete job history with shipping tracking

### Key Workflow
```
1. Customer Inquiry
   ↓
2. Create Quote (estimate costs)
   ↓
3. Send to Customer
   ↓
4. Customer Accepts → Mark as "Won"
   ↓
5. Job Auto-Created (status: Planning)
   ↓
6. Track Job Progress (Planning → In Progress → Done)
   ↓
7. Ship & Track Delivery
   ↓
8. Link Wave Invoice
   ↓
9. Mark as Paid
```

---

## Tech Stack

### Backend
- **PocketBase v0.22+**
  - Single binary (no separate server setup needed)
  - Built-in SQLite database
  - REST API + real-time subscriptions
  - Admin UI at `/_/`
  - No custom backend code needed (use hooks if necessary)

### Frontend
- **React 18** with **Vite**
- **Tailwind CSS** for styling
- **React Router v6** for navigation
- **PocketBase JavaScript SDK** for API calls
- **date-fns** for date handling
- **react-beautiful-dnd** or **@dnd-kit** for Kanban drag-and-drop

### Development
- **Windows** laptop (local development)
- **VS Code** or **Cursor** (recommended)
- **Node.js 18+** and **npm**

### Deployment (Phase 2)
- **Proxmox LXC Container** (Ubuntu 22.04)
- **CloudFlare Tunnel** OR **Caddy** reverse proxy
- **Domain:** quotes.sscadcam.com

---

## Database Schema

### Design Principles
- **snake_case** for all field names (PocketBase convention)
- **Relations** link records between collections
- **Calculated fields** stored for performance (recalculated on save)
- **Indexes** on frequently searched fields

---

### Collection 1: `customers`

```javascript
{
  // Auto-generated
  id: string (auto),
  created: datetime (auto),
  updated: datetime (auto),
  
  // Fields
  name: string (required, indexed),
  company: string (optional),
  email: string (optional),
  phone: string (optional),
  address: text (optional),
  notes: text (optional)
}
```

**Indexes:**
- `name` (for fast search)

**API Rules:**
- None (standard CRUD)

**Example Record:**
```json
{
  "id": "abc123",
  "name": "Matt",
  "company": "H1 Manufacturing",
  "email": "matt@h1.com",
  "phone": "555-1234",
  "address": "123 Industrial Way",
  "notes": "Prefers FedEx shipping"
}
```

---

### Collection 2: `vendors`

```javascript
{
  // Auto-generated
  id: string (auto),
  created: datetime (auto),
  updated: datetime (auto),
  
  // Fields
  name: string (required, indexed),
  vendor_type: select (material_supplier, subcontractor, other) (required),
  contact_person: string (optional),
  email: string (optional),
  phone: string (optional),
  services: text (optional), // "Anodizing, Powder Coating"
  notes: text (optional)
}
```

**Indexes:**
- `name` (for fast search)

**API Rules:**
- None

**Example Records:**
```json
{
  "id": "vendor1",
  "name": "McMaster-Carr",
  "vendor_type": "material_supplier",
  "phone": "555-5000",
  "notes": "Fast shipping, reliable"
}

{
  "id": "vendor2",
  "name": "Anodizing Co",
  "vendor_type": "subcontractor",
  "contact_person": "John Smith",
  "services": "Anodizing, Type II and Type III",
  "notes": "2 week turnaround typical"
}
```

---

### Collection 3: `quotes`

```javascript
{
  // Auto-generated
  id: string (auto),
  created: datetime (auto),
  updated: datetime (auto),
  
  // Job identification
  job_number: string (required, unique, indexed), // "01082026" (MMDDYYYY)
  wave_quote_number: string (optional, indexed), // "Q-2026-015" (from Wave)
  
  // Customer
  customer: relation (customers, optional),
  customer_name: string (optional), // Fallback if no customer relation
  
  // Quote details
  po_number: string (optional),
  engineer: string (required), // Who created the quote
  status: select (draft, sent, won, lost) (default: draft),
  
  // Settings (editable per quote)
  shipping_markup_percent: number (default: 30),
  final_markup_percent: number (default: 0),
  exchange_rate_usd_to_cad: number (required), // Locked when quote created
  
  // Hourly rates
  hourly_rate_programming: number (required),
  hourly_rate_setup: number (required),
  hourly_rate_first_run: number (required),
  hourly_rate_production: number (required),
  
  // Calculated totals (computed from line items)
  materials_total: number (default: 0),
  tooling_total: number (default: 0),
  labor_total: number (default: 0),
  subcontractor_total: number (default: 0),
  subtotal: number (default: 0),
  final_total_cad: number (default: 0),
  final_total_usd: number (default: 0),
  
  // Notes
  notes: text (optional)
}
```

**Indexes:**
- `job_number` (unique)
- `wave_quote_number` (optional)
- `status` (for filtering)
- `created` (for date sorting)
- `customer` (for customer history)

**API Rules / Hooks:**
```javascript
// Before create:
- If job_number not provided, auto-generate from today's date (MMDDYYYY)
- Copy default values from settings (rates, markups, exchange rate)

// Before update:
- If status changes to "won", create job record (see jobs collection)
- Recalculate totals from line items

// After line item changes:
- Trigger quote total recalculation
```

**Example Record:**
```json
{
  "id": "quote1",
  "job_number": "01082026",
  "wave_quote_number": "Q-2026-015",
  "customer": "abc123",
  "customer_name": "Matt",
  "po_number": "S0295625",
  "engineer": "Amish",
  "status": "won",
  "shipping_markup_percent": 30,
  "final_markup_percent": 15,
  "exchange_rate_usd_to_cad": 1.30,
  "hourly_rate_programming": 350,
  "hourly_rate_setup": 350,
  "hourly_rate_first_run": 350,
  "hourly_rate_production": 269,
  "final_total_cad": 14472.00,
  "final_total_usd": 11132.31
}
```

---

### Collection 4: `quote_line_items`

```javascript
{
  // Auto-generated
  id: string (auto),
  created: datetime (auto),
  updated: datetime (auto),
  
  // Parent relationship
  quote: relation (quotes, required, cascade delete),
  line_number: number (required), // 1, 2, 3... for ordering
  
  // PART INFO
  part_number: string (optional, indexed), // Customer's part #
  part_quantity: number (required, default: 1),
  
  // MATERIALS
  alloy: string (optional),
  stock_size_per_part: string (optional),
  ordered_length: string (optional),
  pieces: number (optional),
  material_note: text (optional), // "Using 6" from stock"
  
  material_vendor: relation (vendors, optional),
  vendor_supplied: string (optional),
  usd_cost: number (default: 0),
  testing_cost: number (default: 0),
  
  ut_cost: number (default: 0), // Ultrasonic Testing
  dp_cost: number (default: 0), // Dye Penetration
  
  // TOOLING
  tooling_total_cost: number (default: 0),
  tooling_description: text (optional),
  
  // LABOR
  programming_hours: number (default: 0),
  setup_hours: number (default: 0),
  first_run_hours: number (default: 0),
  production_hours_total: number (default: 0),
  
  // SUBCONTRACTORS
  subcontractor_1: relation (vendors, optional),
  subcontractor_1_service: string (optional),
  subcontractor_1_cost: number (default: 0),
  subcontractor_1_shipping: number (default: 0),
  
  subcontractor_2: relation (vendors, optional),
  subcontractor_2_service: string (optional),
  subcontractor_2_cost: number (default: 0),
  subcontractor_2_shipping: number (default: 0),
  
  // POST-PROCESSING
  heat_treat_cost: number (default: 0),
  inspection_cost: number (default: 0),
  packaging_cost: number (default: 0),
  shipping_cost: number (default: 0),
  
  // REFERENCE
  previous_quote_reference: text (optional),
  
  // CALCULATED FIELDS (computed on save)
  material_actual_cost_cad: number (default: 0),
  material_with_markup: number (default: 0),
  labor_cost: number (default: 0),
  subcontractor_1_total: number (default: 0),
  subcontractor_2_total: number (default: 0),
  line_total_cad: number (default: 0),
  price_per_part_cad: number (default: 0),
  price_per_part_usd: number (default: 0)
}
```

**Indexes:**
- `quote` (for loading all line items of a quote)
- `part_number` (for searching similar parts)

**API Rules / Hooks:**
```javascript
// Before save:
- Calculate all computed fields (see formulas section)
- Trigger parent quote recalculation
```

**Example Record:**
```json
{
  "id": "line1",
  "quote": "quote1",
  "line_number": 1,
  "part_number": "H1CS92-00445-3401",
  "part_quantity": 2,
  "alloy": "Ti Grade 5",
  "usd_cost": 60,
  "tooling_total_cost": 50,
  "programming_hours": 1,
  "setup_hours": 1,
  "first_run_hours": 3,
  "production_hours_total": 3,
  "line_total_cad": 1621.50,
  "price_per_part_cad": 810.75
}
```

---

### Collection 5: `jobs`

**NEW - For Job Tracking**

```javascript
{
  // Auto-generated
  id: string (auto),
  created: datetime (auto),
  updated: datetime (auto),
  
  // Parent relationship
  quote: relation (quotes, required, unique), // One job per quote
  job_number: string (required, indexed), // Same as quote job_number
  
  // AUTO-FILLED FROM QUOTE (on creation)
  customer: relation (customers, optional),
  customer_name: string (optional),
  parts_description: text (optional), // Auto-generated from line items
  
  // JOB STATUS (Kanban columns)
  status: select (
    planning,      // Quote won, preparing for production
    in_progress,   // Actively machining
    done,          // Complete and shipped
    cancelled      // Job cancelled
  ) (default: planning),
  
  // DATES
  due_date: date (optional),
  completion_date: date (optional),
  ship_date: date (optional),
  
  // SHIPPING TRACKING
  tracking_status: select (
    not_shipped,
    in_transit,
    delivered
  ) (default: not_shipped),
  
  tracking_number_1: string (optional),
  tracking_link_1: url (optional), // Auto-generate from tracking number
  tracking_number_2: string (optional), // For multiple shipments
  tracking_link_2: url (optional),
  
  // INVOICING (Wave integration)
  wave_invoice_number: string (optional), // "S1369"
  po_number: string (optional), // Customer's PO "S0295625"
  
  // MATERIAL TRACKING
  material_lot: string (optional), // "24204497"
  material_source: string (optional), // "McMaster" or "From previous job"
  material_notes: text (optional),
  
  // NOTES & DETAILS
  project_notes: text (optional), // Rich text area
  notes: text (optional)
}
```

**Indexes:**
- `quote` (unique - one job per quote)
- `job_number` (for searching)
- `status` (for Kanban filtering)

**API Rules / Hooks:**
```javascript
// Auto-created when quote status → "won":
{
  quote: quote_id,
  job_number: quote.job_number,
  customer: quote.customer,
  customer_name: quote.customer_name,
  parts_description: auto_generate_from_line_items(quote),
  status: "planning",
  po_number: quote.po_number
}

// Auto-generate tracking links:
- If tracking_number_1 starts with "1Z": UPS link
- If tracking_number_1 is 12 digits: FedEx link
- etc.
```

**Example Record:**
```json
{
  "id": "job1",
  "quote": "quote1",
  "job_number": "11242025",
  "customer": "abc123",
  "customer_name": "Matt",
  "parts_description": "• RE Tail Camera Housing PN H1CS92-00445-3401 Qty 1",
  "status": "done",
  "completion_date": "2026-01-07",
  "ship_date": "2026-01-07",
  "tracking_status": "delivered",
  "tracking_number_1": "887709391036",
  "tracking_link_1": "https://fedex.com/tracking?tracknumbers=887709391036",
  "wave_invoice_number": "S1369",
  "po_number": "S0295625",
  "material_lot": "24204497",
  "material_source": "From previous H1 order",
  "project_notes": "Material from previous H1 order. Supplied by H1 Order: 1404885100"
}
```

---

### Collection 6: `settings`

**Singleton** (only one record)

```javascript
{
  // Fixed ID
  id: "settings_singleton" (fixed),
  updated: datetime (auto),
  
  // DEFAULT VALUES FOR NEW QUOTES
  default_shipping_markup_percent: number (default: 30),
  default_final_markup_percent: number (default: 0),
  
  // DEFAULT HOURLY RATES
  default_hourly_rate_programming: number (default: 350),
  default_hourly_rate_setup: number (default: 350),
  default_hourly_rate_first_run: number (default: 350),
  default_hourly_rate_production: number (default: 269),
  
  // EXCHANGE RATE
  exchange_rate_usd_to_cad: number (default: 1.30),
  exchange_rate_auto_update: bool (default: true),
  exchange_rate_last_updated: datetime (optional)
}
```

**API Rules:**
```javascript
// On app load (if auto_update enabled):
- Fetch current rate from Bank of Canada API
- If different from stored rate, update exchange_rate_usd_to_cad
- Update exchange_rate_last_updated

// Create on first run if doesn't exist
```

---

## Calculation Formulas

### Implementation Notes
- All calculations in `frontend/src/lib/calculations.js`
- Also implement in PocketBase hooks for server-side validation
- Handle edge cases (null values, division by zero)
- Match Excel formulas exactly

---

### Line Item Calculations

```javascript
/**
 * Calculate all computed fields for a line item
 * @param {Object} lineItem - The line item data
 * @param {Object} quoteSettings - Parent quote settings (rates, markups, exchange rate)
 * @returns {Object} - Line item with calculated fields
 */
function calculateLineItem(lineItem, quoteSettings) {
  const {
    usd_cost = 0,
    testing_cost = 0,
    ut_cost = 0,
    dp_cost = 0,
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
    part_quantity = 1
  } = lineItem;
  
  const {
    exchange_rate_usd_to_cad,
    shipping_markup_percent,
    hourly_rate_programming,
    hourly_rate_setup,
    hourly_rate_first_run,
    hourly_rate_production
  } = quoteSettings;
  
  // 1. MATERIAL COSTS
  const material_actual_cost_cad = usd_cost * exchange_rate_usd_to_cad;
  
  const material_with_markup = 
    (testing_cost + material_actual_cost_cad) * 
    (1 + shipping_markup_percent / 100);
  
  // 2. TOOLING (direct input, no calculation)
  const tooling_total = tooling_total_cost;
  
  // 3. LABOR COSTS
  const labor_cost = 
    (programming_hours * hourly_rate_programming) +
    (setup_hours * hourly_rate_setup) +
    (first_run_hours * hourly_rate_first_run) +
    (production_hours_total * hourly_rate_production);
  
  // 4. SUBCONTRACTOR COSTS
  const subcontractor_1_total = subcontractor_1_cost + subcontractor_1_shipping;
  const subcontractor_2_total = subcontractor_2_cost + subcontractor_2_shipping;
  
  // 5. LINE ITEM TOTAL
  const line_total_cad = 
    material_with_markup +
    tooling_total +
    labor_cost +
    subcontractor_1_total +
    subcontractor_2_total +
    ut_cost +
    dp_cost +
    heat_treat_cost +
    inspection_cost +
    packaging_cost +
    shipping_cost;
  
  // 6. PER-PART PRICING
  const price_per_part_cad = part_quantity > 0 ? line_total_cad / part_quantity : 0;
  const price_per_part_usd = exchange_rate_usd_to_cad > 0 ? 
    price_per_part_cad / exchange_rate_usd_to_cad : 0;
  
  // Return updated line item with calculated fields
  return {
    ...lineItem,
    material_actual_cost_cad,
    material_with_markup,
    labor_cost,
    subcontractor_1_total,
    subcontractor_2_total,
    line_total_cad,
    price_per_part_cad,
    price_per_part_usd
  };
}
```

---

### Quote Totals Calculation

```javascript
/**
 * Calculate quote-level totals from all line items
 * @param {Object} quote - The quote record
 * @param {Array} lineItems - Array of line items (already calculated)
 * @returns {Object} - Quote with calculated totals
 */
function calculateQuoteTotals(quote, lineItems) {
  const { final_markup_percent = 0, exchange_rate_usd_to_cad } = quote;
  
  // Sum all line items
  const materials_total = lineItems.reduce(
    (sum, item) => sum + (item.material_with_markup || 0), 0
  );
  
  const tooling_total = lineItems.reduce(
    (sum, item) => sum + (item.tooling_total_cost || 0), 0
  );
  
  const labor_total = lineItems.reduce(
    (sum, item) => sum + (item.labor_cost || 0), 0
  );
  
  const subcontractor_total = lineItems.reduce(
    (sum, item) => sum + 
      (item.subcontractor_1_total || 0) + 
      (item.subcontractor_2_total || 0), 0
  );
  
  const subtotal = lineItems.reduce(
    (sum, item) => sum + (item.line_total_cad || 0), 0
  );
  
  // Apply final markup
  const final_total_cad = subtotal * (1 + final_markup_percent / 100);
  const final_total_usd = exchange_rate_usd_to_cad > 0 ?
    final_total_cad / exchange_rate_usd_to_cad : 0;
  
  return {
    ...quote,
    materials_total,
    tooling_total,
    labor_total,
    subcontractor_total,
    subtotal,
    final_total_cad,
    final_total_usd
  };
}
```

---

### Auto-Generate Job Number

```javascript
/**
 * Generate job number from date
 * Format: MMDDYYYY
 * @param {Date} date - Date object (default: today)
 * @returns {string} - Job number
 */
function generateJobNumber(date = new Date()) {
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const year = String(date.getFullYear());
  
  return `${month}${day}${year}`;
}

// Example: Jan 8, 2026 → "01082026"
```

---

### Auto-Generate Parts Description (for Job)

```javascript
/**
 * Generate parts description from quote line items
 * @param {Array} lineItems - Quote line items
 * @returns {string} - Formatted parts list
 */
function generatePartsDescription(lineItems) {
  return lineItems
    .map(item => {
      const partNum = item.part_number || 'Unnamed Part';
      const qty = item.part_quantity || 1;
      return `• ${partNum} (qty ${qty})`;
    })
    .join('\n');
}

// Example output:
// • RE Tail Camera Housing PN H1CS92-00445-3401 (qty 1)
// • OPTION 2 ARM (qty 2)
```

---

### Auto-Generate Tracking Link

```javascript
/**
 * Generate tracking URL from tracking number
 * @param {string} trackingNumber
 * @returns {string} - Tracking URL
 */
function generateTrackingLink(trackingNumber) {
  if (!trackingNumber) return '';
  
  // Remove spaces and convert to uppercase
  const clean = trackingNumber.replace(/\s/g, '').toUpperCase();
  
  // FedEx (12-14 digits)
  if (/^\d{12,14}$/.test(clean)) {
    return `https://www.fedex.com/fedextrack/?tracknumbers=${clean}`;
  }
  
  // UPS (starts with 1Z)
  if (/^1Z/.test(clean)) {
    return `https://www.ups.com/track?tracknum=${clean}`;
  }
  
  // Canada Post (13 digits)
  if (/^\d{13}$/.test(clean)) {
    return `https://www.canadapost-postescanada.ca/track-reperage/en#/search?searchFor=${clean}`;
  }
  
  // Purolator (starts with P)
  if (/^P/.test(clean)) {
    return `https://www.purolator.com/en/shipping/tracker?pin=${clean}`;
  }
  
  // Default: just return the number
  return clean;
}
```

---

## UI Components & Wireframes

### Design System

**Colors:**
- Primary: Purple gradient (#667eea → #764ba2)
- Success: Green (#059669)
- Warning: Yellow (#f59e0b)
- Danger: Red (#dc2626)
- Neutral: Gray scale (#f9fafb → #111827)

**Typography:**
- Font: System fonts (-apple-system, BlinkMacSystemFont, "Segoe UI", etc.)
- Headings: Bold, larger
- Body: Regular weight

**Components:**
- Cards: Rounded corners (12px), shadow
- Buttons: Rounded (8px), gradient for primary
- Inputs: Border (2px), rounded (8px), focus state
- Tables: Hover effects, zebra striping optional
- Badges: Small, rounded pills for status

---

### Page 1: Dashboard (`/`)

```
┌──────────────────────────────────────────────────────────────┐
│  Header: [Logo] Quotes | Jobs | Customers | Vendors | ⚙     │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌────────────────────────────────────────────────────┐      │
│  │  Quote Tracker                     [+ New Quote]   │      │
│  │  Manage your shop operations                       │      │
│  └────────────────────────────────────────────────────┘      │
│                                                               │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐       │
│  │ Quotes   │ │  Won     │ │ Pending  │ │ Revenue  │       │
│  │   12     │ │   5      │ │   3      │ │ $45,320  │       │
│  │ This Mo  │ │ 41% Win  │ │ Waiting  │ │ This Mo  │       │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘       │
│                                                               │
│  Recent Quotes                                                │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Job #     Customer   Status   Total      Action       │  │
│  ├────────────────────────────────────────────────────────┤  │
│  │ 01082026  Acme      Won       $14,472    View →       │  │
│  │ 12092025  XYZ Inc   Sent      $22,100    View →       │  │
│  │ 12042025  ABC Co    Draft     $5,600     Edit →       │  │
│  │ ...                                                     │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
│  Active Jobs                                                  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Job #     Customer   Status        Ship Date          │  │
│  ├────────────────────────────────────────────────────────┤  │
│  │ 01082026  Acme      In Progress   Jan 15              │  │
│  │ 11242025  Matt      Done          Shipped             │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

**Fields:**
- Stats cards: Real-time counts from database
- Recent quotes: Last 10, sorted by created date desc
- Active jobs: Jobs where status = in_progress or planning

---

### Page 2: Quotes List (`/quotes`)

```
┌──────────────────────────────────────────────────────────────┐
│  Header: [Logo] Quotes | Jobs | Customers | Vendors | ⚙     │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌────────────────────────────────────────────────────┐      │
│  │  All Quotes                        [+ New Quote]   │      │
│  └────────────────────────────────────────────────────┘      │
│                                                               │
│  Search: [_______________________]  Status: [All ▼]          │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Job #     Customer   Parts  Status   Total   Action   │  │
│  ├────────────────────────────────────────────────────────┤  │
│  │ 01082026  Acme      4       Won      $14,472  ⋮       │  │
│  │ 12092025  XYZ Inc   2       Sent     $22,100  ⋮       │  │
│  │ 12042025  ABC Co    1       Draft    $5,600   ⋮       │  │
│  │ ...                                                     │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
└──────────────────────────────────────────────────────────────┘

Actions Menu (⋮):
- View Details
- Edit Quote
- Copy Quote
- Delete Quote
- View Job (if won)
```

**Features:**
- Search: job_number, customer_name, part_number (searches line items)
- Filter by status: All, Draft, Sent, Won, Lost
- Sort columns (clickable headers)
- Pagination or infinite scroll

---

### Page 3: Quote Detail/Edit (`/quotes/:id`)

**Header Section:**
```
┌──────────────────────────────────────────────────────────────┐
│  Quote: [01082026_____________] [Auto-generate today's date] │
│  Wave Quote #: [Q-2026-015________] (optional)               │
│                                                               │
│  Customer: [Acme Corp ▼] or [+ Add New Customer]            │
│  PO Number: [PO-12345__________]                             │
│  Engineer: [Amish______________]                             │
│  Status: [Draft ▼] (Draft/Sent/Won/Lost)                    │
│                                                               │
│  Created: Jan 8, 2026  |  [View Job →] (if won)             │
│                                                               │
│  ┌─ ⚙ Quote Settings (click to expand) ──────────────────┐  │
│  │  Shipping Markup: [30__]%                              │  │
│  │  Final Markup: [15__]%                                 │  │
│  │  Exchange Rate (USD→CAD): [1.30__] [Fetch Current]    │  │
│  │  Programming Rate: [$350] /hr                          │  │
│  │  Setup Rate: [$350] /hr                                │  │
│  │  First Run Rate: [$350] /hr                            │  │
│  │  Production Rate: [$269] /hr                           │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

**Line Items Section:**

Each line item is a collapsible card:

```
┌──────────────────────────────────────────────────────────────┐
│  📦 Part 1: [OPTION 2 ARM_______________]  Qty: [2__]  [-]   │
│  ▼ Click to expand                                           │
├──────────────────────────────────────────────────────────────┤
│  ▼ MATERIALS                                                 │
│    Alloy: [Ti Grade 5_______]  Stock Size: [1x1x12"]        │
│    Ordered Length: [_____]  Pieces: [___]                   │
│    Vendor: [McMaster ▼]  Vendor Supplied: [__________]      │
│    USD Cost: [$60___]  Testing Cost: [$50___]               │
│    UT Cost: [$50___]  DP Cost: [$25___]                     │
│    Note: [Using 6" from stock_________________________]     │
│    → Material Total (CAD): $338.00                          │
│                                                              │
│  ▼ TOOLING                                                   │
│    Description: [3/8 endmill, 1/4 ballnose, fixture____]    │
│    Total Cost: [$150___]                                    │
│                                                              │
│  ▼ LABOR                                                     │
│    Programming: [2__] hrs  Setup: [1__] hrs                 │
│    First Run: [4__] hrs  Production Total: [4__] hrs        │
│    → Labor Total: $2,100.00                                 │
│                                                              │
│  ▼ SUBCONTRACTORS                                            │
│    Subcontractor 1: [Anodizing Co ▼]                        │
│      Service: [Anodizing________]                           │
│      Cost: [$300]  Shipping: [$50]                          │
│    Subcontractor 2: [Heat Treat Inc ▼]                      │
│      Service: [Heat Treat_______]                           │
│      Cost: [$200]  Shipping: [$30]                          │
│    → Subcontractor Total: $580.00                           │
│                                                              │
│  ▼ POST-PROCESSING                                           │
│    Heat Treat: [$40___]  Inspection: [$50___]               │
│    Packaging: [$25___]  Shipping: [$15___]                  │
│                                                              │
│  ▼ REFERENCE                                                 │
│    Previous Quote: [Similar to #11182025, $485/part____]    │
│    [🔍 Find Similar Parts]                                  │
│                                                              │
│  LINE TOTALS:                                                │
│    Total (CAD): $3,243.00                                   │
│    Per Part (CAD): $1,621.50                                │
│    Per Part (USD): $1,247.31                                │
│                                                              │
│  [Delete This Part]                                          │
└──────────────────────────────────────────────────────────────┘

[+ Add Another Part]
```

**Quote Totals (Sticky Sidebar or Footer):**
```
┌──────────────────────────────────┐
│  QUOTE TOTALS                    │
├──────────────────────────────────┤
│  Materials:      $  1,352.00     │
│  Tooling:        $    300.00     │
│  Labor:          $  4,200.00     │
│  Subcontractors: $  1,160.00     │
│  Other Costs:    $    260.00     │
├──────────────────────────────────┤
│  Subtotal:       $  7,272.00     │
│  Final Markup:   $  1,090.80     │
│                  (15%)           │
├──────────────────────────────────┤
│  TOTAL (CAD):    $ 14,472.00     │
│  TOTAL (USD):    $ 11,132.31     │
└──────────────────────────────────┘
```

**Action Buttons:**
```
[Save Draft]  [Mark as Sent]  [Copy Quote]  [Delete Quote]
```

**When status changed to "Won":**
```
🎉 Job Created! [View Job →]
```

---

### Page 4: Jobs Board (`/jobs`)

**Kanban Board (Default View):**

```
┌──────────────────────────────────────────────────────────────┐
│  Header: [Logo] Quotes | Jobs | Customers | Vendors | ⚙     │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌────────────────────────────────────────────────────┐      │
│  │  Jobs            [Board] [List] [Calendar]         │      │
│  └────────────────────────────────────────────────────┘      │
│                                                               │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌────────┐│
│  │  Planning   │ │ In Progress │ │    Done     │ │Cancel'd││
│  ├─────────────┤ ├─────────────┤ ├─────────────┤ ├────────┤│
│  │ ┌─────────┐ │ │ ┌─────────┐ │ │ ┌─────────┐ │ │ ┌────┐││
│  │ │FCRS     │ │ │ │01082026 │ │ │ │H1-11242 │ │ │ │0407│││
│  │ │Prototype│ │ │ │Matt     │ │ │ │Matt     │ │ │ │MRL ││( 
│  │ │         │ │ │ │         │ │ │ │Shipped  │ │ │ └────┘││
│  │ └─────────┘ │ │ └─────────┘ │ │ └─────────┘ │ │        ││
│  │             │ │ ┌─────────┐ │ │ ┌─────────┐ │ │        ││
│  │             │ │ │01232026 │ │ │ │11182025 │ │ │        ││
│  │ + New       │ │ │H1       │ │ │ │Matt     │ │ │ + New  ││
│  │             │ │ │         │ │ │ │         │ │ │        ││
│  │             │ │ └─────────┘ │ │ └─────────┘ │ │        ││
│  │             │ │             │ │ ┌─────────┐ │ │        ││
│  │             │ │ + New       │ │ │10292025 │ │ │        ││
│  │             │ │             │ │ │MRL 1029 │ │ │        ││
│  └─────────────┘ └─────────────┘ │ └─────────┘ │ └────────┘│
│                                   │ ...         │           │
│                                   │ + New       │           │
│                                   └─────────────┘           │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Features:**
- Drag & drop cards between columns to change status
- Click card to view/edit job details
- Color-coded by status
- Shows job # and customer name

---

### Page 5: Job Detail (`/jobs/:id`)

```
┌──────────────────────────────────────────────────────────────┐
│  ◎ Job: H1 - 11242025                   [View Quote →]      │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ● Status              [Done ▼] (Planning/In Prog/Done/...)  │
│  📅 Due Date           [______________]                       │
│  📅 Ship Date          [January 7, 2026_______]              │
│  ☑ Completion Date    [January 7, 2026_______]              │
│                                                               │
│  ═══ SHIPPING ═══                                            │
│  📍 Tracking Status    [Delivered ▼]                         │
│  # Tracking Number 1   [887709391036________]                │
│  🔗 Link               fedex.com/fed...391036 [🔗 Open]      │
│  # Tracking Number 2   [______________] (optional)           │
│  🔗 Link               [______________]                       │
│                                                               │
│  ═══ INVOICING ═══                                           │
│  ≡ Wave Invoice #      [S1369_______]                        │
│  ≡ Customer PO #       [S0295625____]                        │
│                                                               │
│  ═══ MATERIAL ═══                                            │
│  ≡ Material LOT        [24204497____]                        │
│  ≡ Source              [From previous H1 order___]           │
│  📝 Material Notes:                                          │
│  [Text area for material notes____________________]          │
│                                                               │
│  ═══ PROJECT DETAILS ═══                                     │
│  📋 Parts in this Job:                                       │
│  • RE Tail Camera Housing PN H1CS92-00445-3401 Qty 1         │
│                                                               │
│  📝 Project Notes (Rich Text):                               │
│  [Text area for detailed notes____________________]          │
│  • Material from previous H1 order.                          │
│  • Supplied by H1 Order: 1404885100                          │
│                                                               │
│  [Save]  [Delete Job]  [Back to Jobs]                       │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

---

### Page 6: Customers (`/customers`)

```
┌──────────────────────────────────────────────────────────────┐
│  Customers                             [+ New Customer]       │
│                                                               │
│  Search: [_____________________]                              │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Name      Company        Phone       Quotes   Action   │  │
│  ├────────────────────────────────────────────────────────┤  │
│  │ Matt      H1 Mfg         555-1234    12       View →   │  │
│  │ Acme      Acme Inc       555-5678    8        View →   │  │
│  │ ...                                                     │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

**Customer Detail (Modal or Page):**
```
┌────────────────────────────────────────┐
│  Matt                       [Edit]     │
├────────────────────────────────────────┤
│  Company:  [H1 Manufacturing____]      │
│  Email:    [matt@h1.com_________]      │
│  Phone:    [555-1234____________]      │
│  Address:  [123 Industrial Way__]      │
│  Notes:    [Prefers FedEx_______]      │
│                                         │
│  Quote History (12 quotes)              │
│  - 01082026: $14,472 (Won)              │
│  - 11242025: $22,100 (Won)              │
│  - ...                                  │
│                                         │
│  [Save]  [Delete]  [Close]             │
└────────────────────────────────────────┘
```

---

### Page 7: Vendors (`/vendors`)

Similar to Customers, with Type filter:

```
┌──────────────────────────────────────────────────────────────┐
│  Vendors                               [+ New Vendor]         │
│                                                               │
│  Type: [All ▼]  Search: [_____________________]              │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Name         Type               Phone       Action     │  │
│  ├────────────────────────────────────────────────────────┤  │
│  │ McMaster     Material Supplier 555-1111    View →     │  │
│  │ Anodizing Co Subcontractor     555-2222    View →     │  │
│  │ ...                                                     │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

---

### Page 8: Settings (`/settings`)

```
┌──────────────────────────────────────────────────────────────┐
│  Settings                                                     │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ▼ DEFAULT VALUES FOR NEW QUOTES                             │
│    Shipping Markup: [30____]%                                │
│    Final Markup: [0_____]%                                   │
│                                                               │
│  ▼ DEFAULT HOURLY RATES                                      │
│    Programming: [$350___] /hr                                │
│    Setup:       [$350___] /hr                                │
│    First Run:   [$350___] /hr                                │
│    Production:  [$269___] /hr                                │
│                                                               │
│  ▼ EXCHANGE RATE (USD → CAD)                                 │
│    Current Rate: [1.30___]                                   │
│    [✓] Auto-update daily from Bank of Canada                 │
│    Last Updated: Jan 8, 2026 9:00 AM                         │
│    [⟳ Fetch Current Rate Now]                               │
│                                                               │
│  ▼ DATA MANAGEMENT (Future)                                  │
│    [Export All Data]                                         │
│    [Import Old Quotes]                                       │
│                                                               │
│  [Save Changes]                                              │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

---

## Development Phases

### Phase 1: Local Setup (Day 1)
**Goal:** PocketBase running with database schema

**Steps:**
1. Install Node.js 18+ (if not installed)
2. Download PocketBase for Windows
3. Run PocketBase: `pocketbase.exe serve`
4. Access admin UI: `http://127.0.0.1:8090/_/`
5. Create admin account
6. Create all collections (see Database Schema section)
7. Configure field types, relations, constraints
8. Create settings singleton record
9. Add sample data (2 customers, 2-3 vendors, 1 quote with line items)

**Deliverable:** Database ready with test data

**Validation:**
- Can view all collections in admin
- Relations work correctly
- Sample quote calculates properly

---

### Phase 2: React App Setup (Day 1-2)
**Goal:** Frontend connected to PocketBase

**Steps:**
1. Create React app:
   ```bash
   npm create vite@latest quote-tracker-frontend -- --template react
   cd quote-tracker-frontend
   ```

2. Install dependencies:
   ```bash
   npm install pocketbase react-router-dom date-fns
   npm install -D tailwindcss postcss autoprefixer
   npx tailwindcss init -p
   ```

3. Configure Tailwind (`tailwind.config.js`):
   ```javascript
   export default {
     content: ['./index.html', './src/**/*.{js,jsx}'],
     theme: { extend: {} },
     plugins: [],
   }
   ```

4. Set up folder structure (see Folder Structure section)

5. Initialize PocketBase client (`src/lib/pocketbase.js`):
   ```javascript
   import PocketBase from 'pocketbase';
   export const pb = new PocketBase('http://127.0.0.1:8090');
   ```

6. Set up React Router (`src/App.jsx`):
   ```javascript
   import { BrowserRouter, Routes, Route } from 'react-router-dom';
   import Dashboard from './pages/Dashboard';
   import QuotesList from './pages/QuotesList';
   // ... other imports

   function App() {
     return (
       <BrowserRouter>
         <Routes>
           <Route path="/" element={<Dashboard />} />
           <Route path="/quotes" element={<QuotesList />} />
           {/* ... other routes */}
         </Routes>
       </BrowserRouter>
     );
   }
   ```

7. Create API wrapper (`src/lib/api.js`)

8. Build simple quotes list page that fetches data

**Deliverable:** React app showing quotes from PocketBase

**Validation:**
- `npm run dev` starts app
- Can see quotes list
- Clicking quote shows (basic) detail

---

### Phase 3: Calculation Engine (Day 2-3)
**Goal:** All formulas implemented and tested

**Steps:**
1. Create `src/lib/calculations.js`
2. Implement all calculation functions (see Formulas section)
3. Create test file with Excel data
4. Verify calculations match Excel exactly
5. Handle edge cases (null, zero, negative)

**Deliverable:** Calculation functions working perfectly

**Validation:**
- Input same data as Excel
- Output matches exactly
- Edge cases handled gracefully

---

### Phase 4: Quote Management UI (Days 3-5)
**Goal:** Create and edit quotes

**Steps:**
1. Build Quote Detail page (`src/pages/QuoteDetail.jsx`)
2. Build header form (job #, customer, PO, etc.)
3. Build line item component (`src/components/quote/LineItemCard.jsx`)
4. Add/delete line items
5. Real-time calculation updates
6. Save/update quote
7. Copy quote feature
8. Delete quote (with confirmation)
9. Form validation

**Deliverable:** Full quote creation/editing

**Validation:**
- Create quote from scratch
- Add multiple parts
- Calculations update instantly
- Save and reload works
- Copy creates new quote
- Delete works with confirm

---

### Phase 5: Search & Filtering (Day 5-6)
**Goal:** Fast search across quotes

**Steps:**
1. Implement search in QuotesList
2. Filter by status
3. Sort columns
4. "Find similar parts" feature
5. Debounced search input

**Deliverable:** Effective search

**Validation:**
- Search by job #, customer, part #
- Filters work
- Results instant (<500ms)

---

### Phase 6: Customer & Vendor Management (Day 6-7)
**Goal:** CRUD for customers and vendors

**Steps:**
1. Build Customers page
2. Build Vendors page
3. Add/edit/delete functionality
4. Integrate into quote form dropdowns
5. "Add new" inline buttons

**Deliverable:** Complete customer/vendor management

**Validation:**
- Add customer, use in quote immediately
- Edit vendor, changes reflected
- Delete with warnings

---

### Phase 7: Dashboard & Settings (Day 7)
**Goal:** Polish with dashboard and settings

**Steps:**
1. Build Dashboard with stats cards
2. Recent quotes/jobs widgets
3. Settings page
4. Exchange rate auto-fetch
5. Default values management

**Deliverable:** Complete settings and dashboard

**Validation:**
- Dashboard shows correct stats
- Settings persist
- Exchange rate updates

---

### Phase 8: Job Tracking (Days 7-9)
**Goal:** Full job management system

**Steps:**
1. Build Jobs Kanban board (`src/pages/JobsBoard.jsx`)
2. Implement drag & drop (use @dnd-kit/core)
3. Build Job Detail page
4. Auto-create job when quote won
5. Calendar view (optional)
6. List view (alternative to board)
7. Link between quote ↔ job
8. Auto-generate tracking links

**Deliverable:** Complete job tracking

**Validation:**
- Mark quote as won → job created
- Drag jobs between columns
- Update job details
- Tracking links work
- View job from quote and vice versa

---

### Phase 9: Testing & Refinement (Day 9-10)
**Goal:** Bug-free, polished app

**Steps:**
1. Test with real quote data
2. Mobile responsive testing
3. Performance check (50+ quotes)
4. UI polish (loading states, errors)
5. User testing (you using it)
6. Bug fixes

**Deliverable:** Production-ready app

**Validation:**
- No crashes
- All features work
- Mobile usable
- Fast and responsive

---

### Phase 10: Deployment to Proxmox (Day 10-11)
**Goal:** Live at quotes.sscadcam.com

**Steps:**
1. Create Ubuntu 22.04 LXC on Proxmox
2. Install PocketBase
3. Set up systemd service
4. Build React frontend: `npm run build`
5. Copy to PocketBase `pb_public/` folder
6. Configure CloudFlare Tunnel OR Caddy
7. Set up domain
8. Migrate data from laptop
9. Test remote access

**Deliverable:** App accessible remotely

**Validation:**
- Access from desktop at shop
- Access from phone
- Access remotely (CloudFlare)
- All data migrated correctly

---

## Cursor Prompts

### Recommended Cursor Workflow

For each phase, paste the relevant prompt into Cursor along with `@PLAN.md` to give context.

---

### Phase 1: Database Setup

**Cursor Prompt:**
```
I'm building a CNC quote tracker with PocketBase. I need to create the database schema.

Create the following collections with exact field names and types:

1. customers
- name (text, required, indexed)
- company (text)
- email (text)
- phone (text)
- address (long text)
- notes (long text)

2. vendors
- name (text, required, indexed)
- vendor_type (select: material_supplier, subcontractor, other)
- contact_person (text)
- email (text)
- phone (text)
- services (long text)
- notes (long text)

[Continue with other collections from schema...]

Provide the JSON configuration I can paste into PocketBase admin.
```

---

### Phase 2: React Setup

**Cursor Prompt:**
```
Set up a React app with Vite for a quote tracking system.

Requirements:
- React 18, Vite
- Tailwind CSS
- React Router v6
- PocketBase SDK
- date-fns for date handling

Create the folder structure:
- src/components/ui/ (reusable UI components)
- src/components/quote/ (quote-specific components)
- src/pages/ (page components)
- src/lib/ (utilities, API, calculations)
- src/hooks/ (custom React hooks)

Configure Tailwind with this color scheme:
- Primary: purple gradient (#667eea to #764ba2)
- Success: green (#059669)
- Neutral: gray scale

Set up React Router with these routes:
- / (Dashboard)
- /quotes (Quotes List)
- /quotes/:id (Quote Detail)
- /jobs (Jobs Board)
- /jobs/:id (Job Detail)
- /customers (Customers List)
- /vendors (Vendors List)
- /settings (Settings)

Initialize PocketBase client in src/lib/pocketbase.js connecting to http://127.0.0.1:8090
```

---

### Phase 3: Calculations

**Cursor Prompt:**
```
@PLAN.md

Implement the quote calculation formulas in src/lib/calculations.js

Create these functions:

1. calculateLineItem(lineItem, quoteSettings)
   - Takes line item data and quote settings
   - Returns line item with all calculated fields
   - Formula logic is in the plan

2. calculateQuoteTotals(quote, lineItems)
   - Takes quote and array of line items
   - Returns quote with totals
   - Formula logic is in the plan

3. generateJobNumber(date)
   - Format: MMDDYYYY
   - Default to today

4. generatePartsDescription(lineItems)
   - Format: "• Part Name (qty X)"
   - One line per part

5. generateTrackingLink(trackingNumber)
   - Auto-detect carrier (FedEx, UPS, Canada Post)
   - Return tracking URL

Use the exact formulas from the plan. Handle edge cases (null, zero, division by zero).

Add JSDoc comments for each function.
```

---

### Phase 4: Quote Form

**Cursor Prompt:**
```
@PLAN.md

Build a Quote Detail/Edit form component (src/pages/QuoteDetail.jsx).

Structure:
1. Header section with job #, customer select, PO, engineer, status
2. Collapsible settings section (markups, rates, exchange rate)
3. Line items (use separate component for each)
4. Sticky totals sidebar/footer
5. Action buttons (Save, Mark as Sent, Copy, Delete)

For line items, create src/components/quote/LineItemCard.jsx with sections:
- Materials (alloy, vendor, costs, testing)
- Tooling (description, total cost)
- Labor (hours for programming, setup, first run, production)
- Subcontractors (2 subcontractors with service, cost, shipping)
- Post-processing (heat treat, inspection, packaging, shipping)
- Reference (previous quote note, find similar button)

Show calculated totals in each section and for the line total.

Use Tailwind CSS, make it look professional and clean.
Real-time calculation updates as user types (debounced).
```

---

### Phase 5: Search

**Cursor Prompt:**
```
Add search functionality to the Quotes List page.

Requirements:
- Search input field (debounced 300ms)
- Search across: job_number, customer.name, line_items.part_number
- Filter dropdown for status (All, Draft, Sent, Won, Lost)
- Sort columns (click header to sort)
- Use PocketBase filter syntax

Create a custom hook: useQuoteSearch(searchTerm, statusFilter)
- Returns filtered quotes
- Handles loading state
- Debounces search

Display results in a table with columns:
- Job #, Customer, Parts count, Status badge, Total (CAD), Actions menu
```

---

### Phase 6: Customers & Vendors

**Cursor Prompt:**
```
Build CRUD pages for Customers and Vendors.

Create src/pages/Customers.jsx:
- List view with search
- Table showing: Name, Company, Phone, # of Quotes
- Click row to view/edit (modal or separate page)
- Add new customer button
- Delete with confirmation (warn if has quotes)

Create src/pages/Vendors.jsx:
- Similar to customers
- Add Type filter dropdown (material_supplier, subcontractor, all)
- Show services column for subcontractors

Create reusable components:
- src/components/ui/Modal.jsx (for add/edit forms)
- src/components/ui/ConfirmDialog.jsx (for delete confirmations)

In quote form, integrate customer/vendor selects:
- Searchable dropdown (use Combobox pattern)
- "Add new" button inline (opens modal, saves, auto-selects)
```

---

### Phase 7: Dashboard & Settings

**Cursor Prompt:**
```
Build Dashboard page (src/pages/Dashboard.jsx):

Stats cards (2x2 grid):
1. Total quotes this month (count)
2. Won quotes / win rate % this month
3. Pending quotes (status = sent)
4. Revenue this month (sum of won quote totals)

Recent quotes widget:
- Last 10 quotes, newest first
- Show: Job #, Customer, Status, Total, View button

Active jobs widget:
- Jobs with status = planning or in_progress
- Show: Job #, Customer, Status, Ship date

Build Settings page (src/pages/Settings.jsx):

Sections:
1. Default values (markups, hourly rates)
2. Exchange rate
   - Current rate display
   - Auto-update toggle
   - Manual input
   - "Fetch current rate" button (calls Bank of Canada API)
   - Last updated timestamp
3. Data management (placeholder for future)

Save button updates the settings singleton.

For exchange rate API:
- Endpoint: https://www.bankofcanada.ca/valet/observations/FXUSDCAD/json
- Parse response, extract latest rate
- Handle errors gracefully
```

---

### Phase 8: Jobs Kanban

**Cursor Prompt:**
```
@PLAN.md

Build a Kanban board for job tracking (src/pages/JobsBoard.jsx).

Use @dnd-kit/core for drag and drop.

Layout:
- 4 columns: Planning, In Progress, Done, Cancelled
- Each column shows job cards
- Cards display: Job #, Customer name
- Drag cards between columns to change status

Features:
- Click card to open job detail modal/page
- Add new job button in each column
- Color-code columns (blue, yellow, green, red)

Build Job Detail page (src/pages/JobDetail.jsx):

Fields:
- Status dropdown
- Due date, ship date, completion date
- Tracking status, tracking number(s), tracking link(s)
- Wave invoice #, PO #
- Material lot, source, notes
- Project notes (rich text area)
- Parts description (auto-filled from quote)

Features:
- "View Quote" link
- Auto-generate tracking link when tracking # entered
- Save button
- Delete job button

Auto-create job when quote status → won:
- In Quote Detail, when status changes to "won", call API to create job
- Job inherits: job_number, customer, parts list
- Job starts in "planning" status
- Show success message with "View Job" link
```

---

### Phase 9: Testing

**Cursor Prompt:**
```
Help me test and polish the app.

Create a test checklist covering:
1. Quote creation (all fields, calculations)
2. Quote editing (update existing)
3. Quote copying (new job #, same data)
4. Job creation from won quote
5. Job status updates (drag & drop)
6. Search functionality
7. Customer/vendor CRUD
8. Settings updates
9. Mobile responsiveness
10. Error handling

For each test:
- What to test
- Expected behavior
- How to verify

Also create a list of UI polish tasks:
- Loading states (spinners)
- Error messages (user-friendly)
- Success notifications (toasts)
- Empty states (no data yet)
- Form validation errors
- Confirmation dialogs
```

---

### Phase 10: Deployment

**Cursor Prompt:**
```
Help me deploy to Proxmox.

Steps needed:
1. Create build script (npm run build)
2. Optimize production build (code splitting, minification)
3. Environment variables (.env for API URL)
4. PocketBase systemd service file
5. CloudFlare Tunnel configuration (or Caddy)
6. Data migration script (export from laptop, import to server)
7. Backup strategy

Provide:
- Exact commands to run
- Configuration files needed
- Deployment checklist
```

---

## Folder Structure

```
cnc-quote-tracker/
├── PLAN.md                          # This document
├── README.md                        # Quick start guide
├── .cursorrules                     # Cursor project rules (optional)
│
├── backend/                          # PocketBase
│   ├── pocketbase.exe               # Windows binary
│   ├── pb_data/                     # Auto-created on first run
│   │   ├── data.db                 # SQLite database
│   │   ├── logs.db                 # Logs
│   │   └── backups/                # Automatic backups
│   └── pb_hooks/                    # Optional custom logic
│       └── main.pb.js              # Calculations, validations
│
└── frontend/                         # React app
    ├── public/
    │   └── favicon.ico
    ├── src/
    │   ├── components/
    │   │   ├── ui/                  # Reusable base components
    │   │   │   ├── Button.jsx
    │   │   │   ├── Input.jsx
    │   │   │   ├── Card.jsx
    │   │   │   ├── Select.jsx
    │   │   │   ├── Badge.jsx
    │   │   │   ├── Modal.jsx
    │   │   │   └── ConfirmDialog.jsx
    │   │   │
    │   │   ├── layout/              # Layout components
    │   │   │   ├── Header.jsx
    │   │   │   ├── Sidebar.jsx (optional)
    │   │   │   └── Layout.jsx
    │   │   │
    │   │   └── quote/               # Quote-specific
    │   │       ├── LineItemCard.jsx
    │   │       ├── QuoteTotals.jsx
    │   │       ├── MaterialSection.jsx
    │   │       ├── ToolingSection.jsx
    │   │       ├── LaborSection.jsx
    │   │       └── SubcontractorSection.jsx
    │   │
    │   ├── pages/                   # Page components
    │   │   ├── Dashboard.jsx
    │   │   ├── QuotesList.jsx
    │   │   ├── QuoteDetail.jsx
    │   │   ├── JobsBoard.jsx
    │   │   ├── JobDetail.jsx
    │   │   ├── Customers.jsx
    │   │   ├── Vendors.jsx
    │   │   └── Settings.jsx
    │   │
    │   ├── lib/                     # Utilities
    │   │   ├── pocketbase.js       # PocketBase client
    │   │   ├── api.js              # API wrapper functions
    │   │   ├── calculations.js     # Quote calculations
    │   │   ├── exchangeRate.js     # Bank of Canada API
    │   │   └── utils.js            # Helper functions
    │   │
    │   ├── hooks/                   # Custom React hooks
    │   │   ├── useQuotes.js
    │   │   ├── useJobs.js
    │   │   ├── useCustomers.js
    │   │   ├── useVendors.js
    │   │   └── useSettings.js
    │   │
    │   ├── App.jsx                  # Main app
    │   ├── main.jsx                 # Entry point
    │   └── index.css                # Global styles
    │
    ├── .gitignore
    ├── package.json
    ├── vite.config.js
    ├── tailwind.config.js
    └── postcss.config.js
```

---

## Success Criteria

### Functional Requirements
✅ Create, edit, delete quotes  
✅ Unlimited line items per quote  
✅ All Excel formulas accurate (test against real quotes)  
✅ Auto-create job when quote won  
✅ Kanban board for job tracking  
✅ Customer & vendor management  
✅ Search by job #, customer, part #  
✅ Filter and sort quotes  
✅ Settings page with defaults  
✅ Exchange rate auto-fetch  
✅ Quote → Job workflow seamless  

### User Experience
✅ Faster than Excel for quoting  
✅ Replace Notion entirely  
✅ Clean, professional UI  
✅ Calculations update instantly  
✅ Easy to find old quotes  
✅ Mobile viewable (not full editing)  

### Performance
✅ Page load < 2s  
✅ Calculation updates < 100ms  
✅ Search results < 500ms  
✅ No lag with 100+ quotes  

### Technical
✅ No data loss  
✅ Form validation  
✅ HTTPS in production  
✅ Automatic backups  

---

## Next Steps

1. ✅ **Review this plan** - Make any final changes
2. 🎯 **Start Phase 1** - Set up PocketBase locally
3. 📁 **Save plan to project** - Keep as PLAN.md for Cursor reference
4. 🚀 **Begin development** - Follow phases step by step

---

**Ready to build!** 🚀

Start with Phase 1, use Cursor with the prompts provided, and reference this plan throughout development.

---

*Version 3.0 - Complete with Job Tracking - Cursor Optimized*