FROM golang:1.27.1-alpine AS build
WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags='-s -w' -o /out/manisa-core ./cmd/manisa-core

FROM alpine:3.22
RUN addgroup -S manisa && adduser -S -G manisa manisa
WORKDIR /app
COPY --from=build /out/manisa-core /usr/local/bin/manisa-core
RUN mkdir -p /app/data && chown -R manisa:manisa /app
USER manisa
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/manisa-core"]
