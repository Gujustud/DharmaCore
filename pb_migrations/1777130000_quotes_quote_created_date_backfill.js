/// <reference path="../pb_data/types.d.ts" />
// Ensure quotes.quote_created_date exists.
// Fill ONLY when empty (never overwrite a real stamp):
//   - system created on/before 2026-09-30 → prefer job_number MMDDYYYY if valid
//   - otherwise → system created
// Create/Copy in the app still stamps "now" going forward.

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

  /** End of migration/import cutoff (America/Vancouver-ish; use UTC day boundary). */
  const cutoff = new Date("2026-09-30T23:59:59.999Z");

  /**
   * Parse shop job numbers like 07102026 → 2026-07-10.
   * Returns ISO date string at noon UTC, or "".
   */
  function dateFromJobNumber(raw) {
    const s = (raw || "").toString().trim();
    if (!/^\d{8}$/.test(s)) return "";
    const mm = parseInt(s.slice(0, 2), 10);
    const dd = parseInt(s.slice(2, 4), 10);
    const yyyy = parseInt(s.slice(4, 8), 10);
    if (yyyy < 2000 || yyyy > 2100) return "";
    if (mm < 1 || mm > 12) return "";
    if (dd < 1 || dd > 31) return "";
    const dt = new Date(Date.UTC(yyyy, mm - 1, dd, 12, 0, 0));
    if (
      dt.getUTCFullYear() !== yyyy ||
      dt.getUTCMonth() !== mm - 1 ||
      dt.getUTCDate() !== dd
    ) {
      return "";
    }
    return dt.toISOString();
  }

  const batchSize = 200;
  let offset = 0;
  while (true) {
    const rows = app.findRecordsByFilter("quotes", "", "-id", batchSize, offset);
    if (!rows || rows.length === 0) break;

    for (const row of rows) {
      const stamped = (row.get("quote_created_date") || "").toString().trim();
      // Never modify quotes that already have a create date.
      if (stamped) continue;

      const createdRaw = (row.get("created") || "").toString().trim();
      const created = createdRaw ? new Date(createdRaw) : null;
      const createdOk = created && !Number.isNaN(created.getTime());

      let value = "";
      if (createdOk && created.getTime() <= cutoff.getTime()) {
        value = dateFromJobNumber(row.get("job_number"));
      }
      if (!value && createdRaw) value = createdRaw;
      if (!value) continue;

      row.set("quote_created_date", value);
      app.save(row);
    }

    offset += rows.length;
    if (rows.length < batchSize) break;
  }
}, (app) => {
  // Keep backfilled dates on down.
});
