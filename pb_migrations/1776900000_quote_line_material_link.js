/// <reference path="../pb_data/types.d.ts" />
// Optional catalog link + material source on quote lines.
// alloy text stays free-form; material relation is optional.
// material_source: buy | shop_stock | customer_supplied (vendor_supplied kept in sync by the app).

migrate((app) => {
  const authRule = '@request.auth.id != ""';

  let materialsCol = null;
  try {
    materialsCol = app.findCollectionByNameOrId("materials");
  } catch (_) {}
  if (!materialsCol) {
    throw new Error("materials missing — apply 1775500000_materials_and_purchase_certs first");
  }

  let lines = null;
  try {
    lines = app.findCollectionByNameOrId("quote_line_items");
  } catch (_) {}
  if (!lines) {
    throw new Error("quote_line_items missing");
  }

  const addIfMissing = (field) => {
    if (!lines.fields.find((f) => f.name === field.name)) {
      lines.fields.add(field);
    }
  };

  addIfMissing(
    new RelationField({
      name: "material",
      collectionId: materialsCol.id,
      maxSelect: 1,
      required: false,
    }),
  );
  addIfMissing(
    new SelectField({
      name: "material_source",
      required: false,
      values: ["buy", "shop_stock", "customer_supplied"],
    }),
  );

  app.save(lines);
}, (app) => {
  try {
    const lines = app.findCollectionByNameOrId("quote_line_items");
    for (const name of ["material", "material_source"]) {
      const field = lines.fields.find((f) => f.name === name);
      if (field) lines.fields.removeById(field.id);
    }
    app.save(lines);
  } catch (_) {}
});
