/// <reference path="../pb_data/types.d.ts" />
// Ensure job_line_items / customer_ship_tos have created+updated so list
// queries can sort by created (PB returns 400 without these fields).

migrate((app) => {
  const ensureAutodates = (name) => {
    let col = null;
    try {
      col = app.findCollectionByNameOrId(name);
    } catch (_) {
      return;
    }
    let changed = false;
    if (!col.fields.find((f) => f.name === "created")) {
      col.fields.add(
        new AutodateField({
          name: "created",
          onCreate: true,
          onUpdate: false,
        }),
      );
      changed = true;
    }
    if (!col.fields.find((f) => f.name === "updated")) {
      col.fields.add(
        new AutodateField({
          name: "updated",
          onCreate: true,
          onUpdate: true,
        }),
      );
      changed = true;
    }
    if (changed) app.save(col);
  };

  ensureAutodates("job_line_items");
  ensureAutodates("customer_ship_tos");
}, (app) => {
  // Keep autodates on down — removing them breaks existing rows.
});
