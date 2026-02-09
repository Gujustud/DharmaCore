/// <reference path="../pb_data/types.d.ts" />
// Update part_images thumb size from 200x200f to 300x300f
migrate((app) => {
  // Update jobs collection
  const jobsCollection = app.findCollectionByNameOrId("pbc_2409499253")
  const jobsField = jobsCollection.fields.find((f) => f.name === "part_images")
  if (jobsField) {
    jobsField.thumbs = ["300x300f"]
    app.save(jobsCollection)
  }

  // Update quotes collection
  const quotesCollection = app.findCollectionByNameOrId("quotes")
  const quotesField = quotesCollection.fields.find((f) => f.name === "part_images")
  if (quotesField) {
    quotesField.thumbs = ["300x300f"]
    app.save(quotesCollection)
  }
})
