/// <reference path="../pb_data/types.d.ts" />
// Packing slips: customer ship-to sites, job line items, job ship-to/PS fields,
// app_settings.next_packing_slip_number (starts at 3000).

migrate((app) => {
  const authRule = '@request.auth.id != ""';

  // --- customers collection id (required for ship_tos relation) ---
  let customers = null;
  try {
    customers = app.findCollectionByNameOrId("customers");
  } catch (_) {}
  if (!customers) return;

  // --- customer_ship_tos ---
  let shipTos = null;
  try {
    shipTos = app.findCollectionByNameOrId("customer_ship_tos");
  } catch (_) {}

  if (!shipTos) {
    shipTos = new Collection({
      name: "customer_ship_tos",
      type: "base",
      listRule: authRule,
      viewRule: authRule,
      createRule: authRule,
      updateRule: authRule,
      deleteRule: authRule,
    });
  }

  const addShipField = (field) => {
    if (!shipTos.fields.find((f) => f.name === field.name)) {
      shipTos.fields.add(field);
    }
  };

  addShipField(
    new RelationField({
      name: "customer",
      collectionId: customers.id,
      maxSelect: 1,
      required: true,
    }),
  );
  addShipField(
    new TextField({
      name: "label",
      required: true,
    }),
  );
  addShipField(
    new TextField({
      name: "address",
      required: true,
    }),
  );
  addShipField(
    new TextField({
      name: "attn",
      required: false,
    }),
  );
  addShipField(
    new BoolField({
      name: "is_default",
      required: false,
    }),
  );

  app.save(shipTos);
  shipTos = app.findCollectionByNameOrId("customer_ship_tos");

  // --- jobs ---
  let jobs = null;
  try {
    jobs = app.findCollectionByNameOrId("jobs");
  } catch (_) {}
  if (!jobs) return;

  const addJobField = (field) => {
    if (!jobs.fields.find((f) => f.name === field.name)) {
      jobs.fields.add(field);
    }
  };

  addJobField(
    new RelationField({
      name: "ship_to",
      collectionId: shipTos.id,
      maxSelect: 1,
      required: false,
    }),
  );
  addJobField(
    new TextField({
      name: "ship_to_override",
      required: false,
    }),
  );
  addJobField(
    new TextField({
      name: "packing_slip_number",
      required: false,
    }),
  );

  app.save(jobs);
  jobs = app.findCollectionByNameOrId("jobs");

  // --- quote_line_items (optional link from job lines) ---
  let quoteLines = null;
  try {
    quoteLines = app.findCollectionByNameOrId("quote_line_items");
  } catch (_) {}

  // --- job_line_items ---
  let jobLines = null;
  try {
    jobLines = app.findCollectionByNameOrId("job_line_items");
  } catch (_) {}

  if (!jobLines) {
    jobLines = new Collection({
      name: "job_line_items",
      type: "base",
      listRule: authRule,
      viewRule: authRule,
      createRule: authRule,
      updateRule: authRule,
      deleteRule: authRule,
    });
  }

  const addLineField = (field) => {
    if (!jobLines.fields.find((f) => f.name === field.name)) {
      jobLines.fields.add(field);
    }
  };

  addLineField(
    new RelationField({
      name: "job",
      collectionId: jobs.id,
      maxSelect: 1,
      required: true,
    }),
  );
  addLineField(
    new TextField({
      name: "description",
      required: true,
    }),
  );
  addLineField(
    new NumberField({
      name: "quantity",
      required: true,
    }),
  );
  addLineField(
    new NumberField({
      name: "packed_quantity",
      required: false,
    }),
  );
  addLineField(
    new NumberField({
      name: "sort_order",
      required: false,
    }),
  );
  if (quoteLines) {
    addLineField(
      new RelationField({
        name: "quote_line_item",
        collectionId: quoteLines.id,
        maxSelect: 1,
        required: false,
      }),
    );
  }

  app.save(jobLines);

  // --- app_settings.next_packing_slip_number ---
  let appSettings = null;
  try {
    appSettings = app.findCollectionByNameOrId("app_settings");
  } catch (_) {}
  if (appSettings) {
    if (!appSettings.fields.find((f) => f.name === "next_packing_slip_number")) {
      appSettings.fields.add(
        new NumberField({
          name: "next_packing_slip_number",
          required: false,
        }),
      );
      app.save(appSettings);
    }

    // Seed counter on existing settings rows if unset/zero.
    try {
      const rows = app.findRecordsByFilter("app_settings", "", "", 50, 0);
      for (const row of rows) {
        const n = Number(row.get("next_packing_slip_number") || 0);
        if (!n || n < 3000) {
          row.set("next_packing_slip_number", 3000);
          app.save(row);
        }
      }
    } catch (_) {}
  }
}, (app) => {
  // Best-effort reverse: remove new fields/collections.
  try {
    const appSettings = app.findCollectionByNameOrId("app_settings");
    const f = appSettings.fields.find((x) => x.name === "next_packing_slip_number");
    if (f) {
      appSettings.fields.removeById(f.id);
      app.save(appSettings);
    }
  } catch (_) {}

  try {
    const jobLines = app.findCollectionByNameOrId("job_line_items");
    if (jobLines) app.delete(jobLines);
  } catch (_) {}

  try {
    const jobs = app.findCollectionByNameOrId("jobs");
    for (const name of ["ship_to", "ship_to_override", "packing_slip_number"]) {
      const f = jobs.fields.find((x) => x.name === name);
      if (f) jobs.fields.removeById(f.id);
    }
    app.save(jobs);
  } catch (_) {}

  try {
    const shipTos = app.findCollectionByNameOrId("customer_ship_tos");
    if (shipTos) app.delete(shipTos);
  } catch (_) {}
});
