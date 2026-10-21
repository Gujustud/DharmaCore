/// <reference path="../pb_data/types.d.ts" />
// Photos on maintenance completion records (shop floor evidence).

migrate((app) => {
  let records = null;
  try {
    records = app.findCollectionByNameOrId("maintenance_records");
  } catch (_) {}
  if (!records) return;

  if (!records.fields.find((f) => f.name === "photos")) {
    records.fields.add(
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
    app.save(records);
  }
}, (app) => {
  try {
    const records = app.findCollectionByNameOrId("maintenance_records");
    const field = records.fields.find((f) => f.name === "photos");
    if (field) {
      records.fields.removeById(field.id);
      app.save(records);
    }
  } catch (_) {}
});
