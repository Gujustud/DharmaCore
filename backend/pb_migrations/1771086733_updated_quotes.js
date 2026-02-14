/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = app.findCollectionByNameOrId("pbc_2527524235")

  // add field
  collection.fields.addAt(7, new Field({
    "hidden": false,
    "id": "date436770664",
    "max": "",
    "min": "",
    "name": "quote_created_date",
    "presentable": false,
    "required": false,
    "system": false,
    "type": "date"
  }))

  return app.save(collection)
}, (app) => {
  const collection = app.findCollectionByNameOrId("pbc_2527524235")

  // remove field
  collection.fields.removeById("date436770664")

  return app.save(collection)
})
