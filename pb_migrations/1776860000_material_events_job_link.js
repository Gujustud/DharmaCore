/// <reference path="../pb_data/types.d.ts" />
// Cut events can link to a real job, record quantity + saw kerf, and keep the
// name of whoever was logged in (History shows the name instead of the email).

migrate((app) => {
  let events = null;
  try {
    events = app.findCollectionByNameOrId("material_events");
  } catch (_) {}
  if (!events) {
    throw new Error(
      "material_events missing — apply 1776820000_material_events_create.js first",
    );
  }

  let jobs = null;
  try {
    jobs = app.findCollectionByNameOrId("jobs");
  } catch (_) {}

  const addField = (field) => {
    if (!events.fields.find((f) => f.name === field.name)) {
      events.fields.add(field);
    }
  };

  if (jobs) {
    addField(
      new RelationField({
        name: "job",
        collectionId: jobs.id,
        maxSelect: 1,
        required: false,
        cascadeDelete: false,
      }),
    );
  }
  addField(new NumberField({ name: "quantity" }));
  addField(new NumberField({ name: "kerf_in" }));
  addField(new TextField({ name: "created_by_name" }));

  app.save(events);
}, (app) => {
  // Keep fields on down — they hold history.
});
