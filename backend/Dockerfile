FROM golang:1.22-alpine AS build

WORKDIR /app
RUN apk add --no-cache git
COPY go.mod ./
RUN go mod download
COPY . ./
RUN go build -o /bin/api ./cmd/api
RUN go build -o /bin/worker ./cmd/worker
RUN go build -o /bin/telegram-poller ./cmd/telegram-poller
RUN go build -o /bin/ticket-qr-backfill ./cmd/ticket-qr-backfill

FROM alpine:3.19
RUN adduser -D app
USER app
COPY --from=build /bin/api /bin/api
COPY --from=build /bin/worker /bin/worker
COPY --from=build /bin/telegram-poller /bin/telegram-poller
COPY --from=build /bin/ticket-qr-backfill /bin/ticket-qr-backfill
EXPOSE 8080
CMD ["/bin/api"]
