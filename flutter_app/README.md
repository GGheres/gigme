# GigMe Flutter App (MVP)

Flutter migration of GigMe frontend with unchanged Go backend contracts.

## Modes

- `Mode A (current MVP)`: Flutter Web inside Telegram WebView (`initData` -> `POST /auth/telegram`).
- `Mode B (implemented scaffold)`: standalone Android/iOS auth via deep-link/helper URL returning `initData`, then same `POST /auth/telegram` backend contract.
- `Web OAuth (optional)`: VK web login (`access_token` callback -> `POST /auth/vk`) for web users.
- `VK Mini Apps (optional)`: auth via VK launch params (`window.location.search` with `sign`) -> `POST /auth/vk/miniapp`.

## Project structure

- `lib/app` - router, shell, theme
- `lib/core` - config, API client, models, storage, utils
- `lib/features/auth` - Telegram auth and session bootstrap
- `lib/features/events` - feed/map/create/details
- `lib/features/profile` - `/me`, `/events/mine`, token topup
- `lib/features/admin` - users moderation, broadcasts, parser import flow
- `lib/integrations/telegram` - JS bridge for Telegram WebApp
- `lib/core/notifications` - FCM bootstrap scaffold (standalone mode)

## Environment (`--dart-define`)

- `API_URL` (default `/api`)
- `BOT_USERNAME` (used for share links)
- `VK_APP_ID` (optional VK OAuth application id for web login button)
- `AUTH_MODE` (`telegram_web` or `standalone`)
- `STANDALONE_AUTH_URL` (optional helper URL for Mode B login start)
- `STANDALONE_REDIRECT_URI` (deep-link target for helper callback, default `gigme://auth`)
- `ENABLE_PUSH` (`true|false`, default `false`; enables FCM init scaffold in standalone mode)
- `ADMIN_TELEGRAM_IDS` (optional comma-separated allowlist to show admin entrypoint in UI)

For `ENABLE_PUSH=true`, add standard Firebase platform files first:
- Android: `android/app/google-services.json`
- iOS: `ios/Runner/GoogleService-Info.plist`

## Run locally (web)

```bash
cd flutter_app
flutter create . --platforms=android,ios,web
flutter pub get
flutter run -d chrome \
  --dart-define=API_URL=http://localhost:8080 \
  --dart-define=BOT_USERNAME=YOUR_BOT_USERNAME \
  --dart-define=VK_APP_ID=YOUR_VK_APP_ID \
  --dart-define=AUTH_MODE=telegram_web \
  --dart-define=ADMIN_TELEGRAM_IDS=123456789
```

## Run locally (mobile)

```bash
cd flutter_app
flutter create . --platforms=android,ios,web
flutter pub get
flutter run -d android \
  --dart-define=API_URL=http://10.0.2.2:8080 \
  --dart-define=AUTH_MODE=standalone \
  --dart-define=STANDALONE_AUTH_URL=https://spacefestival.fun/api/auth/standalone \
  --dart-define=STANDALONE_REDIRECT_URI=gigme://auth \
  --dart-define=ENABLE_PUSH=false
```

(For iOS simulator/device use host reachable from device.)

## Build web for Telegram WebView

```bash
cd flutter_app
flutter pub get
flutter build web --release \
  --base-href / \
  --dart-define=API_URL=/api \
  --dart-define=BOT_USERNAME=YOUR_BOT_USERNAME \
  --dart-define=VK_APP_ID=YOUR_VK_APP_ID \
  --dart-define=AUTH_MODE=telegram_web
```

## Deploy alongside legacy frontend

The repo keeps legacy React `frontend/` untouched.

Production compose serves Flutter web:
- landing at `/`
- app at `/space_app`
- legacy React frontend remains in repo and can be started only via compose profile `legacy`

For Flutter build-time env in `infra/.env.prod`:
- `FLUTTER_API_URL`
- `FLUTTER_BOT_USERNAME`
- `FLUTTER_VK_APP_ID`
- `FLUTTER_AUTH_MODE`
- `FLUTTER_STANDALONE_AUTH_URL`
- `FLUTTER_STANDALONE_REDIRECT_URI`
- `FLUTTER_ENABLE_PUSH`
- `FLUTTER_ADMIN_TELEGRAM_IDS`

Use:
```bash
docker compose -f infra/docker-compose.prod.yml --env-file infra/.env.prod up -d --build
```

## Tests

```bash
cd flutter_app
flutter test
```

Included:
- unit tests: API client retry behavior, JSON model mapping
- widget tests: feed list, event card, profile summary card

## Standalone auth helper

Backend now serves helper endpoints:
- `GET /auth/standalone` - Telegram Login Widget page
- `POST /auth/standalone/exchange` - validates widget payload and returns `initData`

Use `STANDALONE_AUTH_URL` pointing to that helper URL (for prod behind Caddy: `https://<domain>/api/auth/standalone`).
Helper appends `initData` to `STANDALONE_REDIRECT_URI` and Flutter completes login via existing `POST /auth/telegram`.

For Telegram Login Widget to work in production:
- configure bot domain in BotFather (`/setdomain`)
- ensure mobile app handles your deep link (`STANDALONE_REDIRECT_URI`) on Android/iOS

Deep link setup (after `flutter create . --platforms=android,ios,web`):
- Android (`android/app/src/main/AndroidManifest.xml`): add intent-filter for your scheme, for example `gigme://auth`
- iOS (`ios/Runner/Info.plist`): add `CFBundleURLTypes` entry with scheme `gigme`

Minimal examples:

```xml
<!-- AndroidManifest.xml -->
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="gigme" android:host="auth" />
</intent-filter>
```

```xml
<!-- Info.plist -->
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>gigme</string>
    </array>
  </dict>
</array>
```

## Push token sync

When `AUTH_MODE=standalone` and `ENABLE_PUSH=true`, Flutter now syncs FCM token to backend endpoint:
- `POST /me/push-token`

## Admin in Flutter

`/admin` now includes:
- Users list + search + block/unblock + created-events viewer
- Broadcast create/start + history
- Parser sources + quick parse + parsed events import/reject/delete
