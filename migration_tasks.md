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
| t08 | Commit and push `app-platform` branch to GitHub | pending | |
| t09 | Create Spaces key + bucket via `doctl` + `aws` CLI | pending | |
| t10 | Deploy to App Platform (user provides Telegram creds) | pending | |
| t11 | Post-deployment verification (health, web UI, Valkey, Spaces) | pending | |

---

## Completion Log

_Entries added as tasks are completed._
