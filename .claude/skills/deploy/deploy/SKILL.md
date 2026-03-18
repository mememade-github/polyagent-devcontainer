---
name: deploy
description: Deploy services to production server
argument-hint: "[target]"
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash, Read
---

Deploy to production. This is a DESTRUCTIVE operation - always confirm with the user.

Target: $ARGUMENTS

## Steps:
1. Read CLAUDE.md and REFERENCE.md for deployment commands and server details
2. Ask user for confirmation before proceeding
3. Run pre-deployment checks (connectivity test)
4. Run deployment with `--check` (dry-run) first
5. Show check results, ask for final confirmation
6. Run actual deployment
7. Run post-deployment verification (system-status or health checks)

## Discovery

Look for deployment configuration in:
- `REFERENCE.md` — "Server Deployment" section
- `CLAUDE.md` — deployment-related instructions
- `ansible/` or `deploy/` directories
- `docker-compose.yml` or `Dockerfile`
