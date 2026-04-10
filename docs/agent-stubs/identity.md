# Identity (agent stub)

## Purpose

**Cryptographic identity** (master key, agent keys, device attestation, API keys `osk-v1`, revocation) secures the app, CLI, relay, and API access. All implementation files live under `Identity/`. [IDENTITY.md](../IDENTITY.md) is the product-level description.

## Key paths (`Packages/OsaurusCore/`)

- `Identity/` — master/agent/device keys, validators, stores, recovery

## Invariants / don’t break

- Key material handling (zeroization, Keychain, no accidental logging) is **critical**—follow existing patterns in `Identity/` and [SECURITY.md](../SECURITY.md).
- API key and signature formats are a **public contract** for integrations—treat changes as versioned protocol updates.

## See also

- [IDENTITY.md](../IDENTITY.md)
- [SECURITY.md](../SECURITY.md)
- [DEVELOPER_MAP.md](../DEVELOPER_MAP.md)
