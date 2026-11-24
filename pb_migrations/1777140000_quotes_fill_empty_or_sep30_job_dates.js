/// <reference path="../pb_data/types.d.ts" />
// 1) Empty quote_created_date only:
//      created on/before 2026-09-30 + valid MMDDYYYY job_number → job date
//      else → system created
// 2) If 177713 already stamped empties from system created (same calendar day,
//    on/before 2026-09-30), rewrite those to the job-number date when valid.
// Never touch quotes after 2026-09-30, and never touch a create date that
// differs from system created (real app stamps).

migrate((app) => {
  let col = null;
  try {
    col = app.findCollectionByNameOrId("quotes");
  } catch (_) {}
  if (!col) return;

  if (!col.fields.find((f) => f.name === "quote_created_date")) {
    col.fields.add(
      new TextField({
        name: "quote_created_date",
        required: false,
      }),
    );
    app.save(col);
  }

  const cutoffDay = "2026-09-30";

  function ymd(iso) {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return "";
    const y = d.getUTCFullYear();
    const m = String(d.getUTCMonth() + 1).padStart(2, "0");
    const day = String(d.getUTCDate()).padStart(2, "0");
    return `${y}-${m}-${day}`;
  }

  function dateFromJobNumber(raw) {
    const s = (raw || "").toString().trim();
    if (!/^\d{8}$/.test(s)) return "";
    const mm = parseInt(s.slice(0, 2), 10);
    const dd = parseInt(s.slice(2, 4), 10);
    const yyyy = parseInt(s.slice(4, 8), 10);
    if (yyyy < 2000 || yyyy > 2100) return "";
    if (mm < 1 || mm > 12) return "";
    if (dd < 1 || dd > 31) return "";
    const dt = new Date(Date.UTC(yyyy, mm - 1, dd, 12, 0, 0));
    if (
      dt.getUTCFullYear() !== yyyy ||
      dt.getUTCMonth() !== mm - 1 ||
      dt.getUTCDate() !== dd
    ) {
      return "";
    }
    return dt.toISOString();
  }

  const batchSize = 200;
  let offset = 0;
  while (true) {
    const rows = app.findRecordsByFilter("quotes", "", "-id", batchSize, offset);
    if (!rows || rows.length === 0) break;

    for (const row of rows) {
      const stamped = (row.get("quote_created_date") || "").toString().trim();
      const createdRaw = (row.get("created") || "").toString().trim();
      const createdDay = createdRaw ? ymd(createdRaw) : "";
      const fromJob = dateFromJobNumber(row.get("job_number"));

      // --- empty field ---
      if (!stamped) {
        let value = "";
        if (createdDay && createdDay <= cutoffDay && fromJob) {
          value = fromJob;
        } else if (createdRaw) {
          value = createdRaw;
        }
        if (!value) continue;
        row.set("quote_created_date", value);
        app.save(row);
        continue;
      }

      // --- naive Sep-30-or-earlier backfill only (stamped day == created day) ---
      if (!createdDay || createdDay > cutoffDay) continue;
      const stampedDay = ymd(stamped);
      if (!stampedDay || stampedDay !== createdDay) continue;
      if (!fromJob) continue;
      if (ymd(fromJob) === stampedDay) continue;

      row.set("quote_created_date", fromJob);
      app.save(row);
    }

    offset += rows.length;
    if (rows.length < batchSize) break;
  }
}, (app) => {
  // Keep repaired dates on down.
});
