FROM ghcr.io/cirruslabs/flutter:3.27.4 AS build

WORKDIR /app
COPY pubspec.yaml ./
RUN flutter config --enable-web
RUN flutter pub get
COPY . ./

ARG FLUTTER_API_URL=/api
ARG FLUTTER_BOT_USERNAME=
ARG FLUTTER_AUTH_MODE=telegram_web
ARG FLUTTER_STANDALONE_AUTH_URL=
ARG FLUTTER_STANDALONE_REDIRECT_URI=gigme://auth
ARG FLUTTER_ENABLE_PUSH=false
ARG FLUTTER_ADMIN_TELEGRAM_IDS=

RUN flutter build web --release \
  --base-href /app_flutter/ \
  --dart-define=API_URL=${FLUTTER_API_URL} \
  --dart-define=BOT_USERNAME=${FLUTTER_BOT_USERNAME} \
  --dart-define=AUTH_MODE=${FLUTTER_AUTH_MODE} \
  --dart-define=STANDALONE_AUTH_URL=${FLUTTER_STANDALONE_AUTH_URL} \
  --dart-define=STANDALONE_REDIRECT_URI=${FLUTTER_STANDALONE_REDIRECT_URI} \
  --dart-define=ENABLE_PUSH=${FLUTTER_ENABLE_PUSH} \
  --dart-define=ADMIN_TELEGRAM_IDS=${FLUTTER_ADMIN_TELEGRAM_IDS}

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html/app_flutter
EXPOSE 80
