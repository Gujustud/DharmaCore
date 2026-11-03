/// <reference path="../pb_data/types.d.ts" />
// material_events (and pieces) need created/updated AutodateFields.
// Without them, list?sort=-created returns HTTP 400
// "Something went wrong while processing your request."
// Same fix pattern as 1776700000_job_line_items_autodate.js.

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

  ensureAutodates("material_events");
  ensureAutodates("material_pieces");
}, (app) => {
  // Keep autodates on down — removing them breaks list/sort.
});
