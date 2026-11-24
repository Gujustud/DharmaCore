/// <reference path="../pb_data/types.d.ts" />
// Ensure quotes.quote_created_date exists and backfill empties from system created.
// Copy-quote / older creates left this blank; Insights was grouping on import day.

migrate((app) => {
  let col = null;
  try {
    col = app.findCollectionByNameOrId("quotes");
  } catch (_) {}
  if (!col) return;

  if (!col.fields.find((f) => f.name === "quote_created_date")) {
    col.fields.add(
      new TextField({
        name: "quote_created_date",
        required: false,
      }),
    );
    app.save(col);
  }

  const batchSize = 200;
  let offset = 0;
  while (true) {
    const rows = app.findRecordsByFilter("quotes", "", "-id", batchSize, offset);
    if (!rows || rows.length === 0) break;

    for (const row of rows) {
      const stamped = (row.get("quote_created_date") || "").toString().trim();
      if (stamped) continue;
      const created = (row.get("created") || "").toString().trim();
      if (!created) continue;
      row.set("quote_created_date", created);
      app.save(row);
    }

    offset += rows.length;
    if (rows.length < batchSize) break;
  }
}, (app) => {
  // Keep backfilled dates on down.
});
