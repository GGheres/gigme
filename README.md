# Gigme MVP - Telegram WebApp events on a map

## Structure
- `backend/` - Go API + notification worker
- `frontend/` - React + Leaflet WebApp
- `infra/` - docker-compose and Postgres/PostGIS migrations

## Quick start (dev)
1. Create `infra/.env` (used by docker compose):

```
TELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN
TELEGRAM_BOT_USERNAME=YOUR_BOT_USERNAME
JWT_SECRET=replace_me
BASE_URL=
API_PUBLIC_URL=
ADMIN_TELEGRAM_IDS=123456789
S3_PUBLIC_ENDPOINT=http://localhost:9000
```

2. Create `frontend/.env` (used by Vite dev/build):
```
VITE_API_URL=http://localhost:8080
VITE_ADMIN_TELEGRAM_IDS=123456789
VITE_TELEGRAM_BOT_USERNAME=YOUR_BOT_USERNAME
```

3. Start infra:

```
cd infra
docker compose up --build
```

4. Create a bucket in MinIO (once):

```
# MinIO console: http://localhost:9001
# login: minio / minio123
# create bucket: gigme
```

5. Run the frontend locally:
```
cd ../frontend
npm install
npm run dev
```

## Environment variables

### Backend / Worker
- `DATABASE_URL` - Postgres connection string
- `REDIS_URL` - (optional)
- `S3_ENDPOINT` - S3/MinIO endpoint (example `http://minio:9000`)
- `S3_PUBLIC_ENDPOINT` - public S3/MinIO endpoint for browser uploads (example `http://localhost:9000`)
- `S3_BUCKET`
- `S3_ACCESS_KEY`
- `S3_SECRET_KEY`
- `S3_REGION`
- `S3_USE_SSL` - `true|false`
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_BOT_USERNAME`
- `JWT_SECRET`
- `BASE_URL` - (optional) base URL for links
- `API_PUBLIC_URL` - optional public API base URL for notification media (example `https://spacefestival.fun/api`)
- `ADMIN_TELEGRAM_IDS` - allowlist admin ids (comma-separated)
- `LOG_LEVEL` - `debug|info|warn|error` (default: `info`)
- `LOG_FORMAT` - `text|json` (default: `text`)
- `LOG_FILE` - optional path to also write logs to a file

### Frontend
- `VITE_API_URL` - API URL
- `VITE_ADMIN_TELEGRAM_IDS` - allowlist admin ids (comma-separated)
- `VITE_TELEGRAM_BOT_USERNAME` - Telegram bot username for share links
- `VITE_CARD_TOPUP_ENABLED` - `true|false` (default: `false`). Enable card topups when payment integration is ready.
- `VITE_LOG_LEVEL` - `debug|info|warn|error|off` (default: `info`). Overrides can be set at runtime with `localStorage.setItem('gigme:logLevel', 'debug')`.
- `VITE_LOG_TO_SERVER` - `true|false` (default: `true` in dev, `false` in prod). Runtime override: `localStorage.setItem('gigme:logToServer', 'true')`.
- `VITE_LOG_ENDPOINT` - optional full URL for client log sink (defaults to `${VITE_API_URL}/logs/client`).
- `VITE_PRESIGN_ENABLED` - `true|false` (default: `true`). Set `false` to always upload via API instead of presigned S3.

## Deployment (prod, Docker Compose)
1. Copy and fill the production env file:

```
cp infra/.env.prod.example infra/.env.prod
```

2. Build and start the stack:

```
docker compose -f infra/docker-compose.prod.yml --env-file infra/.env.prod up -d --build
```

3. Create the S3/MinIO bucket (once), for example `gigme`.

Notes:
- `VITE_*` variables are baked into the frontend build. Rebuild the `frontend` image after changing them.
- Set `BASE_URL` to the public WebApp URL so Telegram buttons point to the correct host.
- If you use managed Postgres/S3, update `DATABASE_URL` / `S3_*` in `infra/.env.prod`.
- DNS: point `spacefestival.fun` (and optionally `www.spacefestival.fun`) to your server IP; API is served from `/api` on the same domain. Ensure ports 80/443 are open (Caddy handles TLS).
- If `VITE_PRESIGN_ENABLED=false`, uploads go through the API and `S3_PUBLIC_ENDPOINT` can stay internal (e.g. `http://minio:9000`).
- MinIO ports are not exposed in the prod compose; access is internal-only.

## Test calls
```
POST /auth/telegram
{ "initData": "..." }

GET /events/nearby?lat=52.37&lng=4.9&radiusM=5000
```

## MVP notes
- Rate limiting: create event (3/hour), join/leave (10/min) - best effort.
- Notifications: worker scans `notification_jobs`.
- Media: presigned uploads to S3/MinIO.
- Nearby notifications depend on clients sending `POST /me/location`.
- Profile: `/profile` shows Telegram profile data, rating, GigTokens balance, and created events.
- Referrals: sharing an event link with a referral code awards +100 GigTokens to inviter + invitee on first signup.

## API summary
Implemented endpoints:
- `POST /auth/telegram`
- `POST /logs/client`
- `GET /me`
- `POST /me/location`
- `GET /referrals/my-code`
- `POST /referrals/claim`
- `POST /events`
- `GET /events/mine`
- `GET /events/nearby`
- `GET /events/feed`
- `GET /events/{id}`
- `POST /events/{id}/like`
- `DELETE /events/{id}/like`
- `GET /events/{id}/comments`
- `POST /events/{id}/comments`
- `POST /events/{id}/join`
- `POST /events/{id}/leave`
- `POST /events/{id}/promote` (admin only)
- `POST /media/presign`
- `POST /wallet/topup/token`
- `POST /wallet/topup/card`
- `POST /admin/events/{id}/hide`
- `PATCH /admin/events/{id}` (admin only)
- `DELETE /admin/events/{id}` (admin only)

Promoted events are marked as featured and sorted to the top while `promoted_until` is in the future.
