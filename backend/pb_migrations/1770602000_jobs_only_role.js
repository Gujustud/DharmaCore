/// <reference path="../pb_data/types.d.ts" />
// Add optional role to users (full | jobs_only) and restrict quotes/quote_line_items for jobs_only
migrate((app) => {
  const usersCollection = app.findCollectionByNameOrId("users")
  if (usersCollection) {
    const hasRole = usersCollection.fields.find((f) => f.name === "role")
    if (!hasRole) {
      usersCollection.fields.add(new SelectField({
        name: "role",
        required: false,
        values: ["full", "jobs_only"],
      }))
      app.save(usersCollection)
    }
  }

  const quoteRule = '@request.auth.id != "" && @request.auth.role != "jobs_only"'

  const quotesCollection = app.findCollectionByNameOrId("quotes")
  if (quotesCollection) {
    quotesCollection.listRule = quoteRule
    quotesCollection.viewRule = quoteRule
    quotesCollection.createRule = quoteRule
    quotesCollection.updateRule = quoteRule
    quotesCollection.deleteRule = quoteRule
    app.save(quotesCollection)
  }

  const lineItemsCollection = app.findCollectionByNameOrId("quote_line_items")
  if (lineItemsCollection) {
    lineItemsCollection.listRule = quoteRule
    lineItemsCollection.viewRule = quoteRule
    lineItemsCollection.createRule = quoteRule
    lineItemsCollection.updateRule = quoteRule
    lineItemsCollection.deleteRule = quoteRule
    app.save(lineItemsCollection)
  }
}, (app) => {
  const oldRule = '@request.auth.id != ""'

  const quotesCollection = app.findCollectionByNameOrId("quotes")
  if (quotesCollection) {
    quotesCollection.listRule = oldRule
    quotesCollection.viewRule = oldRule
    quotesCollection.createRule = oldRule
    quotesCollection.updateRule = oldRule
    quotesCollection.deleteRule = oldRule
    app.save(quotesCollection)
  }

  const lineItemsCollection = app.findCollectionByNameOrId("quote_line_items")
  if (lineItemsCollection) {
    lineItemsCollection.listRule = oldRule
    lineItemsCollection.viewRule = oldRule
    lineItemsCollection.createRule = oldRule
    lineItemsCollection.updateRule = oldRule
    lineItemsCollection.deleteRule = oldRule
    app.save(lineItemsCollection)
  }
})
