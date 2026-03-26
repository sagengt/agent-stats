# Gemini CLI Integration Spec

## Authentication

### Token Storage (Priority Order)
1. **macOS Keychain** (primary)
   - Service: `gemini-cli-oauth` (OAuth token)
   - Service: `gemini-cli-api-key` (API key)
   - Accessed via `security find-generic-password -s "gemini-cli-oauth" -w`

2. **Legacy file** (fallback, auto-migrated)
   - Path: `~/.gemini/oauth_creds.json`
   - Format:
     ```json
     {
       "access_token": "ya29.xxx",
       "scope": "...",
       "token_type": "Bearer",
       "id_token": "eyJhbG...",
       "expiry_date": 1774427031155,
       "refresh_token": "1//0er6xxx"
     }
     ```

3. **Environment variable**
   - `GEMINI_API_KEY`

### Account Info
- File: `~/.gemini/google_accounts.json`
  ```json
  {
    "active": "user@gmail.com",
    "old": ["previous@example.com"]
  }
  ```

### Auth Settings
- File: `~/.gemini/settings.json`
  - `security.auth.selectedType`: `oauth-personal` | `USE_GEMINI` | `COMPUTE_ADC`

## Usage/Quota API

### Quota Endpoint
```
POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota
Authorization: Bearer {access_token}
Content-Type: application/json
```

### User Info Endpoint
```
GET https://www.googleapis.com/oauth2/v2/userinfo
Authorization: Bearer {access_token}
```
Response: `{ "email": "...", "name": "...", "picture": "..." }`

### Rate Limits
- No local usage log files
- Rate limits detected via HTTP 429 + `Retry-After` header
- Two error types: `TerminalQuotaError` (daily limit) and `RetryableQuotaError` (per-minute)

## Implementation Strategy

1. Try Keychain: `security find-generic-password -s "gemini-cli-oauth" -w`
2. Fallback: Read `~/.gemini/oauth_creds.json`
3. Use token to call `retrieveUserQuota` endpoint
4. Get email from `google_accounts.json` or JWT id_token
5. If API key only (no OAuth): limited to checking if key is valid

## OAuth Client Info
- Client ID/Secret: Read from Gemini CLI's own oauth_creds.json at runtime
- Scopes: `cloud-platform`, `userinfo.email`, `userinfo.profile`
- These are "installed application" public credentials distributed with the CLI
