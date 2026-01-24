# Gigme MVP - Telegram WebApp events on a map

## Structure
- `backend/` - Go API + notification worker
- `frontend/` - React + Leaflet WebApp
- `infra/` - docker-compose and Postgres/PostGIS migrations

## Quick start (dev)
1. Create `.env` in the repo root:

```
TELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN
TELEGRAM_BOT_USERNAME=YOUR_BOT_USERNAME
JWT_SECRET=replace_me
BASE_URL=
ADMIN_TELEGRAM_IDS=123456789
```

2. Start infra:

```
cd infra
docker compose up --build
```

3. Create a bucket in MinIO (once):

```
# MinIO console: http://localhost:9001
# login: minio / minio123
# create bucket: gigme
```

4. Run the frontend locally:
лс
```
cd ../frontend
npm install
VITE_API_URL=http://localhost:8080 npm run dev
```

## Environment variables

### Backend / Worker
- `DATABASE_URL` - Postgres connection string
- `REDIS_URL` - (optional)
- `S3_ENDPOINT` - S3/MinIO endpoint (example `http://minio:9000`)
- `S3_BUCKET`
- `S3_ACCESS_KEY`
- `S3_SECRET_KEY`
- `S3_REGION`
- `S3_USE_SSL` - `true|false`
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_BOT_USERNAME`
- `JWT_SECRET`
- `BASE_URL` - (optional) base URL for links
- `ADMIN_TELEGRAM_IDS` - allowlist admin ids (comma-separated)

### Frontend
- `VITE_API_URL` - API URL

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

## API summary
Implemented endpoints:
- `POST /auth/telegram`
- `GET /me`
- `POST /events`
- `GET /events/nearby`
- `GET /events/feed`
- `GET /events/{id}`
- `POST /events/{id}/join`
- `POST /events/{id}/leave`
- `POST /events/{id}/promote` (501)
- `POST /media/presign`
- `POST /admin/events/{id}/hide`
