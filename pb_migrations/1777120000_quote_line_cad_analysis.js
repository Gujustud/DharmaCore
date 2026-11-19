/// <reference path="../pb_data/types.d.ts" />
// JSON blob for Toolpath Phase B analysis (bbox, features, status).

migrate((app) => {
  let lines = null;
  try {
    lines = app.findCollectionByNameOrId("quote_line_items");
  } catch (_) {}
  if (!lines) return;

  if (!lines.fields.find((f) => f.name === "cad_analysis")) {
    lines.fields.add(
      new TextField({
        name: "cad_analysis",
        required: false,
      }),
    );
    app.save(lines);
  }
}, (app) => {
  try {
    const lines = app.findCollectionByNameOrId("quote_line_items");
    const field = lines.fields.find((f) => f.name === "cad_analysis");
    if (field) {
      lines.fields.removeById(field.id);
      app.save(lines);
    }
  } catch (_) {}
});
