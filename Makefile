.PHONY: run test fmt vet ci docker-up docker-down

run:
	go run ./cmd/manisa-core

test:
	go test ./...

fmt:
	gofmt -w .

vet:
	go vet ./...

ci: fmt vet test

docker-up:
	docker compose up --build

docker-down:
	docker compose down
