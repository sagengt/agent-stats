# Z.ai Integration Spec

## Overview
- Z.ai (chat.z.ai) is an AI platform by ZhipuAI (智谱AI)
- Models: GLM-5, GLM-4.7, GLM-4.6
- Offers "Z.ai Coding Plan" for AI coding assistance
- NOT related to Zed editor (zed.dev)

## Authentication
- **API Key** based authentication
- Key obtained from Z.ai dashboard
- Stored in macOS Keychain (AgentBar pattern: service `com.agentbar.apikeys`, account `zai`)
- For AgentStats: stored via CredentialStore with `authorizationHeader` field

### Auth Header Format
```
Authorization: Bearer <api_key>
```
Fallback (if Bearer fails with 401):
```
Authorization: <api_key>
```

## Usage/Quota API

### Endpoint
```
GET https://api.z.ai/api/monitor/usage/quota/limit
Authorization: Bearer <api_key>
Accept: application/json
Accept-Language: en-US,en
```

### Response Format
```json
{
  "code": 0,
  "success": true,
  "data": {
    "level": "pro",
    "limits": [
      {
        "type": "TOKENS_LIMIT",
        "usage": null,
        "currentValue": null,
        "percentage": 35.5,
        "nextResetTime": 1711234567890
      },
      {
        "type": "TIME_LIMIT",
        "usage": 1000,
        "currentValue": 350,
        "percentage": null,
        "nextResetTime": 1714567890000
      }
    ]
  }
}
```

### Limit Types

| Type | Description | Fields |
|------|-------------|--------|
| `TOKENS_LIMIT` | 5-hour prompt window | `percentage` (0-100), `nextResetTime` (epoch ms) |
| `TIME_LIMIT` | Monthly MCP request count | `currentValue`/`usage` (count), `nextResetTime` |

### Notes
- `nextResetTime` is in epoch milliseconds
- Minimum cache TTL: 60 seconds
- `percentage` is 0-100 scale
- When `percentage` is null, calculate from `currentValue / usage`

## Implementation Strategy

1. User enters API key via APIKeyInputView
2. Save key as `CredentialMaterial.authorizationHeader = "Bearer <key>"`
3. Call quota endpoint with Bearer token
4. Parse response into QuotaWindows:
   - TOKENS_LIMIT → "5 Hour" window with percentage
   - TIME_LIMIT → "Monthly" window with currentValue/usage ratio
5. If Bearer auth fails (401), retry with raw key
