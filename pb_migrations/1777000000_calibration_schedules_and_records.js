/// <reference path="../pb_data/types.d.ts" />
// Inspection tool calibration: schedules (what's due) + records (what was done).
// Linked to inventory/tools — not machines. Any logged-in user can CRUD.

migrate((app) => {
  const authRule = '@request.auth.id != ""';

  let toolsCol = null;
  for (const name of ["inventory", "tools"]) {
    try {
      toolsCol = app.findCollectionByNameOrId(name);
      if (toolsCol) break;
    } catch (_) {}
  }
  if (!toolsCol) {
    throw new Error(
      "inventory/tools collection missing — cannot create calibration relations",
    );
  }

  const addIfMissing = (col, field) => {
    if (!col.fields.find((f) => f.name === field.name)) {
      col.fields.add(field);
    }
  };

  // --- calibration_schedules ---
  let schedules = null;
  try {
    schedules = app.findCollectionByNameOrId("calibration_schedules");
  } catch (_) {}

  if (!schedules) {
    schedules = new Collection({
      name: "calibration_schedules",
      type: "base",
      listRule: authRule,
      viewRule: authRule,
      createRule: authRule,
      updateRule: authRule,
      deleteRule: authRule,
    });
  }

  addIfMissing(
    schedules,
    new TextField({
      name: "name",
      required: true,
    }),
  );
  addIfMissing(
    schedules,
    new RelationField({
      name: "tool",
      collectionId: toolsCol.id,
      maxSelect: 1,
      required: true,
    }),
  );
  addIfMissing(
    schedules,
    new NumberField({
      name: "frequency_value",
      required: true,
    }),
  );
  addIfMissing(
    schedules,
    new SelectField({
      name: "frequency_unit",
      required: true,
      values: ["days", "weeks", "months"],
    }),
  );
  addIfMissing(
    schedules,
    new DateField({
      name: "next_due_date",
      required: true,
    }),
  );
  addIfMissing(
    schedules,
    new DateField({
      name: "last_completed_date",
      required: false,
    }),
  );
  addIfMissing(
    schedules,
    new BoolField({
      name: "active",
      required: false,
    }),
  );
  addIfMissing(
    schedules,
    new NumberField({
      name: "lead_days",
    }),
  );
  addIfMissing(
    schedules,
    new TextField({
      name: "note",
    }),
  );
  addIfMissing(
    schedules,
    new TextField({
      name: "updated_by_email",
    }),
  );

  app.save(schedules);
  const schedulesCol = app.findCollectionByNameOrId("calibration_schedules");

  // --- calibration_records ---
  let records = null;
  try {
    records = app.findCollectionByNameOrId("calibration_records");
  } catch (_) {}

  if (!records) {
    records = new Collection({
      name: "calibration_records",
      type: "base",
      listRule: authRule,
      viewRule: authRule,
      createRule: authRule,
      updateRule: authRule,
      deleteRule: authRule,
    });
  }

  addIfMissing(
    records,
    new TextField({
      name: "name",
      required: true,
    }),
  );
  addIfMissing(
    records,
    new DateField({
      name: "completed_date",
      required: false,
    }),
  );
  addIfMissing(
    records,
    new RelationField({
      name: "tool",
      collectionId: toolsCol.id,
      maxSelect: 1,
      required: true,
    }),
  );
  addIfMissing(
    records,
    new RelationField({
      name: "schedule",
      collectionId: schedulesCol.id,
      maxSelect: 1,
      required: false,
    }),
  );
  addIfMissing(
    records,
    new TextField({
      name: "note",
    }),
  );
  addIfMissing(
    records,
    new TextField({
      name: "updated_by_email",
    }),
  );
  // Optional certificate / report file (Wescan PDF, etc.)
  addIfMissing(
    records,
    new FileField({
      name: "certificate",
      maxSelect: 1,
      maxSize: 20971520,
      mimeTypes: ["application/pdf", "image/jpeg", "image/png", "image/webp"],
    }),
  );

  app.save(records);
}, (app) => {
  // Soft down: leave collections in place (data-preserving).
});
