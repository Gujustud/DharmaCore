/// <reference path="../pb_data/types.d.ts" />
// Undo aggressive length-strip for plate: when form is plate, size_label has
// only cross-section (2 numbers), and there is exactly one distinct purchase
// length_in, restore catalog size as section×length (e.g. 1.5×3 + 3.5 → 1.5×3×3.5).
// Skips materials with 0 or 2+ distinct lengths (merged blanks — leave alone).

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

  function formatInches(v) {
    if (Math.abs(v - Math.round(v)) < 1e-9) return String(Math.round(v));
    let s = v.toFixed(3).replace(/0+$/, "");
    if (s.endsWith(".")) s = s.slice(0, -1);
    return s;
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
      'form = "plate"',
      "-id",
      batchSize,
      offset,
    );
    if (!mats || mats.length === 0) break;

    for (const mat of mats) {
      const sizeRaw = (mat.get("size_label") || "").toString().trim();
      const nums = parseSizeNumbers(sizeRaw);
      // Already a full blank, or not a simple section — leave alone.
      if (nums.length !== 2) continue;

      const mid = mat.id;
      const lengths = [];
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
          const len = existingLength(item);
          if (len == null) continue;
          const exists = lengths.some((x) => Math.abs(x - len) < 0.0005);
          if (!exists) lengths.push(len);
        }
        itemOffset += items.length;
        if (items.length < batchSize) break;
      }

      if (lengths.length !== 1) continue;

      const restored = `${sizeRaw}×${formatInches(lengths[0])}`;
      if (restored === sizeRaw) continue;
      mat.set("size_label", restored);
      app.save(mat);
    }

    offset += mats.length;
    if (mats.length < batchSize) break;
  }
}, (app) => {
  // Keep restored plate sizes on down.
});
