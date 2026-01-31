FROM node:20-alpine AS build

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . ./

ARG VITE_API_URL
ARG VITE_ADMIN_TELEGRAM_IDS
ARG VITE_LOG_LEVEL
ARG VITE_LOG_TO_SERVER
ARG VITE_LOG_ENDPOINT

ENV VITE_API_URL=$VITE_API_URL \
    VITE_ADMIN_TELEGRAM_IDS=$VITE_ADMIN_TELEGRAM_IDS \
    VITE_LOG_LEVEL=$VITE_LOG_LEVEL \
    VITE_LOG_TO_SERVER=$VITE_LOG_TO_SERVER \
    VITE_LOG_ENDPOINT=$VITE_LOG_ENDPOINT

RUN npm run build

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
