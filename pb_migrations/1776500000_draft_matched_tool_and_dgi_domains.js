/// <reference path="../pb_data/types.d.ts" />
migrate(
  (app) => {
    // matched_tool on purchase_draft_lines (DGI / tool purchases)
    let lines = null;
    try {
      lines = app.findCollectionByNameOrId("purchase_draft_lines");
    } catch (_) {}
    if (lines) {
      let toolsCol = null;
      for (const name of ["tools", "inventory"]) {
        try {
          toolsCol = app.findCollectionByNameOrId(name);
          if (toolsCol) break;
        } catch (_) {}
      }
      if (toolsCol && !lines.fields.find((f) => f.name === "matched_tool")) {
        lines.fields.add(
          new RelationField({
            name: "matched_tool",
            collectionId: toolsCol.id,
            maxSelect: 1,
            required: false,
          })
        );
        app.save(lines);
      }
    }

    // Ensure DGI vendor has .ca domains + full adapter status when present
    let vendors = [];
    try {
      vendors = app.findRecordsByFilter(
        "email_ingest_vendors",
        'vendor_key = "dgi_supply"',
        "",
        10,
        0
      );
    } catch (_) {
      vendors = [];
    }
    for (const rec of vendors || []) {
      const domains = (rec.get("from_domains") || "").toString();
      let next = domains;
      if (!/dgisupply\.ca/i.test(next)) {
        next = next
          ? `${next.replace(/,\s*$/, "")},dgisupply.ca`
          : "dgisupply.ca,dgisupply.com";
      }
      rec.set("from_domains", next);
      rec.set("default_currency", "CAD");
      rec.set("default_line_kind", "item");
      rec.set("adapter_status", "full");
      // Do not force-enable — shop turns it on in Settings
      app.save(rec);
    }
  },
  (app) => {
    try {
      const lines = app.findCollectionByNameOrId("purchase_draft_lines");
      const field = lines.fields.find((f) => f.name === "matched_tool");
      if (field) {
        lines.fields.removeField(field.id);
        app.save(lines);
      }
    } catch (_) {}
  }
);
