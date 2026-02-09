/// <reference path="../pb_data/types.d.ts" />
// Fix part_images mimeTypes - remove wildcard restriction (empty array = allow all)
migrate((app) => {
  // Update jobs collection
  const jobsCollection = app.findCollectionByNameOrId("pbc_2409499253")
  const jobsField = jobsCollection.fields.find((f) => f.name === "part_images")
  if (jobsField) {
    jobsField.mimeTypes = [] // Empty array = no mime type restriction
    app.save(jobsCollection)
  }

  // Update quotes collection
  const quotesCollection = app.findCollectionByNameOrId("quotes")
  const quotesField = quotesCollection.fields.find((f) => f.name === "part_images")
  if (quotesField) {
    quotesField.mimeTypes = [] // Empty array = no mime type restriction
    app.save(quotesCollection)
  }
})
