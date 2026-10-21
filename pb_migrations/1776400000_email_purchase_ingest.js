/// <reference path="../pb_data/types.d.ts" />
// Gmail purchase ingest: vendors, messages, purchase drafts/lines, material proposals,
// and shop settings fields for enable/poll/sync cursor.

migrate((app) => {
  const authRule = '@request.auth.id != ""';

  let suppliersCol = null;
  try {
    suppliersCol = app.findCollectionByNameOrId("suppliers");
  } catch (_) {}

  let materialsCol = null;
  try {
    materialsCol = app.findCollectionByNameOrId("materials");
  } catch (_) {}

  let purchasesCol = null;
  try {
    purchasesCol = app.findCollectionByNameOrId("purchases");
  } catch (_) {}

  // --- email_ingest_vendors ---
  let vendors = null;
  try {
    vendors = app.findCollectionByNameOrId("email_ingest_vendors");
  } catch (_) {}
  if (!vendors) {
    vendors = new Collection({
      name: "email_ingest_vendors",
      type: "base",
      listRule: authRule,
      viewRule: authRule,
      createRule: authRule,
      updateRule: authRule,
      deleteRule: authRule,
    });
  }
  const addVendorField = (field) => {
    if (!vendors.fields.find((f) => f.name === field.name)) {
      vendors.fields.add(field);
    }
  };
  addVendorField(new TextField({ name: "name", required: true }));
  addVendorField(new TextField({ name: "vendor_key", required: true }));
  if (suppliersCol) {
    addVendorField(
      new RelationField({
        name: "supplier",
        collectionId: suppliersCol.id,
        maxSelect: 1,
        required: false,
      }),
    );
  }
  addVendorField(new TextField({ name: "from_domains", required: true }));
  addVendorField(
    new SelectField({
      name: "default_currency",
      required: false,
      values: ["CAD", "USD"],
    }),
  );
  addVendorField(
    new SelectField({
      name: "default_line_kind",
      required: false,
      values: ["material", "item", "auto"],
    }),
  );
  addVendorField(new BoolField({ name: "enabled" }));
  addVendorField(
    new SelectField({
      name: "adapter_status",
      required: false,
      values: ["full", "stub"],
    }),
  );
  addVendorField(new TextField({ name: "notes" }));
  app.save(vendors);
  const vendorsCol = app.findCollectionByNameOrId("email_ingest_vendors");

  // Seed McMaster + DGI if empty
  let existingVendors = [];
  try {
    existingVendors = app.findRecordsByFilter("email_ingest_vendors", "", "", 1, 0);
  } catch (_) {
    existingVendors = [];
  }
  if (!existingVendors || existingVendors.length === 0) {
    const seed = [
      {
        name: "McMaster-Carr",
        vendor_key: "mcmaster",
        from_domains: "mcmaster.com,mcmastercarr.com",
        default_currency: "USD",
        default_line_kind: "material",
        enabled: true,
        adapter_status: "full",
      },
      {
        name: "DGI Supply",
        vendor_key: "dgi_supply",
        from_domains: "dgisupply.com",
        default_currency: "CAD",
        default_line_kind: "item",
        enabled: false,
        adapter_status: "stub",
        notes: "Parser stub — enable after adapter is filled in.",
      },
    ];
    for (const row of seed) {
      const rec = new Record(vendorsCol);
      for (const [k, v] of Object.entries(row)) {
        rec.set(k, v);
      }
      app.save(rec);
    }
  }

  // --- material_proposals ---
  let proposals = null;
  try {
    proposals = app.findCollectionByNameOrId("material_proposals");
  } catch (_) {}
  if (!proposals) {
    proposals = new Collection({
      name: "material_proposals",
      type: "base",
      listRule: authRule,
      viewRule: authRule,
      createRule: authRule,
      updateRule: authRule,
      deleteRule: authRule,
    });
  }
  const addPropField = (field) => {
    if (!proposals.fields.find((f) => f.name === field.name)) {
      proposals.fields.add(field);
    }
  };
  addPropField(new TextField({ name: "grade", required: true }));
  addPropField(
    new SelectField({
      name: "form",
      required: true,
      values: ["bar", "plate", "sheet", "tube", "hex", "flat", "other"],
    }),
  );
  addPropField(new TextField({ name: "size_label", required: true }));
  addPropField(
    new SelectField({
      name: "unit",
      required: false,
      values: ["ea", "ft", "in", "lb", "kg"],
    }),
  );
  addPropField(new TextField({ name: "notes" }));
  addPropField(new TextField({ name: "source_description" }));
  addPropField(
    new SelectField({
      name: "status",
      required: true,
      values: ["pending", "approved", "rejected"],
    }),
  );
  if (materialsCol) {
    addPropField(
      new RelationField({
        name: "created_material",
        collectionId: materialsCol.id,
        maxSelect: 1,
        required: false,
      }),
    );
  }
  app.save(proposals);
  const proposalsCol = app.findCollectionByNameOrId("material_proposals");

  // --- purchase_drafts ---
  let drafts = null;
  try {
    drafts = app.findCollectionByNameOrId("purchase_drafts");
  } catch (_) {}
  if (!drafts) {
    drafts = new Collection({
      name: "purchase_drafts",
      type: "base",
      listRule: authRule,
      viewRule: authRule,
      createRule: authRule,
      updateRule: authRule,
      deleteRule: authRule,
    });
  }
  const addDraftField = (field) => {
    if (!drafts.fields.find((f) => f.name === field.name)) {
      drafts.fields.add(field);
    }
  };
  addDraftField(new DateField({ name: "purchase_date", required: false }));
  if (suppliersCol) {
    addDraftField(
      new RelationField({
        name: "supplier",
        collectionId: suppliersCol.id,
        maxSelect: 1,
        required: false,
      }),
    );
  }
  addDraftField(
    new RelationField({
      name: "email_ingest_vendor",
      collectionId: vendorsCol.id,
      maxSelect: 1,
      required: false,
    }),
  );
  addDraftField(new TextField({ name: "vendor_key" }));
  addDraftField(new TextField({ name: "order_reference" }));
  addDraftField(new TextField({ name: "invoice" }));
  addDraftField(new TextField({ name: "notes" }));
  addDraftField(new TextField({ name: "tracking" }));
  addDraftField(new NumberField({ name: "total" }));
  addDraftField(
    new SelectField({
      name: "currency",
      required: false,
      values: ["CAD", "USD"],
    }),
  );
  addDraftField(
    new SelectField({
      name: "status",
      required: true,
      values: ["pending", "approved", "rejected"],
    }),
  );
  addDraftField(new TextField({ name: "parse_notes" }));
  if (purchasesCol) {
    addDraftField(
      new RelationField({
        name: "approved_purchase",
        collectionId: purchasesCol.id,
        maxSelect: 1,
        required: false,
      }),
    );
  }
  addDraftField(
    new FileField({
      name: "attachments",
      maxSelect: 12,
      maxSize: 52428800,
      mimeTypes: ["application/pdf", "image/jpeg", "image/png", "image/webp"],
    }),
  );
  app.save(drafts);
  const draftsCol = app.findCollectionByNameOrId("purchase_drafts");

  // --- purchase_draft_lines ---
  let lines = null;
  try {
    lines = app.findCollectionByNameOrId("purchase_draft_lines");
  } catch (_) {}
  if (!lines) {
    lines = new Collection({
      name: "purchase_draft_lines",
      type: "base",
      listRule: authRule,
      viewRule: authRule,
      createRule: authRule,
      updateRule: authRule,
      deleteRule: authRule,
    });
  }
  const addLineField = (field) => {
    if (!lines.fields.find((f) => f.name === field.name)) {
      lines.fields.add(field);
    }
  };
  addLineField(
    new RelationField({
      name: "draft",
      collectionId: draftsCol.id,
      maxSelect: 1,
      required: true,
    }),
  );
  addLineField(
    new SelectField({
      name: "line_type",
      required: true,
      values: ["item", "material", "misc", "tax", "shipping"],
    }),
  );
  addLineField(new TextField({ name: "description" }));
  addLineField(new TextField({ name: "part_number" }));
  addLineField(new NumberField({ name: "quantity" }));
  addLineField(new NumberField({ name: "unit_cost" }));
  addLineField(new TextField({ name: "heat_lot" }));
  addLineField(
    new SelectField({
      name: "match_status",
      required: false,
      values: ["matched", "ambiguous", "propose_new", "none", "n_a"],
    }),
  );
  if (materialsCol) {
    addLineField(
      new RelationField({
        name: "matched_material",
        collectionId: materialsCol.id,
        maxSelect: 1,
        required: false,
      }),
    );
  }
  addLineField(
    new RelationField({
      name: "material_proposal",
      collectionId: proposalsCol.id,
      maxSelect: 1,
      required: false,
    }),
  );
  addLineField(new TextField({ name: "proposed_material_json" }));
  addLineField(new TextField({ name: "candidate_material_ids" }));
  addLineField(new NumberField({ name: "sort_order" }));
  addLineField(
    new FileField({
      name: "mill_certs",
      maxSelect: 8,
      maxSize: 52428800,
      mimeTypes: ["application/pdf", "image/jpeg", "image/png", "image/webp"],
    }),
  );
  app.save(lines);

  // --- email_ingest_messages ---
  let messages = null;
  try {
    messages = app.findCollectionByNameOrId("email_ingest_messages");
  } catch (_) {}
  if (!messages) {
    messages = new Collection({
      name: "email_ingest_messages",
      type: "base",
      listRule: authRule,
      viewRule: authRule,
      createRule: authRule,
      updateRule: authRule,
      deleteRule: authRule,
    });
  }
  const addMsgField = (field) => {
    if (!messages.fields.find((f) => f.name === field.name)) {
      messages.fields.add(field);
    }
  };
  addMsgField(new TextField({ name: "gmail_message_id", required: true }));
  addMsgField(new TextField({ name: "gmail_thread_id" }));
  addMsgField(new TextField({ name: "vendor_key" }));
  addMsgField(
    new RelationField({
      name: "email_ingest_vendor",
      collectionId: vendorsCol.id,
      maxSelect: 1,
      required: false,
    }),
  );
  addMsgField(new TextField({ name: "from_address" }));
  addMsgField(new TextField({ name: "subject" }));
  addMsgField(new DateField({ name: "received_at" }));
  addMsgField(
    new SelectField({
      name: "email_type",
      required: false,
      values: [
        "order_confirmation",
        "shipping",
        "invoice",
        "certificate",
        "other",
      ],
    }),
  );
  addMsgField(
    new SelectField({
      name: "parse_status",
      required: true,
      values: ["parsed", "ignored", "parse_error", "duplicate"],
    }),
  );
  addMsgField(new TextField({ name: "parse_error" }));
  addMsgField(new TextField({ name: "snippet" }));
  addMsgField(
    new RelationField({
      name: "purchase_draft",
      collectionId: draftsCol.id,
      maxSelect: 1,
      required: false,
    }),
  );
  app.save(messages);

  // --- settings fields ---
  let settings = null;
  try {
    settings = app.findCollectionByNameOrId("settings");
  } catch (_) {}
  if (settings) {
    const addSettingsField = (field) => {
      if (!settings.fields.find((f) => f.name === field.name)) {
        settings.fields.add(field);
      }
    };
    addSettingsField(new BoolField({ name: "email_ingest_enabled" }));
    addSettingsField(new NumberField({ name: "email_ingest_poll_minutes" }));
    addSettingsField(new TextField({ name: "email_ingest_last_sync_at" }));
    addSettingsField(new TextField({ name: "email_ingest_last_sync_status" }));
    addSettingsField(new TextField({ name: "email_ingest_last_error" }));
    addSettingsField(new TextField({ name: "email_ingest_history_id" }));
    addSettingsField(new BoolField({ name: "email_ingest_backfill_done" }));
    app.save(settings);
  }
}, (app) => {
  const names = [
    "email_ingest_messages",
    "purchase_draft_lines",
    "purchase_drafts",
    "material_proposals",
    "email_ingest_vendors",
  ];
  for (const name of names) {
    try {
      const col = app.findCollectionByNameOrId(name);
      app.delete(col);
    } catch (_) {}
  }
  try {
    const settings = app.findCollectionByNameOrId("settings");
    const remove = [
      "email_ingest_enabled",
      "email_ingest_poll_minutes",
      "email_ingest_last_sync_at",
      "email_ingest_last_sync_status",
      "email_ingest_last_error",
      "email_ingest_history_id",
      "email_ingest_backfill_done",
    ];
    for (const n of remove) {
      const f = settings.fields.find((x) => x.name === n);
      if (f) settings.fields.removeById(f.id);
    }
    app.save(settings);
  } catch (_) {}
});
