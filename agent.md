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
1. pathway update request
2. version creation request
3. publish request
4. inbound number link request if needed
5. test call request

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
