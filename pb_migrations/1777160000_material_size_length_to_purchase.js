/// <reference path="../pb_data/types.d.ts" />
// One-shot: catalog sizes that still embed bar length (e.g. 3×6×60)
// → write that length onto purchase lines missing length_in, then strip
// the catalog size_label to cross-section only (3×6).
// Safe to re-run: skips materials with <3 size numbers; never overwrites
// an existing positive purchase length_in.

migrate((app) => {
  let materialsCol = null;
  let itemsCol = null;
  try {
    materialsCol = app.findCollectionByNameOrId("materials");
  } catch (_) {}
  try {
    itemsCol = app.findCollectionByNameOrId("purchase_items");
  } catch (_) {}
  if (!materialsCol || !itemsCol) return;

  if (!itemsCol.fields.find((f) => f.name === "length_in")) {
    // 177715 should have added this; bail rather than half-migrate.
    return;
  }

  function parseSizeNumbers(sizeLabel) {
    const s = (sizeLabel || "").toString();
    const matches = s.match(/\d+\.?\d*/g) || [];
    const out = [];
    for (const m of matches) {
      const n = parseFloat(m);
      if (Number.isFinite(n) && n > 0) out.push(n);
    }
    return out;
  }

  function barLengthFromSizeLabel(sizeLabel) {
    const nums = parseSizeNumbers(sizeLabel);
    if (nums.length < 3) return null;
    return nums[nums.length - 1];
  }

  function stripTrailingLengthFromSizeLabel(sizeLabel) {
    const trimmed = (sizeLabel || "").toString().trim();
    if (parseSizeNumbers(trimmed).length < 3) return null;
    const stripped = trimmed
      .replace(/[\s×xX*/\-]+[\d.]+(?:\s*(?:["″]|in(?:ch(?:es)?)?))?\s*$/, "")
      .trim();
    if (!stripped || stripped === trimmed) return null;
    return stripped;
  }

  function existingLength(row) {
    const raw = row.get("length_in");
    if (raw === null || raw === undefined || raw === "") return null;
    const n = typeof raw === "number" ? raw : parseFloat(String(raw));
    if (!Number.isFinite(n) || n <= 0) return null;
    return n;
  }

  const batchSize = 200;
  let offset = 0;
  while (true) {
    const mats = app.findRecordsByFilter(
      "materials",
      "",
      "-id",
      batchSize,
      offset,
    );
    if (!mats || mats.length === 0) break;

    for (const mat of mats) {
      const sizeRaw = (mat.get("size_label") || "").toString();
      const len = barLengthFromSizeLabel(sizeRaw);
      const stripped = stripTrailingLengthFromSizeLabel(sizeRaw);
      if (len == null || len <= 0 || !stripped) continue;

      const mid = mat.id;
      // Purchase lines for this catalog row (material line type only).
      let itemOffset = 0;
      while (true) {
        const items = app.findRecordsByFilter(
          "purchase_items",
          `material = "${mid}" && line_type = "material"`,
          "-id",
          batchSize,
          itemOffset,
        );
        if (!items || items.length === 0) break;

        for (const item of items) {
          if (existingLength(item) != null) continue;
          item.set("length_in", len);
          app.save(item);
        }

        itemOffset += items.length;
        if (items.length < batchSize) break;
      }

      mat.set("size_label", stripped);
      app.save(mat);
    }

    offset += mats.length;
    if (mats.length < batchSize) break;
  }
}, (app) => {
  // Keep backfilled lengths and stripped sizes on down.
});
