/// <reference path="../pb_data/types.d.ts" />
// Single CAD file per quote line (STEP / Parasolid). Empty mimeTypes: browsers
// often send application/octet-stream for .step / .x_t.

migrate((app) => {
  let lines = null;
  try {
    lines = app.findCollectionByNameOrId("quote_line_items");
  } catch (_) {}
  if (!lines) return;

  if (!lines.fields.find((f) => f.name === "cad_files")) {
    lines.fields.add(
      new FileField({
        name: "cad_files",
        maxSelect: 1,
        maxSize: 52428800,
        mimeTypes: [],
      }),
    );
  }

  if (!lines.fields.find((f) => f.name === "cad_file_bytes")) {
    lines.fields.add(
      new NumberField({
        name: "cad_file_bytes",
        required: false,
        onlyInt: true,
      }),
    );
  }

  app.save(lines);
}, (app) => {
  try {
    const lines = app.findCollectionByNameOrId("quote_line_items");
    for (const name of ["cad_files", "cad_file_bytes"]) {
      const field = lines.fields.find((f) => f.name === name);
      if (field) lines.fields.removeById(field.id);
    }
    app.save(lines);
  } catch (_) {}
});
