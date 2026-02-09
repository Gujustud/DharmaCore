/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = app.findCollectionByNameOrId("pbc_2963409648")

  // update collection data
  unmarshal({
    "createRule": "\"\" = \"\"",
    "deleteRule": "\"\" = \"\"",
    "listRule": "\"\" = \"\"",
    "updateRule": "\"\" = \"\"",
    "viewRule": "\"\" = \"\""
  }, collection)

  // remove field
  collection.fields.removeById("number1849871573")

  // remove field
  collection.fields.removeById("number2308209258")

  return app.save(collection)
}, (app) => {
  const collection = app.findCollectionByNameOrId("pbc_2963409648")

  // update collection data
  unmarshal({
    "createRule": "",
    "deleteRule": "",
    "listRule": "",
    "updateRule": "",
    "viewRule": ""
  }, collection)

  // add field
  collection.fields.addAt(43, new Field({
    "hidden": false,
    "id": "number1849871573",
    "max": null,
    "min": null,
    "name": "material_cost_cad",
    "onlyInt": false,
    "presentable": false,
    "required": false,
    "system": false,
    "type": "number"
  }))

  // add field
  collection.fields.addAt(44, new Field({
    "hidden": false,
    "id": "number2308209258",
    "max": null,
    "min": null,
    "name": "material_shipping_cost",
    "onlyInt": false,
    "presentable": false,
    "required": false,
    "system": false,
    "type": "number"
  }))

  return app.save(collection)
})
