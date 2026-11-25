/// <reference path="../pb_data/types.d.ts" />
// Ordered bar length (inches) on a material purchase line.
// Catalog size stays cross-section; length belongs on the line / pieces.

migrate((app) => {
  let items = null;
  try {
    items = app.findCollectionByNameOrId("purchase_items");
  } catch (_) {}
  if (!items) return;

  if (!items.fields.find((f) => f.name === "length_in")) {
    items.fields.add(
      new NumberField({
        name: "length_in",
        required: false,
        onlyInt: false,
      }),
    );
  }

  app.save(items);
}, (app) => {
  try {
    const items = app.findCollectionByNameOrId("purchase_items");
    const field = items.fields.find((f) => f.name === "length_in");
    if (field) {
      items.fields.removeById(field.id);
      app.save(items);
    }
  } catch (_) {}
});
