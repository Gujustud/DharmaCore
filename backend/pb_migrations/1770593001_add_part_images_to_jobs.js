/// <reference path="../pb_data/types.d.ts" />
// Add part_images file field to jobs (multiple images, max 10)
migrate((app) => {
  const collection = app.findCollectionByNameOrId("pbc_2409499253")
  collection.fields.add(new FileField({
    name: "part_images",
    maxSelect: 10,
    mimeTypes: ["image/png", "image/jpeg", "image/jpg", "image/gif", "image/webp"],
    thumbs: ["300x300f"],
  }))
  app.save(collection)
})
