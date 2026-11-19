/// <reference path="../pb_data/types.d.ts" />
// Original client filename for cad_files (PocketBase stores a renamed copy).

migrate((app) => {
  let lines = null;
  try {
    lines = app.findCollectionByNameOrId("quote_line_items");
  } catch (_) {}
  if (!lines) return;

  if (!lines.fields.find((f) => f.name === "cad_original_name")) {
    lines.fields.add(
      new TextField({
        name: "cad_original_name",
        required: false,
      }),
    );
    app.save(lines);
  }
}, (app) => {
  try {
    const lines = app.findCollectionByNameOrId("quote_line_items");
    const field = lines.fields.find((f) => f.name === "cad_original_name");
    if (field) {
      lines.fields.removeById(field.id);
      app.save(lines);
    }
  } catch (_) {}
});
