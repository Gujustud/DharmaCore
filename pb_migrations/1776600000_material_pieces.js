/// <reference path="../pb_data/types.d.ts" />
// Physical material pieces (shelf stock) + cut/intake event history.
// Catalog (`materials`) stays the SKU; pieces are stickered sticks with remaining length.

migrate((app) => {
  const authRule = '@request.auth.id != ""';

  const materialsCol = app.findCollectionByNameOrId("materials");
  if (!materialsCol) {
    throw new Error("materials missing — apply 1775500000 first");
  }

  let purchaseItemsCol = null;
  try {
    purchaseItemsCol = app.findCollectionByNameOrId("purchase_items");
  } catch (_) {}

  let pieces = null;
  try {
    pieces = app.findCollectionByNameOrId("material_pieces");
  } catch (_) {}

  if (!pieces) {
    pieces = new Collection({
      name: "material_pieces",
      type: "base",
      listRule: authRule,
      viewRule: authRule,
      createRule: authRule,
      updateRule: authRule,
      deleteRule: authRule,
    });
  }

  const addPieceField = (field) => {
    if (!pieces.fields.find((f) => f.name === field.name)) {
      pieces.fields.add(field);
    }
  };

  addPieceField(
    new RelationField({
      name: "material",
      collectionId: materialsCol.id,
      maxSelect: 1,
      required: true,
    }),
  );
  addPieceField(
    new TextField({
      name: "label_code",
      required: true,
    }),
  );
  addPieceField(
    new NumberField({
      name: "length_in",
      required: true,
    }),
  );
  addPieceField(
    new NumberField({
      name: "original_length_in",
    }),
  );
  addPieceField(
    new SelectField({
      name: "status",
      required: true,
      values: ["on_shelf", "depleted", "scrap"],
    }),
  );
  addPieceField(
    new SelectField({
      name: "source",
      required: false,
      values: ["purchase", "legacy", "unknown"],
    }),
  );
  addPieceField(
    new TextField({
      name: "location_note",
    }),
  );
  addPieceField(
    new TextField({
      name: "heat_lot",
    }),
  );
  if (purchaseItemsCol) {
    addPieceField(
      new RelationField({
        name: "purchase_item",
        collectionId: purchaseItemsCol.id,
        maxSelect: 1,
        required: false,
      }),
    );
  }
  addPieceField(
    new TextField({
      name: "notes",
    }),
  );

  app.save(pieces);
  const piecesCol = app.findCollectionByNameOrId("material_pieces");

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
  addEventField(
    new NumberField({
      name: "length_before",
    }),
  );
  addEventField(
    new NumberField({
      name: "length_after",
    }),
  );
  addEventField(
    new NumberField({
      name: "cut_length",
    }),
  );
  addEventField(
    new TextField({
      name: "job_ref",
    }),
  );
  addEventField(
    new TextField({
      name: "notes",
    }),
  );
  addEventField(
    new TextField({
      name: "created_by_email",
    }),
  );

  app.save(events);
}, (app) => {
  try {
    const events = app.findCollectionByNameOrId("material_events");
    app.delete(events);
  } catch (_) {}
  try {
    const pieces = app.findCollectionByNameOrId("material_pieces");
    app.delete(pieces);
  } catch (_) {}
});
