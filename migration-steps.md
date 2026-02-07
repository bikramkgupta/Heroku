# Migration Steps: Heroku Userbot to DigitalOcean App Platform

This document describes the complete migration of the Heroku Userbot from its
current Docker-based deployment to DigitalOcean App Platform.

---

## Table of Contents

- [Application Overview](#application-overview)
- [Phase 0: Understand the Current Setup](#phase-0-understand-the-current-setup)
- [Phase 1: Refactor the Dockerfile](#phase-1-refactor-the-dockerfile)
- [Phase 2: Add Valkey (Redis) for Persistence](#phase-2-add-valkey-redis-for-persistence)
- [Phase 3: Add DigitalOcean Spaces Backup](#phase-3-add-digitalocean-spaces-backup)
- [Phase 4: Create App Platform Specification](#phase-4-create-app-platform-specification)
- [Phase 5: Local Verification](#phase-5-local-verification)
- [Phase 6: Push to GitHub and Deploy](#phase-6-push-to-github-and-deploy)
- [Phase 7: Post-Migration Verification](#phase-7-post-migration-verification)
- [Rollback Plan](#rollback-plan)

---

## Application Overview

### What is Heroku Userbot?

A Telegram userbot framework (fork of Hikka/FTG) that automates Telegram user accounts.
Despite its name, it has **zero Heroku platform dependencies** -- no Procfile, no app.json,
no heroku.yml. It is purely Docker-based.

### Core Components

| Component | Description |
|-----------|-------------|
| **Python app** | Entry point: `python -m heroku` (Python 3.10) |
| **Web UI** | aiohttp server on port 8080 for setup, QR login, API config |
| **Module system** | Dynamic plugin loading from `heroku/modules/` |
| **Database** | JSON file (`config-{user_id}.json`) with optional Redis backend |
| **Telegram API** | Via `herokutl` library (fork of Telethon) |
| **Inline bot** | Forms, galleries, lists via Telegram inline bot |

### System Dependencies (installed in Dockerfile)

- FFmpeg + media codec libraries
- Node.js 18
- wkhtmltopdf
- Cairo graphics library
- Git
- OpenSSH server

### How the Database Works

The app uses a dual-storage approach defined in `heroku/database.py`:

1. **Primary (with Redis/Valkey)**: If `REDIS_URL` env var or `redis_uri` config key is set,
   the Database class connects to Redis and stores all data there as JSON keyed by Telegram user ID.
   Saves are debounced (5 second delay) via async pipeline.

2. **Fallback (local file)**: Without Redis, data is written to `config-{user_id}.json` in the
   working directory. This is the default when running locally.

3. **Asset storage**: Large files (notes, media) are stored in a Telegram channel called
   "heroku-assets", not in the database.

This means **Valkey/Redis is already a first-class citizen** in the codebase. We just need
to set the `REDIS_URL` environment variable.

### Current Dockerfile (before migration)

```dockerfile
FROM python:3.10 AS python-base
FROM python-base AS builder-base

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=off \
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PIP_DEFAULT_TIMEOUT=100 \
    AIOHTTP_NO_EXTENSIONS=1 \
    PYSETUP_PATH="/opt/pysetup" \
    VENV_PATH="/opt/pysetup/.venv" \
    DOCKER=true \
    GIT_PYTHON_REFRESH=quiet

# System dependencies
RUN apt-get update && apt-get install ...

# !! PROBLEM: Clones from GitHub at build time
RUN git clone https://github.com/coddrago/Heroku /data/Heroku
WORKDIR /data/Heroku
RUN git fetch && git checkout master && git pull

RUN pip install -r requirements.txt
EXPOSE 8080
CMD ["python", "-m", "heroku", "--root"]
```

**Problems for App Platform:**
1. `git clone` at build time -- should use local source
2. Depends on persistent `/data` volume -- App Platform has no persistent disk
3. No graceful shutdown handling

---

## Phase 0: Understand the Current Setup

### Verify the app runs locally with the original Docker setup

```bash
cd /path/to/Heroku
docker-compose up --build
```

Expected result:
- Container starts, web UI available at http://localhost:8080
- Prompts for Telegram API credentials on first run
- Data stored in Docker volume `worker:/data`

### Key files to understand

| File | Role |
|------|------|
| `Dockerfile` | Build instructions (will be refactored) |
| `docker-compose.yml` | Local dev orchestration (kept for local testing) |
| `heroku/__main__.py` | Entry point, dependency checks, hash-based updates |
| `heroku/main.py` | Core app: multi-client Telegram auth, session management |
| `heroku/database.py` | JSON/Redis dual-storage database |
| `heroku/web/core.py` | aiohttp web server setup |
| `heroku/web/root.py` | Web UI routes (setup, QR login, auth) |

---

## Phase 1: Refactor the Dockerfile

### Changes

1. **Replace `git clone` with `COPY`** -- App Platform builds from the repo directly
2. **Remove git fetch/pull** -- App Platform handles deployments via git push
3. **Add `s3cmd`** -- For Spaces backup/restore
4. **Add `entrypoint.sh`** -- Wrapper for backup lifecycle
5. **Clean up apt cache** -- Reduce image size

### New Dockerfile

See the refactored `Dockerfile` in the repo (created in task t03).

Key differences:
- `COPY . /data/Heroku` replaces `git clone`
- `s3cmd` installed for Spaces backup
- `entrypoint.sh` copied and set as ENTRYPOINT
- SIGTERM handling for graceful backup on shutdown

---

## Phase 2: Add Valkey (Redis) for Persistence

### Why Valkey?

App Platform containers are **ephemeral** -- no persistent disk. The app already supports
Redis as a primary database (see `heroku/database.py` lines 104-111). We use DigitalOcean
Managed Valkey (Redis-compatible) so the database survives container restarts.

### How it works

1. App Platform provisions a Managed Valkey instance (defined in `.do/app.yaml`)
2. The `REDIS_URL` env var is **auto-bound** from the managed database using the syntax
   `${valkey.REDIS_URL}` in the app spec
3. On startup, `database.py` detects `REDIS_URL` and uses Redis as primary storage
4. All reads/writes go to Valkey instead of local JSON files

### No code changes required

The existing code in `heroku/database.py` already handles this:

```python
async def redis_init(self) -> bool:
    if REDIS_URI := (
        os.environ.get("REDIS_URL") or main.get_config_key("redis_uri")
    ):
        self._redis = redis.Redis.from_url(REDIS_URI)
```

---

## Phase 3: Add DigitalOcean Spaces Backup

### Why Spaces?

Even with Valkey as the primary database, we want a secondary backup for:
- Session files (`.session` files for Telegram auth)
- Module cache and loaded modules
- Any local state in `/data` that isn't in the database

### Strategy

An `entrypoint.sh` wrapper script handles the backup lifecycle:

1. **On container start**: Restore `/data` from Spaces (if backup exists)
2. **While running**: Periodic backup every 15 minutes (background process)
3. **On SIGTERM**: Final backup to Spaces before exit

### Setup (automated via doctl)

```bash
# Create Spaces key
doctl spaces keys create "heroku-userbot-key" --output json

# Create bucket
aws --endpoint-url https://nyc3.digitaloceanspaces.com \
    s3api create-bucket --bucket heroku-userbot-backup
```

### Environment variables

| Variable | Value | Description |
|----------|-------|-------------|
| `SPACES_ENDPOINT` | `https://nyc3.digitaloceanspaces.com` | Spaces API endpoint |
| `SPACES_BUCKET` | `heroku-userbot-backup` | Bucket name |
| `SPACES_ACCESS_KEY` | (from doctl) | Spaces access key |
| `SPACES_SECRET_KEY` | (from doctl) | Spaces secret key |

---

## Phase 4: Create App Platform Specification

### `.do/app.yaml`

The app spec defines:
- **Service**: Docker-based, built from the `app-platform` branch
- **Instance**: `apps-s-1vcpu-2gb` ($25/mo) -- 2GB RAM for media processing
- **Database**: Managed Valkey (dev tier), auto-bound via `${valkey.REDIS_URL}`
- **Environment variables**: Valkey URL, Spaces credentials, Docker flag

### Component mapping

| Current (Docker) | App Platform |
|-------------------|-------------|
| `docker-compose worker` | `services[0]` (name: userbot) |
| Docker volume `/data` | Valkey (primary) + Spaces (backup) |
| Port 8080 | `http_port: 8080` |
| `docker-compose up` | `git push` triggers deploy |

---

## Phase 5: Local Verification

### Build the refactored Docker image locally

```bash
cd /path/to/Heroku
docker build -t heroku-userbot-test .
```

### Run it locally

```bash
docker run -it --rm \
    -p 8080:8080 \
    -e DOCKER=true \
    heroku-userbot-test
```

### Verify

1. Container starts without errors
2. Web UI loads at http://localhost:8080
3. No git clone errors (since we COPY local source)
4. App prompts for Telegram API credentials

### Test with Valkey locally (optional)

```bash
docker run -d --name valkey -p 6379:6379 valkey/valkey:8

docker run -it --rm \
    -p 8080:8080 \
    -e DOCKER=true \
    -e REDIS_URL=redis://host.docker.internal:6379 \
    heroku-userbot-test
```

---

## Phase 6: Push to GitHub and Deploy

### 1. Commit and push the `app-platform` branch

```bash
git checkout app-platform
git add -A
git commit -m "Migrate to DigitalOcean App Platform"
git push -u origin app-platform
```

### 2. Create Spaces infrastructure (via doctl + aws CLI)

```bash
# Create Spaces key
KEY_JSON=$(doctl spaces keys create "heroku-userbot-key" --output json)
SPACES_ACCESS_KEY=$(echo "$KEY_JSON" | jq -r '.[0].access_key')
SPACES_SECRET_KEY=$(echo "$KEY_JSON" | jq -r '.[0].secret_key')

# Save the secret key immediately (shown only once)
echo "Access Key: $SPACES_ACCESS_KEY"
echo "Secret Key: $SPACES_SECRET_KEY"

# Create bucket
aws --endpoint-url https://nyc3.digitaloceanspaces.com \
    s3api create-bucket --bucket heroku-userbot-backup
```

### 3. Deploy to App Platform

```bash
doctl apps create --spec .do/app.yaml
```

Or deploy via the DigitalOcean Control Panel by importing `.do/app.yaml`.

### 4. Set secret environment variables

After the app is created, set the secrets that aren't in the spec:
- `SPACES_ACCESS_KEY` and `SPACES_SECRET_KEY` (from step 2)
- Telegram `api_id` and `api_hash` (if pre-configuring; otherwise set via web UI)

---

## Phase 7: Post-Migration Verification

### Health checks

- [ ] App Platform shows deployment as "Active"
- [ ] Web UI is accessible at the App Platform URL
- [ ] App prompts for Telegram credentials (or connects if pre-configured)

### Database verification

- [ ] Valkey connection established (check app logs for "Published db to Redis")
- [ ] No "Database file not found" warnings (data should be in Valkey)

### Spaces backup verification

- [ ] Check Spaces bucket has backup files:
  ```bash
  aws --endpoint-url https://nyc3.digitaloceanspaces.com \
      s3 ls s3://heroku-userbot-backup/ --recursive
  ```
- [ ] Restart the app and verify data restores from Spaces

### Telegram functionality

- [ ] Bot responds to commands
- [ ] Inline features work
- [ ] Modules load correctly

---

## Rollback Plan

If the migration fails:

1. The original `master` branch is untouched
2. Switch back to the previous Docker deployment:
   ```bash
   git checkout master
   docker-compose up --build
   ```
3. All data in Valkey persists independently of the app container
4. Spaces backups can be downloaded:
   ```bash
   aws --endpoint-url https://nyc3.digitaloceanspaces.com \
       s3 sync s3://heroku-userbot-backup/ ./backup/
   ```
