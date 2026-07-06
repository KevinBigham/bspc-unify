# Prod Probe Results

Date: 2026-07-06
Wave: 2 - Prod truth probe
Status: NOT RUN - BLOCKED BEFORE PROD CONNECTION

## Read-Only Verification

`BSPC/ACTIVE/scripts/audit-prod-schema.ts` was re-read before any attempted prod run.

Verified read-only properties:

- The script shells out only to `psql`.
- The SQL fragments are catalog/table reads only: `select`, `to_regclass`, `json_agg`, `row_to_json`, joins, counts, and metadata introspection.
- The script checks migration ledger rows, `public.handle_new_user()` definition metadata, public table RLS flags, storage bucket metadata, auth-user/profile orphan counts, and throwaway-user existence/counts.
- No SQL mutation statements were found in query paths: no `insert`, `update`, `delete`, `alter`, `drop`, `create`, `truncate`, `grant`, `revoke`, `call`, `do`, `copy`, or `execute`.
- Error output is passed through the script redactor for database URLs, JWT-shaped values, email addresses, and UUIDs.
- The report shape is sanitized by design: auth-user samples are short hashes; throwaway/demo checks are counts/booleans only when configured.

## Preflight Findings

The live probe could not be run from this Codex environment.

Initial sanitized preflight result:

- `BSPC_PROD_DATABASE_URL`: absent.
- `BSPC_PROD_PGHOST`: absent.
- `BSPC_PROD_PGUSER`: absent.
- `BSPC_PROD_PGPASSWORD`: absent.
- `BSPC_PROD_THROWAWAY_EMAIL`: absent.
- `BSPC_PROD_THROWAWAY_USER_ID`: absent.
- `psql`: not found on `PATH`; no bundled `psql` binary was found in common local locations.
- Supabase CLI is installed, but `supabase projects list` failed with "Access token not provided."
- `BSPC/ACTIVE/.env.local` contains public app Supabase variables only; no service-role, database, or password-shaped env names were present.

Continuation update:

- Installed Homebrew `libpq` to make `psql` available at `/opt/homebrew/opt/libpq/bin/psql`.
- Verified `psql (PostgreSQL) 18.4`.
- Re-ran the script with `PATH="/opt/homebrew/opt/libpq/bin:$PATH"` and `CONFIRM_PROD_SCHEMA_AUDIT=go`.
- The script stopped before any prod connection with `Missing required env var BSPC_PROD_PGHOST.`
- Prod DB credential env vars and `SUPABASE_ACCESS_TOKEN` remain absent in this shell.

## Prod Access

- Prod read attempted: no.
- Prod write attempted: no.
- Prod mutation possible from this run: no, because no prod connection was opened.

## Classification

No GREEN/YELLOW/RED database classification is available because the probe did not connect to production.

Mission state: STOPPED under the global hard rule for a Wave 2 blocker. Waves 3+ must not build on an unverified production foundation.

## Required Operator Inputs To Resume

- Use the installed `psql` with `PATH="/opt/homebrew/opt/libpq/bin:$PATH"` or expose that directory on `PATH`.
- Provide either `BSPC_PROD_DATABASE_URL` or the individual `BSPC_PROD_PGHOST`, `BSPC_PROD_PGUSER`, and `BSPC_PROD_PGPASSWORD` variables in the same shell.
- Optionally provide `BSPC_PROD_THROWAWAY_EMAIL` or `BSPC_PROD_THROWAWAY_USER_ID` if the throwaway existence check should target the known account.
- Re-run Wave 2 with `CONFIRM_PROD_SCHEMA_AUDIT=go`.
