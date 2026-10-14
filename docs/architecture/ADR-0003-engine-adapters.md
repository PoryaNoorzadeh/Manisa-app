# ADR-0003: External engines live behind adapters

Status: Accepted

## Decision

Matter Server, Home Assistant, OTBR, and future cloud services are infrastructure dependencies behind Manisa-owned interfaces.

Matter Node IDs and Home Assistant entity IDs are external bindings, never canonical Manisa device identifiers.

## Consequence

Changing or upgrading an engine must not force a mobile-app or domain-model rewrite.
