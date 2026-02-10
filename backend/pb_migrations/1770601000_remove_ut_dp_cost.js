/// <reference path="../pb_data/types.d.ts" />
// Remove unused ut_cost (UT) and dp_cost (DP) from quote_line_items
migrate((app) => {
  const collection = app.findCollectionByNameOrId("pbc_2963409648")
  const utField = collection.fields.find((f) => f.name === "ut_cost")
  const dpField = collection.fields.find((f) => f.name === "dp_cost")
  if (utField) collection.fields.removeById(utField.id)
  if (dpField) collection.fields.removeById(dpField.id)
  return app.save(collection)
}, (app) => {
  const collection = app.findCollectionByNameOrId("pbc_2963409648")
  // Rollback: re-add fields (optional; only if you need to reverse)
  const hasUt = collection.fields.find((f) => f.name === "ut_cost")
  const hasDp = collection.fields.find((f) => f.name === "dp_cost")
  if (!hasUt) {
    collection.fields.add(new Field({
      "hidden": false, "max": null, "min": null, "name": "ut_cost",
      "onlyInt": false, "presentable": false, "required": false, "system": false, "type": "number"
    }))
  }
  if (!hasDp) {
    collection.fields.add(new Field({
      "hidden": false, "max": null, "min": null, "name": "dp_cost",
      "onlyInt": false, "presentable": false, "required": false, "system": false, "type": "number"
    }))
  }
  return app.save(collection)
})
