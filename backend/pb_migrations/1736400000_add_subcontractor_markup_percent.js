// Add subcontractor_markup_percent to quotes (quote-level markup applied to subcontractor costs)
migrate((app) => {
  const collection = app.findCollectionByNameOrId("quotes");
  collection.fields.add(new NumberField({
    name: "subcontractor_markup_percent",
  }));
  app.save(collection);
});
