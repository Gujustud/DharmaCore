// Add labor_note (text) to quote_line_items for notes in the Labour section
migrate((app) => {
  const collection = app.findCollectionByNameOrId("quote_line_items")
  if (collection.fields.find((f) => f.name === "labor_note")) return
  collection.fields.add(new TextField({ name: "labor_note" }))
  app.save(collection)
})
