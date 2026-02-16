// Add actual_time_notes (text) to quotes for notes on how long the job actually took (shown only when a job exists)
migrate((app) => {
  const collection = app.findCollectionByNameOrId("quotes")
  if (collection.fields.find((f) => f.name === "actual_time_notes")) return
  collection.fields.add(new TextField({ name: "actual_time_notes" }))
  app.save(collection)
})
