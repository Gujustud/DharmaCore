/// <reference path="../pb_data/types.d.ts" />
// Optional date: when the shipment was delivered (distinct from ship_date / tracking).
migrate((app) => {
  const jobsCollection = app.findCollectionByNameOrId("jobs")
  if (jobsCollection.fields.find((f) => f.name === "delivered_date")) return
  jobsCollection.fields.add(
    new Field({
      hidden: false,
      max: "",
      min: "",
      name: "delivered_date",
      presentable: false,
      required: false,
      system: false,
      type: "date",
    })
  )
  app.save(jobsCollection)
})
