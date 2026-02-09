// Add quote_part_price_cad to quote_line_items (optional override for quoted per-part CAD)
migrate((app) => {
  const collection = app.findCollectionByNameOrId("quote_line_items");
  collection.fields.add(new NumberField({
    name: "quote_part_price_cad",
  }));
  app.save(collection);
});
