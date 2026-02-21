/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = app.findCollectionByNameOrId('alloys')
  if (!collection) return
  collection.listRule = '@request.auth.id != ""'
  collection.viewRule = '@request.auth.id != ""'
  collection.createRule = '@request.auth.id != ""'
  collection.updateRule = '@request.auth.id != ""'
  collection.deleteRule = '@request.auth.id != ""'
  return app.save(collection)
})
