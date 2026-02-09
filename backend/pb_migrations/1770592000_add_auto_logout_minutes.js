// Add auto_logout_minutes to settings (0 = disabled, number = minutes of inactivity before logout)
migrate((app) => {
  const collection = app.findCollectionByNameOrId("settings")
  collection.fields.add(new NumberField({
    name: "auto_logout_minutes",
  }))
  app.save(collection)
})
