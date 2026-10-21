/// <reference path="../pb_data/types.d.ts" />
// Reference photos on recurring maintenance schedules (how-to / what to check).

migrate((app) => {
  let schedules = null;
  try {
    schedules = app.findCollectionByNameOrId("maintenance_schedules");
  } catch (_) {}
  if (!schedules) return;

  if (!schedules.fields.find((f) => f.name === "photos")) {
    schedules.fields.add(
      new FileField({
        name: "photos",
        maxSelect: 8,
        maxSize: 52428800,
        mimeTypes: [
          "image/jpeg",
          "image/png",
          "image/webp",
          "image/gif",
        ],
      }),
    );
    app.save(schedules);
  }
}, (app) => {
  try {
    const schedules = app.findCollectionByNameOrId("maintenance_schedules");
    const field = schedules.fields.find((f) => f.name === "photos");
    if (field) {
      schedules.fields.removeById(field.id);
      app.save(schedules);
    }
  } catch (_) {}
});
