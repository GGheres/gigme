FROM golang:1.22-alpine AS build

WORKDIR /app
RUN apk add --no-cache git
COPY go.mod ./
RUN go mod download
COPY . ./
RUN go build -o /bin/api ./cmd/api
RUN go build -o /bin/worker ./cmd/worker

FROM alpine:3.19
RUN adduser -D app
USER app
COPY --from=build /bin/api /bin/api
COPY --from=build /bin/worker /bin/worker
EXPOSE 8080
CMD ["/bin/api"]
