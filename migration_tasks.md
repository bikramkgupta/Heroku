# Migration Tasks

Tracking file for the Heroku Userbot -> DigitalOcean App Platform migration.
Updated as each step is completed.

---

## Task List

| ID | Task | Status | Notes |
|----|------|--------|-------|
| t01 | Create `app-platform` branch from master | **done** | Branch created from master |
| t02 | Create `migration-steps.md` (full app analysis + step-by-step guide) | **done** | 7 phases covering analysis through post-deploy verification |
| t03 | Refactor Dockerfile (COPY source, add s3cmd, optimize) | **done** | Replaced git clone with COPY, added s3cmd, entrypoint.sh |
| t04 | Create `entrypoint.sh` (Spaces backup/restore lifecycle) | **done** | Restore on start, backup every 15min, backup on SIGTERM |
| t05 | Create `.do/app.yaml` (App Platform spec with Valkey + Spaces) | **done** | Service + Valkey DB + Spaces env vars |
| t06 | Create `.env.example` (all env vars documented) | **done** | All vars with comments for local vs App Platform |
| t07 | Build and run Docker locally to verify | **done** | Build OK, web UI returns 200 on port 8080 |
| t08 | Commit and push `app-platform` branch to GitHub | **done** | Pushed to origin/app-platform (commit 24cc74b) |
| t09 | Create Spaces key + bucket via `doctl` + `aws` CLI | **done** | Key: heroku-userbot-key, Bucket: heroku-userbot-backup (nyc3) |
| t10 | Deploy to App Platform (user provides Telegram creds) | **done** | App ID: 8f739420-a988-485c-ac34-e0a3f29b7619, Valkey cluster created |
| t11 | Post-deployment verification (health, web UI, Valkey, Spaces) | **done** | ACTIVE, web UI at https://heroku-userbot-3t8hk.ondigitalocean.app returns 200 |

---

## Completion Log

- **t01** (2026-02-07): Created `app-platform` branch from `master`
- **t02** (2026-02-07): Created `migration-steps.md` with 7-phase guide
- **t03** (2026-02-07): Refactored Dockerfile (COPY source, bookworm base, s3cmd)
- **t04** (2026-02-07): Created `entrypoint.sh` (restore/backup/periodic/SIGTERM)
- **t05** (2026-02-07): Created `.do/app.yaml` (service + Valkey + Spaces)
- **t06** (2026-02-07): Created `.env.example`
- **t07** (2026-02-07): Local Docker build + run verified (HTTP 200 on :8080)
- **t08** (2026-02-07): Pushed `app-platform` branch to GitHub
- **t09** (2026-02-07): Created Spaces key `heroku-userbot-key` + bucket `heroku-userbot-backup` (nyc3)
- **t10** (2026-02-07): Deployed to App Platform (app: `8f739420-a988-485c-ac34-e0a3f29b7619`, Valkey cluster: `heroku-userbot-valkey`)
- **t11** (2026-02-07): Verified: ACTIVE deployment, web UI at https://heroku-userbot-3t8hk.ondigitalocean.app returns HTTP 200
