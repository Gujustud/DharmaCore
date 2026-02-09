// Add material_shipping_cost to quote_line_items (shipping cost for materials)
migrate((app) => {
  const collection = app.findCollectionByNameOrId("quote_line_items");
  collection.fields.add(new NumberField({
    name: "material_shipping_cost",
  }));
  app.save(collection);
});
