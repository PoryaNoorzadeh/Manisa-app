# ADR-0002: Start as a modular monolith

Status: Accepted

## Decision

Manisa Core is implemented as one Go deployable with explicit internal module boundaries. We will not introduce microservices until operational scale or independent deployment requirements justify them.

## Rationale

The current team needs fast iteration, simple deployment, strong local reliability, and low operational overhead. Module boundaries preserve a future extraction path without paying distributed-system complexity now.
