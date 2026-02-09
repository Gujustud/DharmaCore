// Add material_cost_cad to quote_line_items (optional - for local CAD purchases)
migrate((app) => {
  const collection = app.findCollectionByNameOrId("quote_line_items");
  collection.fields.add(new NumberField({
    name: "material_cost_cad",
  }));
  app.save(collection);
});
