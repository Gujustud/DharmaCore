# PocketBase – Import collections via migration

The fastest way to create all CNC Quote Tracker collections is to use the included migration.

## Steps

1. **From the project root, go to the backend folder:**
   ```bash
   cd backend
   ```

2. **Start PocketBase** (migrations run automatically on startup):
   ```bash
   pocketbase serve
   ```
   On Windows:
   ```bash
   .\pocketbase.exe serve
   ```

3. On first run, create an admin account when prompted (email + password for `http://127.0.0.1:8090/_/`).

4. The migration `pb_migrations/1736280000_cnc_quote_tracker_collections.js` will run and create:
   - **customers**
   - **vendors**
   - **quotes**
   - **quote_line_items**
   - **jobs**
   - **settings**

5. Open the Admin UI at **http://127.0.0.1:8090/_/** and confirm the collections are there.

## Allow the app to use the API (fix 403 Forbidden)

By default, new collections only allow **superusers** (Admin UI) to read/write. The frontend app needs API access.

1. In Admin UI go to **Settings** (gear icon) → **Collections** (or open each collection from the sidebar).
2. For each collection (**customers**, **vendors**, **quotes**, **quote_line_items**, **jobs**, **settings**):
   - Open the collection → **API rules** tab.
   - Set **List** and **View** to allow access (e.g. leave the rule **empty** to allow all, or use a rule like `@request.auth.id != ""` if you add auth later).
   - Set **Create**, **Update**, **Delete** the same way so the app can create and edit records.
3. **Empty rule** = allow that action for everyone. Use this for a local/trusted app. For production you’d add proper auth and rules.

After saving the rules, reload the app; the 403 errors should stop and “New quote” will load.

## If you already created collections by hand

- If you have a **fresh** PocketBase (no collections yet), the migration will create everything.
- If you **already** have collections with the same names, either:
  - Delete those collections in the Admin UI, then restart PocketBase so the migration runs, or
  - Keep your current schema and skip this migration (e.g. rename or remove the migration file before starting).

## Optional: create the settings record

The **settings** collection is empty after the migration. To get default rates and markups in the app:

1. In Admin UI go to **settings**.
2. Click **New record**.
3. Set for example:
   - `default_shipping_markup_percent`: 30  
   - `default_final_markup_percent`: 0  
   - `exchange_rate_usd_to_cad`: 1.3  
   - `default_hourly_rate_programming`: 350  
   - `default_hourly_rate_setup`: 350  
   - `default_hourly_rate_first_run`: 350  
   - `default_hourly_rate_production`: 269  
   - `exchange_rate_auto_update`: true  

Save the record. The frontend will use it for new quotes.

## Optional: material cost (CAD) field

If you added the **quote_line_items** collection before the `1736350000_add_material_cost_cad.js` migration existed, add the field manually:

1. Open **quote_line_items** in Admin UI.
2. **New field** → Type: Number, Name: `material_cost_cad`, Required: off.
3. Save.

This lets the app store “Actual cost (CAD)” for local purchases alongside “Material cost (USD)”.

**Material shipping cost:** If the `material_shipping_cost` field is missing (migration `1736350001_add_material_shipping_cost.js` not applied), add it manually: **quote_line_items** → New field → Number, name: `material_shipping_cost`, required: off. This is the shipping cost for materials used in the standard cost calculation.

---

## Login (auth)

The app uses PocketBase auth. You need an **Auth** collection and API rules that require a logged-in user.

### 1. Create the auth collection

1. In Admin UI go to **Collections** → **New collection**.
2. Set **Type** to **Auth**.
3. Set **Name** to **users** (the app expects this name).
4. PocketBase adds **email** and **password** (and related fields). Keep the defaults and save.

### 2. Create your first user

1. Open the **users** collection in the sidebar.
2. Click **New record**.
3. Enter an **email** and **password** (and confirm password). Save.
4. Use this email and password to sign in at `/login` in the app.

### 3. Require login for API access

1. For each collection (**customers**, **vendors**, **quotes**, **quote_line_items**, **jobs**, **settings**), open it → **API rules**.
2. Set **List**, **View**, **Create**, **Update**, **Delete** to:  
   `@request.auth.id != ""`  
   so only authenticated users can access data.
3. Save. Unauthenticated requests will get 403 until the user signs in.
