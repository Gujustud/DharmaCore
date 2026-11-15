# App dates (DharmaCore shop)

Canonical helpers live in **`lib/app_date_field.dart`**. Use them for every new date field.

## Rules

| Concern | Do this |
|--------|---------|
| Editable UI | `AppDateField` (type **or** calendar) |
| What users see | Month/day/year, e.g. `Nov 14, 2026` (`formatAppDate`) |
| Typing | Commits when the field **loses focus** (blur) or on Enter — not Enter-only |
| Accepted typed forms | `11/14/2026`, `Nov 14, 2026`, `2026-11-14`, dashes, etc. (`parseAppDate`) |
| PocketBase / APIs | Store date-only ISO `yyyy-MM-dd` (`formatAppDateIso`) |
| Read-only lists | Prefer `formatAppDate` / `formatAppDateText` (or `DateFormat.yMMMd()`) |

## Do not

- Show editable dates as `yyyy-MM-dd` in the UI
- Use pick-only fields (`readOnly: true` + calendar) for normal shop dates
- Invent a second date widget without extending `AppDateField`

## Quick usage

```dart
import 'app_date_field.dart';

// In a form:
AppDateField(
  controller: _dateController,
  labelText: 'Due date',
  onDateChanged: (d) { /* optional */ },
);

// When saving to PocketBase:
final iso = formatAppDateIso(parseAppDate(_dateController.text)!);
// or keep a DateTime from onDateChanged and formatAppDateIso(d)
```

## Already wired

Purchases, job dates, maintenance completed/next due, packing-slip packed date, wiki table date cells.

Agents also follow `.cursor/rules/app-dates.mdc`.
