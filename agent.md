Project: Horizon Store Bland AI / Odoo / Bland API development

Rules:
- Never ask me for raw IDs if they should already come from previous API responses.
- Prefer editing existing request files over making one-off terminal commands.
- Keep all Bland API requests in /requests/bland/
- Keep all Odoo API requests in /requests/odoo/
- Keep call test payloads in /requests/tests/
- When changing a pathway, update:
  1. pathway JSON
  2. version request
  3. publish request
  4. test call request
- Always explain what broke from the latest API response before changing files.
- Never claim a quote/customer/product was found unless the returned ID exists.
