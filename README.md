# Gigme MVP - Telegram WebApp events on a map

## Structure
- `backend/` - Go API + notification worker
- `frontend/` - React + Leaflet WebApp (legacy client, disabled in prod by default)
- `flutter_app/` - Flutter client (Mode A Telegram Web MVP, Mode B standalone scaffold)
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

2. Optional: create `frontend/.env` if you need to run legacy React UI locally:
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

5. Optional: run legacy frontend locally:
```
cd ../frontend
npm install
npm run dev
```

6. Run the Flutter client locally (optional, Mode A):
```
cd ../flutter_app
flutter create . --platforms=android,ios,web
flutter pub get
flutter run -d chrome \
  --dart-define=API_URL=http://localhost:8080 \
  --dart-define=BOT_USERNAME=YOUR_BOT_USERNAME \
  --dart-define=AUTH_MODE=telegram_web
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
- `HMAC_SECRET` - HMAC key for signed ticket QR payloads
- `TICKET_HMAC_SECRET` - optional alias for `HMAC_SECRET` (used if `HMAC_SECRET` is empty)
- `BASE_URL` - (optional) base URL for links
- `API_PUBLIC_URL` - optional public API base URL for notification media (example `https://spacefestival.fun/api`)
- `ADMIN_TELEGRAM_IDS` - allowlist admin ids (comma-separated)
- `PHONE_NUMBER` - manual transfer recipient shown for `PHONE` payment method
- `USDT_WALLET` - wallet shown for `USDT` payment method
- `USDT_NETWORK` - network label (default `TRC20`)
- `USDT_MEMO` - optional memo/tag for USDT transfers
- `PAYMENT_QR_DATA` - optional payment payload template for QR method (`{order_id}`, `{event_id}`, `{amount}`, `{amount_cents}` placeholders supported)
- `PAYMENT_PHONE_NUMBER` / `PAYMENT_USDT_*` aliases are also supported on backend.
- These payment fields can be overridden in Admin panel (`/space_app/admin` -> `Products` -> `Payment settings`).
- `TOCHKA_CLIENT_ID` - Tochka OAuth client id
- `TOCHKA_CLIENT_SECRET` - Tochka OAuth client secret
- `TOCHKA_CUSTOMER_CODE` - optional Tochka customer/company context header
- `TOCHKA_MERCHANT_ID` - merchant id for SBP QR registration
- `TOCHKA_ACCOUNT_ID` - account id for SBP QR registration
- `TOCHKA_SCOPE` - OAuth scope (default `sbp`)
- `TOCHKA_TOKEN_URL` - OAuth token endpoint (default `https://enter.tochka.com/connect/token`)
- `TOCHKA_API_BASE_URL` - Tochka API base URL (default `https://enter.tochka.com/uapi`)
- `TOCHKA_REDIRECT_URL` - optional redirect URL template for dynamic QR (`{order_id}` placeholder is supported)
- `LOG_LEVEL` - `debug|info|warn|error` (default: `info`)
- `LOG_FORMAT` - `text|json` (default: `text`)
- `LOG_FILE` - optional path to also write logs to a file

### Frontend (legacy, optional)
- `VITE_API_URL` - API URL
- `VITE_ADMIN_TELEGRAM_IDS` - allowlist admin ids (comma-separated)
- `VITE_TELEGRAM_BOT_USERNAME` - Telegram bot username for share links
- `VITE_CARD_TOPUP_ENABLED` - `true|false` (default: `false`). Enable card topups when payment integration is ready.
- `VITE_LOG_LEVEL` - `debug|info|warn|error|off` (default: `info`). Overrides can be set at runtime with `localStorage.setItem('gigme:logLevel', 'debug')`.
- `VITE_LOG_TO_SERVER` - `true|false` (default: `true` in dev, `false` in prod). Runtime override: `localStorage.setItem('gigme:logToServer', 'true')`.
- `VITE_LOG_ENDPOINT` - optional full URL for client log sink (defaults to `${VITE_API_URL}/logs/client`).
- `VITE_PRESIGN_ENABLED` - `true|false` (default: `true`). Set `false` to always upload via API instead of presigned S3.
- In production this client is disabled by default (`frontend` service is behind compose profile `legacy`).

### Flutter frontend
- `API_URL` - backend API URL (passed via `--dart-define` or Docker build arg `FLUTTER_API_URL`)
- `BOT_USERNAME` - Telegram bot username used in shared referral links
- `AUTH_MODE` - `telegram_web` (Mode A) or `standalone` (Mode B scaffold)
- `STANDALONE_AUTH_URL` - optional helper URL for Mode B login (returns `initData` via deep link/query)
- `STANDALONE_REDIRECT_URI` - deep-link URL for Mode B callback (default `gigme://auth`)
- `ENABLE_PUSH` - `true|false` toggle for FCM scaffold initialization in standalone mode
- `ADMIN_TELEGRAM_IDS` - optional comma-separated allowlist for showing admin UI entrypoint
- `PAYMENT_PHONE_NUMBER` - phone transfer recipient shown on checkout screen
- `PAYMENT_USDT_WALLET` - USDT wallet shown on checkout screen
- `PAYMENT_USDT_NETWORK` - USDT network label (default `TRC20`)
- `PAYMENT_USDT_MEMO` - optional memo/tag for USDT transfer
- `PAYMENT_QR_DATA` - optional payment payload shown for QR payment method
- Production build args are read from `infra/.env.prod` as `FLUTTER_*` variables.

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
- `VITE_*` variables are only for legacy React frontend. It is not started in default prod stack.
- `FLUTTER_*` variables are baked into the Flutter web build. Rebuild the `flutter_frontend` image after changing them.
- For standalone mobile auth helper use `FLUTTER_STANDALONE_AUTH_URL` (for this stack: `https://<domain>/api/auth/standalone`) and set deep link with `FLUTTER_STANDALONE_REDIRECT_URI`.
- Set `BASE_URL` to the public WebApp URL so Telegram buttons point to the correct host.
- If you use managed Postgres/S3, update `DATABASE_URL` / `S3_*` in `infra/.env.prod`.
- DNS: point `spacefestival.fun` (and optionally `www.spacefestival.fun`) to your server IP; API is served from `/api` on the same domain. Ensure ports 80/443 are open (Caddy handles TLS).
- In production Flutter Web serves both surfaces: landing at `/` and app at `/space_app`.
- Legacy React frontend can be started manually with `--profile legacy`, but Caddy routes public traffic to Flutter (`/` and `/space_app`).
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
- `GET /auth/standalone` (Telegram Login Widget helper for Mode B)
- `POST /auth/standalone/exchange` (helper payload -> signed `initData`)
- `POST /logs/client`
- `GET /me`
- `POST /me/location`
- `POST /me/push-token`
- `GET /referrals/my-code`
- `POST /referrals/claim`
- `POST /events`
- `GET /events/mine`
- `GET /events/nearby`
- `GET /events/feed`
- `GET /landing/events` (public landing feed)
- `GET /events/{id}`
- `POST /events/{id}/like`
- `DELETE /events/{id}/like`
- `GET /events/{id}/comments`
- `POST /events/{id}/comments`
- `POST /events/{id}/join`
- `POST /events/{id}/leave`
- `GET /events/{id}/products`
- `POST /orders`
- `POST /payments/sbp/qr/create`
- `GET /payments/sbp/qr/{orderId}/status`
- `GET /payments/settings`
- `GET /orders/my`
- `POST /orders/{id}/confirm` (admin only)
- `POST /orders/{id}/cancel` (admin only)
- `GET /tickets/my`
- `POST /tickets/{id}/redeem` (admin only)
- `POST /promo-codes/validate`
- `POST /events/{id}/promote` (admin only)
- `POST /media/presign`
- `POST /wallet/topup/token`
- `POST /wallet/topup/card`
- `POST /admin/events/{id}/hide`
- `POST /admin/events/{id}/landing` (admin publish/unpublish on landing)
- `PATCH /admin/events/{id}` (admin only)
- `DELETE /admin/events/{id}` (admin only)
- `GET /admin/parser/sources` (admin only)
- `POST /admin/parser/sources` (admin only)
- `PATCH /admin/parser/sources/{id}` (admin only)
- `POST /admin/parser/sources/{id}/parse` (admin only)
- `POST /admin/parser/parse` (admin only)
- `POST /admin/parser/geocode` (admin only)
- `GET /admin/parser/events` (admin only)
- `POST /admin/parser/events/{id}/import` (admin only)
- `POST /admin/parser/events/{id}/reject` (admin only)
- `GET /admin/orders` (admin only)
- `GET /admin/orders/{id}` (admin only)
- `POST /admin/orders/{orderId}/confirm` (admin only)
- `POST /admin/tickets/redeem` (admin only)
- `GET /admin/stats` (admin only)
- `GET /admin/payment-settings` (admin only)
- `POST /admin/payment-settings` (admin only)
- `GET /admin/products/tickets` / `POST /admin/products/tickets` / `PATCH /admin/products/tickets/{id}` / `DELETE /admin/products/tickets/{id}` (admin only)
- `GET /admin/products/transfers` / `POST /admin/products/transfers` / `PATCH /admin/products/transfers/{id}` / `DELETE /admin/products/transfers/{id}` (admin only)
- `GET /admin/promo-codes` / `POST /admin/promo-codes` / `PATCH /admin/promo-codes/{id}` / `DELETE /admin/promo-codes/{id}` (admin only)

Promoted events are marked as featured and sorted to the top while `promoted_until` is in the future.

## Ticket purchase + QR validation
- DB schema: apply migrations `infra/migrations/017_ticketing.up.sql`, `infra/migrations/018_sbp_tochka_payments.up.sql`, and `infra/migrations/019_payment_settings.up.sql` (adds `PAID` status, `sbp_qr`, `payments`, and editable payment settings).
- Purchase flow:
  1. User opens event page, chooses tickets/transfer, optional promo, and payment method.
  2. For manual methods (`PHONE`, `USDT`, `PAYMENT_QR`) app uses `POST /orders` and waits for admin confirmation.
  3. For Tochka SBP method app uses `POST /payments/sbp/qr/create`, backend creates a dynamic SBP QR and returns `payload` + `qrcId`.
  4. App polls `GET /payments/sbp/qr/{orderId}/status`; when payment is `Accepted`, backend marks order `PAID`, generates signed ticket QR payloads, and sends ticket QR images to Telegram bot.
- Admin payment fallback:
  1. Open `Admin orders` screen.
  2. Review order details and click `Confirm payment` (`POST /admin/orders/{orderId}/confirm`).
  3. Backend marks order `PAID`, generates signed QR payload per ticket, and sends QR image to Telegram.
- Ticket redeem:
  1. Admin opens `QR scanner`.
  2. Scan QR or paste payload / ticket ID manually.
  3. `POST /admin/tickets/redeem` (or legacy `POST /tickets/{id}/redeem`) verifies HMAC signature and atomically marks ticket redeemed.
  4. Repeated redeem attempts return conflict (`ticket already redeemed`).
- Stats/accounting:
  - `GET /admin/stats` returns global and per-event totals:
    - purchased amount (`PAID + REDEEMED`; legacy `CONFIRMED` is still counted)
    - redeemed amount (`REDEEMED`)
    - counts by ticket type and transfer direction.

## Tochka SBP setup
- Credentials:
  1. In Tochka developer cabinet create/get OAuth client credentials (`TOCHKA_CLIENT_ID`, `TOCHKA_CLIENT_SECRET`).
  2. Get SBP merchant/account identifiers (`TOCHKA_MERCHANT_ID`, `TOCHKA_ACCOUNT_ID`).
  3. If your organization requires context header, set `TOCHKA_CUSTOMER_CODE`.
  4. Set ticket signature secret (`HMAC_SECRET` or `TICKET_HMAC_SECRET`) and bot token (`TELEGRAM_BOT_TOKEN`).
- Sandbox vs production:
  - Use separate credential sets for sandbox and production.
  - Override endpoints with `TOCHKA_TOKEN_URL` and `TOCHKA_API_BASE_URL` only if Tochka provides different URLs for your environment.
  - Keep `TOCHKA_SCOPE=sbp` unless your contract specifies another scope.
- Troubleshooting:
  - `sbp payment is not configured`: required Tochka env vars are missing in API container.
  - `tochka register qr failed`: verify OAuth credentials, `merchantId/accountId`, and (if used) `customerCode`.
  - Status remains `unknown`/unavailable: dynamic QR status may be unavailable after QR lifetime or about 24h after payment; use admin confirm fallback.
  - Money received but order still `PENDING`: run `POST /admin/orders/{orderId}/confirm`, then check ticket delivery in Telegram bot.

## Universal Event Parser

### How dispatch works
- Entry point: `backend/internal/eventparser/parser.go`.
- Public API:
  - Go: `eventparser.ParseEvent(ctx, input)`
  - Go with explicit source: `eventparser.ParseEventWithSource(ctx, input, sourceType)`
  - CLI: `backend/cmd/gigme-event-parse/main.go`
- Source routing:
  - `instagram.com` -> Instagram parser
  - `t.me` (or plain channel name) -> Telegram parser
  - `vk.com` -> VK parser
  - everything else -> generic Web parser
- Non-URL input supports Telegram channel shortcut (`channelName` => `https://t.me/s/channelName`).

### Platform limitations
- Parser is intentionally **no-login first** (HTTP + HTML parsing).
- Instagram and VK often block unauthenticated scraping:
  - parser returns typed errors (`AuthRequiredError` / `DynamicContentError`) with hints.
- Browser rendering is not enabled by default; only `BrowserFetcher` interface stub is provided for future Playwright/Selenium integration.
- Telegram parser now extracts all channel messages for the last 24 hours from `/s/` view and includes photo URLs from message media blocks.
- During import from parser, if media is not set manually, image links are auto-selected from parsed links.
- Admin geocoding uses Nominatim (OpenStreetMap) via `/admin/parser/geocode`; lat/lng can be auto-filled from location text.

### CLI usage
From `backend/`:
```bash
go run ./cmd/gigme-event-parse -source auto "https://t.me/s/some_channel"
go run ./cmd/gigme-event-parse -source telegram "some_channel"
```

### Extending with new parser modules
1. Add a parser in `backend/internal/eventparser/parsers/` implementing:
   - `Parse(ctx context.Context, input string) (*core.EventData, error)`
2. Register it in `backend/internal/eventparser/parser.go`.
3. Update source detection in `backend/internal/eventparser/core/dispatcher.go` if domain-based dispatch is needed.
4. Add fixtures/tests under `backend/internal/eventparser/tests/`.
