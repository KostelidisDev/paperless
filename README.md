# Paperless

Docker Compose stack for [Paperless-ngx](https://docs.paperless-ngx.com/), served behind Traefik,
plus a GitHub Actions workflow that builds a Paperless-ngx image with Greek OCR data baked in.

## Services

| Service     | Container             | Image                                        | Purpose                                   |
|-------------|-----------------------|----------------------------------------------|-------------------------------------------|
| `paperless` | `paperless`           | `${PAPERLESS_IMAGE}:${PAPERLESS_IMAGE_TAG}`  | Web UI, API, consumer and task workers    |
| `postgres`  | `paperless-postgres`  | `postgres:${POSTGRES_TAG}`                   | Database                                  |
| `broker`    | `paperless-broker`    | `valkey/valkey:${VALKEY_TAG}`                | Task queue (Redis-compatible)             |
| `gotenberg` | `paperless-gotenberg` | `gotenberg/gotenberg:${GOTENBERG_TAG}`       | Office/HTML → PDF conversion              |
| `tika`      | `paperless-tika`      | `${TIKA_IMAGE}:${TIKA_IMAGE_TAG}`            | Text extraction from Office files & email |

### Images

Two ready-made env files choose where the Paperless and Tika images come from:

| File                | Paperless image                        | Tika image                                 |
|---------------------|----------------------------------------|--------------------------------------------|
| `.env.example`      | `ghcr.io/paperless-ngx/paperless-ngx`  | `apache/tika`                              |
| `.env.fork.example` | `ghcr.io/kostelidisdev/paperless`      | `ghcr.io/kostelidisdev/paperless-tika`     |

The fork Paperless image is built from this repository's [`Dockerfile`](Dockerfile): the upstream
image with `tesseract-ocr-ell` installed and `PAPERLESS_OCR_LANGUAGE=ell+eng` set. The upstream image
does not ship Greek OCR data, so `.env.example` uses `eng` and `.env.fork.example` uses `ell+eng`.

### Networks

- `paperless` — the only network the web container exposes; Traefik routes to port `8000` on it.
- `paperless-backend` — `internal: true`, no outbound access. Database, broker, Gotenberg and Tika live only here.

### Volumes

| Volume                 | Mounted at                       |
|------------------------|----------------------------------|
| `paperless-data`       | `/usr/src/paperless/data`        |
| `paperless-media`      | `/usr/src/paperless/media`       |
| `paperless-consume`    | `/usr/src/paperless/consume`     |
| `paperless-export`     | `/usr/src/paperless/export`      |
| `paperless-pgdata`     | `/var/lib/postgresql`            |
| `paperless-brokerdata` | `/data` (Valkey)                 |

### Hardening

Every container runs with `no-new-privileges`, CPU/memory/PID limits and rotated, compressed
`json-file` logs. Gotenberg additionally drops all capabilities, runs Chromium with JavaScript
disabled and only allows `file:///tmp/` URLs.

## Requirements

- Docker Engine with Compose v2.
- Traefik running with:
  - a `websecure` entrypoint that provides TLS (wildcard default certificate),
  - a `strict-path@file` middleware defined elsewhere,
  - access to the `paperless` network.
- If the fork images on GHCR are private: `docker login ghcr.io`.

## Setup

```sh
cp .env.example .env        # or .env.fork.example for the fork images
chmod 600 .env
```

Edit `.env` and set at least:

| Variable               | Notes                                                                       |
|------------------------|-----------------------------------------------------------------------------|
| `DOMAIN`               | Public hostname; used for `PAPERLESS_URL` and the Traefik router rule.      |
| `PAPERLESS_SECRET_KEY` | Long random string. Never change it once set — it logs everyone out and breaks signed links. |
| `POSTGRES_PASSWORD`    | Must match the existing database user's password.                           |
| `PAPERLESS_IMAGE_TAG`  | Pin an immutable tag rather than `latest`.                                  |

Generate a secret key, for example:

```sh
openssl rand -base64 48
```

Both secrets are passed to the containers as Compose secrets (`/run/secrets/…`), not as plain environment variables.

## Usage

```sh
docker compose pull
docker compose up -d
docker compose ps        # wait until every service is healthy
docker compose logs -f paperless
```

Create the first admin user:

```sh
docker compose exec paperless python3 manage.py createsuperuser
```

### Upgrading

Update `PAPERLESS_IMAGE_TAG`, `TIKA_IMAGE_TAG` and any third-party `*_TAG` in `.env`, then:

```sh
docker compose pull
docker compose up -d
```

## Configuration

All settings live in `.env`; see [`.env.example`](.env.example) for the full list with defaults.

- **Access control** — `IPV4_ALLOWLIST` / `IPV6_ALLOWLIST` restrict the web UI and API via a Traefik IP allowlist. Defaults allow everyone.
- **OCR** — `PAPERLESS_OCR_LANGUAGE` is `eng` with the upstream image and `ell+eng` (Greek + English) with the fork image; see [Images](#images).
- **Workers** — Paperless sizes its workers from the *host's* CPU count, not the container limit, so they are set explicitly. Keep `PAPERLESS_TASK_WORKERS × PAPERLESS_THREADS_PER_WORKER ≤ PAPERLESS_CPU_LIMIT`.
- **Resource limits** — every service has CPU, memory, memory-reservation and PID limits (`PAPERLESS_*_CPU_LIMIT`, `*_MEMORY_LIMIT`, …). OCR is memory-hungry; don't drop the main container much below 2G.
- **Tika heap** — `PAPERLESS_TIKA_HEAP_PERCENT` (default 60) sets the JVM's max heap as a share of the container memory limit.
- **Time zone** — `TZ`, default `Europe/Athens`.

## Building the image

[`.github/workflows/docker-publish.yml`](.github/workflows/docker-publish.yml) builds the
[`Dockerfile`](Dockerfile) natively on `linux/amd64` and `linux/arm64` runners, then merges both into
one multi-arch image at `ghcr.io/<owner>/<repo>`. Pull requests build without pushing.

| Trigger                  | Tags                                                  |
|--------------------------|-------------------------------------------------------|
| Push to `main`           | `main`, `latest`, `sha-<short>`                       |
| Tag `vX.Y.Z`             | `X.Y.Z`, `X.Y`, `sha-<short>`                         |
| Weekly (Sunday 00:00 UTC) | `main`, `latest`, `YYYYMMDD` — picks up base-image fixes |

`main` and `latest` move; deploy a version, `sha-` or dated tag instead.

The upstream Paperless version is set by `PAPERLESS_TAG` in the `Dockerfile`. To build locally:

```sh
docker build --build-arg PAPERLESS_TAG=3.2.1 -t paperless .
```

[Dependabot](.github/dependabot.yml) checks the Dockerfile, the Compose file and the GitHub
Actions weekly.

## Backups

Export documents and metadata with the built-in exporter (writes to the `paperless-export` volume):

```sh
docker compose exec paperless document_exporter ../export
```

For a full backup, also snapshot the `paperless-pgdata`, `paperless-data` and `paperless-media` volumes, or dump the database:

```sh
docker compose exec postgres pg_dump -U paperless paperless > paperless.sql
```
