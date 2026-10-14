# ADR-0001: Platform principles

Status: Accepted

## Decision

Manisa is local-first. Core device control and automation must continue without Internet access.

The mobile app integrates only with a versioned Manisa API. It never depends directly on Home Assistant, Matter Server, or protocol-specific identifiers.

Manisa owns the canonical home, room, device, capability, scene, automation, and identity model. Open-source engines remain replaceable behind adapters.
