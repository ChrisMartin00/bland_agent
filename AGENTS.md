# Horizon Store Bland AI project instructions

You are working on Horizon Store Bland AI, Odoo, and Bland API development.

## Core rules
- Never ask for raw IDs from the user if those IDs should come from prior API responses.
- Treat the latest API response files in `/responses/` as the source of truth.
- Before changing anything, explain what failed in the latest response and why.
- Never claim a customer, product, or quote was found unless the returned ID exists.
- Never claim a quote was created unless `quote_id` exists.
- Never run billing address updates unless `partner_id` exists.
- Never run quote creation unless `partner_id`, `product_id`, and `qty` all exist.
- Prefer editing existing request files over generating one-off shell commands.

## File layout
- Put Bland pathway request bodies in `/requests/bland/`
- Put call test payloads in `/requests/tests/`
- Put raw API responses in `/responses/`
- Put human notes and debugging summaries in `/notes/`

## Required workflow
When changing a pathway, always update these files together:
1. `requests/bland/update_pathway.json`
2. `requests/bland/create_version.json`
3. `requests/bland/publish_version.json`
4. `requests/bland/link_inbound_number.json` if inbound routing matters
5. `requests/tests/test_call.json`

## Output style
- Be direct.
- Keep changes minimal when possible.
- Preserve working IDs and only change what is necessary.
- Summarize the exact bug being fixed before writing files.

## Project-specific behavior
- Alex must collect customer information before placing an order.
- Customer lookup should happen before quote creation.
- Product lookup should happen before quote creation.
- If quote creation fails because of billing or invoice address issues, collect billing address and retry.
- If a pathway starts in the wrong node, fix the start routing before doing anything else.
- Do not use fake fallback branches that sound successful when returned IDs are null.

## Autopilot behavior
When asked to continue development:
1. Read `responses/latest_call.json` first if it exists.
2. Read `responses/latest_pathway.json` if it exists.
3. Update the request files.
4. Leave a short note in `notes/issues.md` describing the failure and the patch.
5. Do not delete old response files.
6. Keep the repo runnable by the loop scripts.
