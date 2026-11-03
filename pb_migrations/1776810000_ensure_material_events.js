/// <reference path="../pb_data/types.d.ts" />
// Ensure material_events exists even if 1776800000 created pieces then stopped.
// Safe to apply on CT 105 when History shows "Piece activity unavailable".

migrate((app) => {
  const authRule = '@request.auth.id != ""';

  let piecesCol = null;
  try {
    piecesCol = app.findCollectionByNameOrId("material_pieces");
  } catch (_) {}
  if (!piecesCol) {
    throw new Error("material_pieces missing — apply 1776800000_material_pieces.js first");
  }

  let events = null;
  try {
    events = app.findCollectionByNameOrId("material_events");
  } catch (_) {}

  if (!events) {
    events = new Collection({
      name: "material_events",
      type: "base",
      listRule: authRule,
      viewRule: authRule,
      createRule: authRule,
      updateRule: authRule,
      deleteRule: authRule,
    });
  }

  const addEventField = (field) => {
    if (!events.fields.find((f) => f.name === field.name)) {
      events.fields.add(field);
    }
  };

  addEventField(
    new RelationField({
      name: "piece",
      collectionId: piecesCol.id,
      maxSelect: 1,
      required: true,
    }),
  );
  addEventField(
    new SelectField({
      name: "event_type",
      required: true,
      values: ["intake", "cut", "scrap", "adjust", "reprint"],
    }),
  );
  addEventField(new NumberField({ name: "length_before" }));
  addEventField(new NumberField({ name: "length_after" }));
  addEventField(new NumberField({ name: "cut_length" }));
  addEventField(new TextField({ name: "job_ref" }));
  addEventField(new TextField({ name: "notes" }));
  addEventField(new TextField({ name: "created_by_email" }));
  addEventField(
    new AutodateField({ name: "created", onCreate: true, onUpdate: false }),
  );
  addEventField(
    new AutodateField({ name: "updated", onCreate: true, onUpdate: true }),
  );

  app.save(events);
}, (app) => {
  // Do not delete material_events on down — may already hold live history.
});
