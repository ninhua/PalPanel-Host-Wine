# AGENTS.md — PalPanel Host-Wine Fork

## Project invariants

- Production is Linux amd64 in a 简幻欢 container.
- `/home/container` is NFS-backed persistent storage.
- `/home/container/start.sh` is the only root startup script.
- All other persistent data belongs under `/home/container/palworld_win`.
- There is no real Docker daemon in production.
- The PalServer process is `Pal/Binaries/Win64/PalServer-Win64-Shipping-Cmd.exe` under portable Wine.
- The authoritative save directory is `server/Pal/Saved/SaveGames`.
- Never reintroduce tmpfs/shm save mirroring.
- Fail closed when the save preflight fails.

## SteamCMD

- Use Windows `steamcmd.exe` for server install/update and Workshop.
- Use a dedicated SteamCMD Wine prefix separate from the PalServer prefix.
- Anonymous is the default.
- No default Steam username; no forced login.
- Never persist passwords or Steam Guard codes.

## Download policy

GitHub download order:

1. `https://v4.gh-proxy.org`
2. `https://cdn.gh-proxy.org`
3. direct GitHub

All downloads need bounds, temporary files, validation and SHA-256 where a trusted digest is available.

## Development workflow

For every atomic change:

1. update/add tests;
2. implement;
3. run relevant checks;
4. update docs/OpenAPI and CHANGELOG;
5. commit with a meaningful Conventional Commit message;
6. push immediately;
7. verify CI before starting the next task.

Do not finish a task with uncommitted or unpushed changes.

## Source references

- Base: `uitok/palworld-panel` v1.2.1.
- Feature reference: `CoderYiXin/PalOpsWeb` 1.2.0.
- PalOps is a business and security design reference; rewrite in Go/React rather than embedding .NET/Vue.

## Safety

Never commit secrets, user saves, databases, runtime logs, Steam caches, Wine prefixes or public addresses. Avoid destructive git commands and never force-push protected branches.
