# Configuration

App-level configuration constants.

## Guidelines

- **Secrets stay here.** API keys, client IDs, OAuth scopes — all in `GoogleCredentials.swift`.
- **No logic.** This folder contains only static constants and configuration values.
- **Never import these in Views.** Only Services should read configuration values.
- When adding a new OAuth scope, add it to `GoogleCredentials.scopes` and document why it's needed.

## Files

| File | Role |
|------|------|
| `GoogleCredentials.swift` | Google OAuth client ID, redirect URI, scopes |
