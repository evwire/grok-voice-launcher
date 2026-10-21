# VoiceLauncher for Mac – Privacy notice

_Last updated: 21 October 2026_

**Short version: we don't collect anything.** VoiceLauncher runs on your Mac. EVwire has no server, account system, analytics, telemetry or crash reporting for it, so we never see what you say, what you open, or your API key.

## What stays on your Mac
- **Your destination list** (`~/.voice-launcher/destinations.json`), status file and log. The log records text lengths, ids and timings, not your words (unless you turn on the `LOG_TEXT` debug setting yourself).
- **Your API key.** It is stored in your macOS Keychain (service `xai-voice-launcher`, or `voicelauncher-<provider>` for another provider). The xAI key is only ever sent to api.x.ai. The key is read only at the moment of a request, and never written to a file or logged.
- **Exact-name matches.** When what you say matches a name or alias on your list, it is opened locally. Nothing leaves your Mac.

## What is sent to xAI (or the provider you chose), and only when needed
When a command doesn't match exactly, VoiceLauncher sends one request **directly from your Mac to xAI's API (api.x.ai), using your own key**. If you set another provider ([PROVIDERS.md](PROVIDERS.md)), such as OpenAI, OpenRouter, Groq or a local Ollama, the same request goes directly to that provider instead. It never passes through an EVwire server. That request contains:
- the text of that command;
- the ids, names, aliases and descriptions on your destination list;
- if Chrome is running, up to 50 open tab titles (cut to 60 characters) with only the host and first path segment of each URL (no full URLs, no query strings, never page content).

xAI (or your chosen provider) handles that data under its own terms and privacy policy, under your account. For xAI, see https://x.ai/legal. With a local model (Ollama on `localhost`), nothing leaves your Mac at all.

## Other apps you choose to use
- **Dictation apps** such as Wispr Flow, macOS Dictation, Superwhisper, VoiceInk or Spokenly turn your speech into text before VoiceLauncher sees it. They have their own privacy policies.
- **Chrome tabs** are read through Apple Events only when Chrome is already running and only after you allow "Hammerspoon wants to control Google Chrome". You can switch this off with `TABS_ENABLED = false`.
- **Bot-assisted setup.** If you ask a bot (such as Grok Bot) to look up Claude project ids or chat links, that happens only when you ask, reads ids and titles only, and runs under that bot's own terms.

## Permissions
VoiceLauncher only gets the macOS permissions you grant to Hammerspoon yourself (Accessibility, and Automation for Chrome). You can revoke them at any time in System Settings → Privacy & Security.

## Removing everything
Run `./install.sh --uninstall`, delete `~/.voice-launcher`, and remove the key with
`security delete-generic-password -s xai-voice-launcher -a "$USER"`.

## Paid products
If you buy the Pro Kit or a setup session, the payment is handled by our payment provider / merchant of record ([PLACEHOLDER: Lemon Squeezy, Polar or Gumroad]), which processes your name, email and payment details under its own privacy policy. We receive your order details (name, email, what you bought) to deliver it and provide support, and nothing else.

## Contact
Maintainer: [PLACEHOLDER: Jaan's full name], EVwire – [PLACEHOLDER: contact email]

We'll update this page if anything changes and note the date at the top.
