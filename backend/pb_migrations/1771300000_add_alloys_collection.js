/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const alloys = new Collection({
    type: "base",
    name: "alloys",
    listRule: null,
    viewRule: null,
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      { name: "name", type: "text", required: true },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_alloys_name ON alloys (name)"],
  })
  app.save(alloys)
})
