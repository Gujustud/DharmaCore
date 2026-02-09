/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = app.findCollectionByNameOrId("pbc_2527524235")

  // update collection data
  unmarshal({
    "createRule": "\"\" = \"\"",
    "deleteRule": "\"\" = \"\"",
    "listRule": "\"\" = \"\"",
    "updateRule": "\"\" = \"\"",
    "viewRule": "\"\" = \"\""
  }, collection)

  return app.save(collection)
}, (app) => {
  const collection = app.findCollectionByNameOrId("pbc_2527524235")

  // update collection data
  unmarshal({
    "createRule": "",
    "deleteRule": "",
    "listRule": "",
    "updateRule": "",
    "viewRule": ""
  }, collection)

  return app.save(collection)
})
