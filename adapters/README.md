# Adapter SDK

New log sources should be described by a JSON adapter contract before a parser is added. Copy `adapter.schema.json`, provide one fixture under `adapters/fixtures/`, and add a focused test that proves:

1. timestamps are normalized to ISO-8601;
2. skill names are extracted only from explicit skill events or real `SKILL.md` reads;
3. session IDs and local paths can be redacted;
4. malformed records are skipped with a diagnostic instead of stopping the scan.

The collector remains responsible for filesystem discovery and privacy filtering. An adapter must never upload data or return raw transcript content.
