# Failure patterns that should stop unattended looping

- repetitive publish failures with no pathway version increment
- inbound number linked to the wrong pathway after update
- pathway starts at Create Quote instead of Greeting or Customer Lookup
- quote creation runs with null partner_id
- billing update runs with null partner_id
- same exact failure happens 3 cycles in a row
