// CNC Quote Tracker - Import all collections in one migration.
// Run: from backend folder, start PocketBase (./pocketbase serve or pocketbase.exe serve).
// Migrations run automatically on serve.

migrate((app) => {
  // 1. customers
  const customers = new Collection({
    type: "base",
    name: "customers",
    listRule: null,
    viewRule: null,
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      { name: "name", type: "text", required: true },
      { name: "company", type: "text" },
      { name: "email", type: "email" },
      { name: "phone", type: "text" },
      { name: "address", type: "text" },
      { name: "notes", type: "text" },
    ],
    indexes: ["CREATE INDEX idx_customers_name ON customers (name)"],
  });
  app.save(customers);

  const customersId = app.findCollectionByNameOrId("customers").id;

  // 2. vendors
  const vendors = new Collection({
    type: "base",
    name: "vendors",
    listRule: null,
    viewRule: null,
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      { name: "name", type: "text", required: true },
      {
        name: "vendor_type",
        type: "select",
        required: true,
        values: ["material_supplier", "subcontractor", "other"],
      },
      { name: "contact_person", type: "text" },
      { name: "email", type: "email" },
      { name: "phone", type: "text" },
      { name: "services", type: "text" },
      { name: "notes", type: "text" },
    ],
    indexes: ["CREATE INDEX idx_vendors_name ON vendors (name)"],
  });
  app.save(vendors);

  const vendorsId = app.findCollectionByNameOrId("vendors").id;

  // 3. quotes
  const quotes = new Collection({
    type: "base",
    name: "quotes",
    listRule: null,
    viewRule: null,
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      { name: "job_number", type: "text", required: true },
      { name: "wave_quote_number", type: "text" },
      {
        name: "customer",
        type: "relation",
        collectionId: customersId,
        maxSelect: 1,
        cascadeDelete: false,
      },
      { name: "customer_name", type: "text" },
      { name: "po_number", type: "text" },
      { name: "engineer", type: "text", required: true },
      {
        name: "status",
        type: "select",
        values: ["draft", "sent", "won", "lost"],
        required: true,
      },
      { name: "shipping_markup_percent", type: "number" },
      { name: "final_markup_percent", type: "number" },
      { name: "exchange_rate_usd_to_cad", type: "number", required: true },
      { name: "hourly_rate_programming", type: "number", required: true },
      { name: "hourly_rate_setup", type: "number", required: true },
      { name: "hourly_rate_first_run", type: "number", required: true },
      { name: "hourly_rate_production", type: "number", required: true },
      { name: "materials_total", type: "number" },
      { name: "tooling_total", type: "number" },
      { name: "labor_total", type: "number" },
      { name: "subcontractor_total", type: "number" },
      { name: "subtotal", type: "number" },
      { name: "final_total_cad", type: "number" },
      { name: "final_total_usd", type: "number" },
      { name: "notes", type: "text" },
    ],
    indexes: [
      "CREATE UNIQUE INDEX idx_quotes_job_number ON quotes (job_number)",
      "CREATE INDEX idx_quotes_wave_quote_number ON quotes (wave_quote_number)",
      "CREATE INDEX idx_quotes_status ON quotes (status)",
      "CREATE INDEX idx_quotes_customer ON quotes (customer)",
    ],
  });
  app.save(quotes);

  const quotesId = app.findCollectionByNameOrId("quotes").id;

  // 4. quote_line_items
  const quoteLineItems = new Collection({
    type: "base",
    name: "quote_line_items",
    listRule: null,
    viewRule: null,
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      {
        name: "quote",
        type: "relation",
        collectionId: quotesId,
        maxSelect: 1,
        cascadeDelete: true,
        required: true,
      },
      { name: "line_number", type: "number", required: true },
      { name: "part_number", type: "text" },
      { name: "part_quantity", type: "number", required: true },
      { name: "alloy", type: "text" },
      { name: "stock_size_per_part", type: "text" },
      { name: "ordered_length", type: "text" },
      { name: "pieces", type: "number" },
      { name: "material_note", type: "text" },
      {
        name: "material_vendor",
        type: "relation",
        collectionId: vendorsId,
        maxSelect: 1,
        cascadeDelete: false,
      },
      { name: "vendor_supplied", type: "text" },
      { name: "usd_cost", type: "number" },
      { name: "testing_cost", type: "number" },
      { name: "ut_cost", type: "number" },
      { name: "dp_cost", type: "number" },
      { name: "tooling_total_cost", type: "number" },
      { name: "tooling_description", type: "text" },
      { name: "programming_hours", type: "number" },
      { name: "setup_hours", type: "number" },
      { name: "first_run_hours", type: "number" },
      { name: "production_hours_total", type: "number" },
      {
        name: "subcontractor_1",
        type: "relation",
        collectionId: vendorsId,
        maxSelect: 1,
        cascadeDelete: false,
      },
      { name: "subcontractor_1_service", type: "text" },
      { name: "subcontractor_1_cost", type: "number" },
      { name: "subcontractor_1_shipping", type: "number" },
      {
        name: "subcontractor_2",
        type: "relation",
        collectionId: vendorsId,
        maxSelect: 1,
        cascadeDelete: false,
      },
      { name: "subcontractor_2_service", type: "text" },
      { name: "subcontractor_2_cost", type: "number" },
      { name: "subcontractor_2_shipping", type: "number" },
      { name: "heat_treat_cost", type: "number" },
      { name: "inspection_cost", type: "number" },
      { name: "packaging_cost", type: "number" },
      { name: "shipping_cost", type: "number" },
      { name: "previous_quote_reference", type: "text" },
      { name: "material_actual_cost_cad", type: "number" },
      { name: "material_with_markup", type: "number" },
      { name: "labor_cost", type: "number" },
      { name: "subcontractor_1_total", type: "number" },
      { name: "subcontractor_2_total", type: "number" },
      { name: "line_total_cad", type: "number" },
      { name: "price_per_part_cad", type: "number" },
      { name: "price_per_part_usd", type: "number" },
    ],
    indexes: [
      "CREATE INDEX idx_quote_line_items_quote ON quote_line_items (quote)",
      "CREATE INDEX idx_quote_line_items_part_number ON quote_line_items (part_number)",
    ],
  });
  app.save(quoteLineItems);

  // 5. jobs
  const jobs = new Collection({
    type: "base",
    name: "jobs",
    listRule: null,
    viewRule: null,
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      {
        name: "quote",
        type: "relation",
        collectionId: quotesId,
        maxSelect: 1,
        cascadeDelete: false,
        required: true,
      },
      { name: "job_number", type: "text", required: true },
      {
        name: "customer",
        type: "relation",
        collectionId: customersId,
        maxSelect: 1,
        cascadeDelete: false,
      },
      { name: "customer_name", type: "text" },
      { name: "parts_description", type: "text" },
      {
        name: "status",
        type: "select",
        values: ["planning", "in_progress", "done", "cancelled"],
        required: true,
      },
      { name: "due_date", type: "date" },
      { name: "completion_date", type: "date" },
      { name: "ship_date", type: "date" },
      {
        name: "tracking_status",
        type: "select",
        values: ["not_shipped", "in_transit", "delivered"],
      },
      { name: "tracking_number_1", type: "text" },
      { name: "tracking_link_1", type: "url" },
      { name: "tracking_number_2", type: "text" },
      { name: "tracking_link_2", type: "url" },
      { name: "wave_invoice_number", type: "text" },
      { name: "po_number", type: "text" },
      { name: "material_lot", type: "text" },
      { name: "material_source", type: "text" },
      { name: "material_notes", type: "text" },
      { name: "project_notes", type: "text" },
      { name: "notes", type: "text" },
    ],
    indexes: [
      "CREATE UNIQUE INDEX idx_jobs_quote ON jobs (quote)",
      "CREATE INDEX idx_jobs_job_number ON jobs (job_number)",
      "CREATE INDEX idx_jobs_status ON jobs (status)",
    ],
  });
  app.save(jobs);

  // 6. settings (singleton - one record)
  const settings = new Collection({
    type: "base",
    name: "settings",
    listRule: null,
    viewRule: null,
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      { name: "default_shipping_markup_percent", type: "number" },
      { name: "default_final_markup_percent", type: "number" },
      { name: "default_hourly_rate_programming", type: "number" },
      { name: "default_hourly_rate_setup", type: "number" },
      { name: "default_hourly_rate_first_run", type: "number" },
      { name: "default_hourly_rate_production", type: "number" },
      { name: "exchange_rate_usd_to_cad", type: "number" },
      { name: "exchange_rate_auto_update", type: "bool" },
      { name: "exchange_rate_last_updated", type: "date" },
    ],
    indexes: [],
  });
  app.save(settings);
});
