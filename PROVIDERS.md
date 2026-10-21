# AI providers

VoiceLauncher sends **only commands that don't match a name exactly** to a chat-completions API, together with your destination names and descriptions. The model may only answer with ids from your list.

**xAI is the default** and needs nothing extra: put your key in the Keychain under `xai-voice-launcher` (see SETUP-NOTES.md). Any other **OpenAI-compatible** API works too. Add a `"provider"` object to the top of `~/.voice-launcher/destinations.json`. It applies on the next command, and `~/.voice-launcher/status.txt` shows the active provider and any setting error after a reload.

## Presets
| `preset` | Endpoint | Keychain service for the key |
|---|---|---|
| `xai` (default) | `https://api.x.ai/v1/chat/completions` | `xai-voice-launcher` |
| `openai` | `https://api.openai.com/v1/chat/completions` | `voicelauncher-openai` |
| `openrouter` | `https://openrouter.ai/api/v1/chat/completions` | `voicelauncher-openrouter` |
| `groq` | `https://api.groq.com/openai/v1/chat/completions` | `voicelauncher-groq` |
| `ollama` | `http://localhost:11434/v1/chat/completions` (on your Mac) | none |

For anything but xAI, give a `models` list. Model names change too often to hard-code; pick a fast, inexpensive chat model from your provider's list. If a model returns HTTP 400/404, the next one in the list is tried.

```json
{
  "provider": { "preset": "openai", "models": ["gpt-4.1-mini"] },
  "destinations": [ … ]
}
```

Store the key at a hidden prompt (never paste it anywhere else):

```bash
security add-generic-password -U -s voicelauncher-openai -a "$USER" -w
```

## Custom endpoint
```json
"provider": {
  "name": "My gateway",
  "apiUrl": "https://llm.example.com/v1/chat/completions",
  "keychainService": "voicelauncher-mygateway",
  "models": ["some-model"],
  "maxTokensParam": "max_tokens",
  "sendTemperature": true
}
```
- `maxTokensParam`: set it to `"max_completion_tokens"` for APIs that reject `max_tokens` (some newer OpenAI models).
- `sendTemperature`: set it to `false` for models that reject a `temperature` setting.
- A local server (Ollama, LM Studio…) on `http://localhost:<port>` or `http://127.0.0.1:<port>` can use `"keychainService": false`.

## Safety rules (enforced in code)
- Only `https://` endpoints are allowed, or plain `http://` to `localhost` / `127.0.0.1`.
- **Your xAI key (`xai-voice-launcher`) is only ever sent to `api.x.ai`.** Another endpoint needs its own Keychain service.
- Keychain service names may only contain letters, digits, `.`, `_` and `-`.
- URLs with `user@host` parts or odd ports are refused.
- Whatever the provider answers, only ids from your list can be opened.

Remove the `provider` block to go back to xAI. Your provider's own terms and privacy policy apply to what you send it.
