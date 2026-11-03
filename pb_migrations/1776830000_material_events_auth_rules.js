/// <reference path="../pb_data/types.d.ts" />
// Force-repair material_events API rules (list/create) for signed-in users.
// Safe if rules are already correct — History was wrongly blaming "missing collection".

migrate((app) => {
  const authRule = '@request.auth.id != ""';

  let events = null;
  try {
    events = app.findCollectionByNameOrId("material_events");
  } catch (_) {}
  if (!events) {
    throw new Error(
      "material_events missing — apply 1776820000_material_events_create.js first",
    );
  }

  events.listRule = authRule;
  events.viewRule = authRule;
  events.createRule = authRule;
  events.updateRule = authRule;
  events.deleteRule = authRule;
  app.save(events);
}, (app) => {
  // Keep rules on down.
});
