# Paperless

Docker Compose stack for [Paperless-ngx](https://docs.paperless-ngx.com/), served behind Traefik.

## Services

| Service     | Container             | Image                                          | Purpose                                   |
|-------------|-----------------------|------------------------------------------------|-------------------------------------------|
| `paperless` | `paperless`           | `${DOCKER_REGISTRY}/…/paperless-ngx`           | Web UI, API, consumer and task workers    |
| `postgres`  | `paperless-postgres`  | `postgres:${POSTGRES_TAG}`                     | Database                                  |
| `broker`    | `paperless-broker`    | `valkey/valkey:${VALKEY_TAG}`                  | Task queue (Redis-compatible)             |
| `gotenberg` | `paperless-gotenberg` | `gotenberg/gotenberg:${GOTENBERG_TAG}`         | Office/HTML → PDF conversion              |
| `tika`      | `paperless-tika`      | `${DOCKER_REGISTRY}/…/paperless-tika`          | Text extraction from Office files & email |

The `paperless-ngx` and `paperless-tika` images are pulled from the private registry
(`gitea.kostelidis.dev/kostelidisdev/paperless` by default) and share the same `DOCKER_TAG`.

### Networks

- `paperless` — the only network the web container exposes; Traefik routes to port `8000` on it.
- `paperless_backend` — `internal: true`, no outbound access. Database, broker, Gotenberg and Tika live only here.

### Volumes

| Volume                 | Mounted at                       |
|------------------------|----------------------------------|
| `paperless_data`       | `/usr/src/paperless/data`        |
| `paperless_media`      | `/usr/src/paperless/media`       |
| `paperless_consume`    | `/usr/src/paperless/consume`     |
| `paperless_export`     | `/usr/src/paperless/export`      |
| `paperless_pgdata`     | `/var/lib/postgresql`            |
| `paperless_brokerdata` | `/data` (Valkey)                 |

## Requirements

- Docker Engine with Compose v2.
- Traefik running with:
  - a `websecure` entrypoint that provides TLS (wildcard default certificate),
  - a `strict-path@file` middleware defined elsewhere,
  - access to the `paperless` network.
- Pull access to the private image registry (`docker login gitea.kostelidis.dev`).

## Setup

```sh
cp .env.example .env
chmod 600 .env
```

Edit `.env` and set at least:

| Variable               | Notes                                                                       |
|------------------------|-----------------------------------------------------------------------------|
| `DOMAIN`               | Public hostname; used for `PAPERLESS_URL` and the Traefik router rule.      |
| `DOCKER_TAG`           | Pin an immutable tag rather than `latest`.                                  |
| `PAPERLESS_SECRET_KEY` | Long random string. Never change it once set — it logs everyone out and breaks signed links. |
| `POSTGRES_PASSWORD`    | Must match the existing database user's password.                           |

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

Update `DOCKER_TAG` (and any third-party `*_TAG`) in `.env`, then:

```sh
docker compose pull
docker compose up -d
```

## Configuration

All settings live in `.env`; see [`.env.example`](.env.example) for the full list with defaults.

- **Access control** — `IPV4_ALLOWLIST` / `IPV6_ALLOWLIST` restrict the web UI and API via a Traefik IP allowlist. Defaults allow everyone.
- **OCR** — `PAPERLESS_OCR_LANGUAGE` defaults to `ell+eng` (Greek + English).
- **Workers** — Paperless sizes its workers from the *host's* CPU count, not the container limit, so they are set explicitly. Keep `PAPERLESS_TASK_WORKERS × PAPERLESS_THREADS_PER_WORKER ≤ PAPERLESS_CPU_LIMIT`.
- **Resource limits** — every service has CPU, memory, memory-reservation and PID limits (`PAPERLESS_*_CPU_LIMIT`, `*_MEMORY_LIMIT`, …). OCR is memory-hungry; don't drop the main container much below 2G.
- **Tika heap** — `PAPERLESS_TIKA_HEAP_PERCENT` (default 60) sets the JVM's max heap as a share of the container memory limit.
- **Time zone** — `TZ`, default `Europe/Athens`.

## Backups

Export documents and metadata with the built-in exporter (writes to the `paperless_export` volume):

```sh
docker compose exec paperless document_exporter ../export
```

For a full backup, also snapshot the `paperless_pgdata`, `paperless_data` and `paperless_media` volumes, or dump the database:

```sh
docker compose exec postgres pg_dump -U paperless paperless > paperless.sql
```
