# Horizon Store Bland AI Autopilot Starter Kit

This repo is the control center for developing and testing your Bland agent.

## What this does

- stores the active Bland pathway JSON and test payloads
- stores the latest API responses from Bland
- gives Codex clear project rules via `AGENTS.md`
- runs a repeatable dev loop with shell or PowerShell scripts
- lets you walk away while your machine keeps iterating

## The loop

1. update pathway in `requests/bland/update_pathway.json`
2. create a new version
3. publish that version
4. optionally link the pathway to the inbound number
5. place a test call
6. save the test result to `responses/latest_call.json`
7. ask Codex to inspect the latest result and patch the request files
8. repeat until success or stop conditions

## First setup

1. Copy `.env.example` to `.env`
2. Fill in your API key and IDs
3. Put your current working pathway JSON into `requests/bland/update_pathway.json`
4. Put your latest failed call response into `responses/latest_call.json`
5. Run `scripts/doctor.sh` or `scripts/doctor.ps1`
6. Start with one manual cycle before using loop mode

## Required tools

- `codex` CLI on your PATH
- `curl` on your PATH
- `jq` on your PATH for bash mode
- PowerShell 7+ if using Windows scripts

## Environment values

See `.env.example`.

## Recommended first Codex command

Run this from the repo root:

```text
codex -C . "Read AGENTS.md and responses/latest_call.json. Explain the exact failure, then update the request files under requests/bland and requests/tests for the next safe iteration. Do not ask for raw IDs if they should come from prior responses."
```

## Manual run order

### Bash

```bash
./scripts/doctor.sh
./scripts/run_cycle.sh once
```

### PowerShell

```powershell
./scripts/doctor.ps1
./scripts/run_cycle.ps1 -Mode once
```

## Full loop mode

### Bash

```bash
./scripts/run_cycle.sh loop
```

### PowerShell

```powershell
./scripts/run_cycle.ps1 -Mode loop
```

## What counts as success

The latest call should prove all of these:

- pathway starts at the correct greeting or lookup node
- no node asks the caller for raw `partner_id` or `product_id`
- no quote is attempted without `partner_id`, `product_id`, and `qty`
- no billing update is attempted without `partner_id`
- no fake success language is used when IDs are null

## Stop conditions

The loop stops when any of these happen:

- `notes/STOP` exists
- max iteration count is reached
- a script exits non-zero
- the latest response matches any failure guard in `notes/failure_patterns.md`

## Safe working style

- edit request files, not random one-off commands
- save every meaningful API response into `responses/`
- let Codex work from the files, not from memory
