/// <reference path="../pb_data/types.d.ts" />
// Add material_source_vendor relation to jobs (links to vendors, like quote line item material_vendor)
migrate((app) => {
  const jobsCollection = app.findCollectionByNameOrId("jobs")
  const vendorsId = app.findCollectionByNameOrId("vendors").id
  jobsCollection.fields.add(new RelationField({
    name: "material_source_vendor",
    collectionId: vendorsId,
    maxSelect: 1,
    cascadeDelete: false,
  }))
  app.save(jobsCollection)
})
