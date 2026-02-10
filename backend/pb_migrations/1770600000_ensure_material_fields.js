/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = app.findCollectionByNameOrId("pbc_2963409648")
  
  // Check if fields exist using find()
  const materialCostCadField = collection.fields.find((f) => f.name === "material_cost_cad")
  const materialShippingCostField = collection.fields.find((f) => f.name === "material_shipping_cost")
  
  if (!materialCostCadField) {
    collection.fields.add(new Field({
      "hidden": false,
      "max": null,
      "min": null,
      "name": "material_cost_cad",
      "onlyInt": false,
      "presentable": false,
      "required": false,
      "system": false,
      "type": "number"
    }))
  }
  
  if (!materialShippingCostField) {
    collection.fields.add(new Field({
      "hidden": false,
      "max": null,
      "min": null,
      "name": "material_shipping_cost",
      "onlyInt": false,
      "presentable": false,
      "required": false,
      "system": false,
      "type": "number"
    }))
  }
  
  return app.save(collection)
}, (app) => {
  // Rollback: remove fields if they exist
  const collection = app.findCollectionByNameOrId("pbc_2963409648")
  const materialCostCadField = collection.fields.find((f) => f.name === "material_cost_cad")
  const materialShippingCostField = collection.fields.find((f) => f.name === "material_shipping_cost")
  
  if (materialCostCadField) {
    collection.fields.removeById(materialCostCadField.id)
  }
  if (materialShippingCostField) {
    collection.fields.removeById(materialShippingCostField.id)
  }
  
  return app.save(collection)
})
