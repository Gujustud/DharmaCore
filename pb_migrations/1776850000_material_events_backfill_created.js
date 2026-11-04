/// <reference path="../pb_data/types.d.ts" />
// Backfill empty created/updated on material_events rows that were written
// before AutodateFields existed (History showed email but no date).

migrate((app) => {
  let col = null;
  try {
    col = app.findCollectionByNameOrId("material_events");
  } catch (_) {}
  if (!col) return;

  // Ensure autodate fields exist (safe if 177684 already applied).
  let schemaChanged = false;
  if (!col.fields.find((f) => f.name === "created")) {
    col.fields.add(
      new AutodateField({ name: "created", onCreate: true, onUpdate: false }),
    );
    schemaChanged = true;
  }
  if (!col.fields.find((f) => f.name === "updated")) {
    col.fields.add(
      new AutodateField({ name: "updated", onCreate: true, onUpdate: true }),
    );
    schemaChanged = true;
  }
  if (schemaChanged) app.save(col);

  const batchSize = 200;
  let offset = 0;
  while (true) {
    const rows = app.findRecordsByFilter(
      "material_events",
      "",
      "-id",
      batchSize,
      offset,
    );
    if (!rows || rows.length === 0) break;

    for (const row of rows) {
      const created = (row.get("created") || "").toString().trim();
      const updated = (row.get("updated") || "").toString().trim();
      if (created && updated) continue;

      let changed = false;
      if (!created) {
        // Prefer updated; otherwise stamp "now" so History can show a date.
        row.set("created", updated || new Date().toISOString());
        changed = true;
      }
      if (!updated) {
        row.set("updated", (row.get("created") || "").toString());
        changed = true;
      }
      if (changed) app.save(row);
    }

    offset += rows.length;
    if (rows.length < batchSize) break;
  }
}, (app) => {
  // Keep backfilled timestamps on down.
});
