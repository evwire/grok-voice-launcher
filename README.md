# VoiceLauncher for Mac

**Say where you want to go. Your Mac takes you there.**

Open any app, chat, project or settings page on your Mac by voice. Built on [Hammerspoon](https://www.hammerspoon.org), works with any dictation app (Spokenly, VoiceInk, Wispr Flow, macOS Dictation or plain typing), and works with your own xAI API key, or any OpenAI-compatible API ([PROVIDERS.md](PROVIDERS.md)).

Say "Slack", "bluetooth", "my Claude project about pricing", or "Teams and calendar". VoiceLauncher understands loose, mis-transcribed or mixed-language speech and opens the right things, but **only things on your own list**. The model picks ids from your list and can't open anything else.

<!-- DEMO GIF PLACEHOLDER: record a ~15 s loop (hotkey → "bluetooth" → "my Claude pricing project" → "YouTube tab"),
     save it as docs/demo.gif (≤ 5 MB, ~1200 px wide), then replace this comment with:
     ![VoiceLauncher demo](docs/demo.gif) -->
> 🎬 **Demo GIF coming soon.** _(placeholder: `docs/demo.gif`)_

> VoiceLauncher is an independent open-source project by EVwire. It is **not affiliated with, endorsed by or sponsored by xAI or Wispr**. It works with their products through your own accounts and keys.

## How it works

```
Cmd+Shift+Space  ─┐
"Hey Siri,        ├─▶ small text box ─▶ you speak (any dictation app types into the box)
 Voice Launcher" ─┘                       │ ~1 s pause
                                          ▼
                     exact name/alias? ── yes ─▶ open it (offline, ~3 ms)
                                          │ no
                                          ▼
                     the model (your own xAI or other key) picks ids from ~/.voice-launcher/destinations.json
                                          ▼
                     open up to 4 destinations in order
```

**Chrome tabs.** Say **"YouTube tab"**, **"go to my Gmail tab"** or **"switch to the YT one"** and VoiceLauncher jumps to that already-open Google Chrome tab. It works across windows, displays and Chrome profiles. Common nicknames (YT, Gmail, Docs, Sheets, X, GH…) and words from tab titles match offline. Anything unclear goes to the model, along with a short list of your tabs. If Chrome isn't running or no tab fits, the normal destinations are used, so "YouTube tab" can still open a YouTube entry.

**Demo flow**
1. Press **Cmd+Shift+Space** (or say **"Hey Siri, Voice Launcher"** for hands-free).
2. Say **"bluetooth"**. System Settings comes to the front on the Bluetooth page.
3. Say **"open Slack and my dashboard"**. Slack opens, then Claude opens and clicks the pinned "Dashboard" item in its sidebar.

**Destination types**
- **Apps:** any app in /Applications.
- **Websites.**
- **System Settings pages,** brought to the front on the right page.
- **Claude projects and chats:** `claude://` links open in the Claude app.
- **ChatGPT projects:** these open in the browser.
- **Grok Bot chats:** `grokbot://` links.
- **Folders and macOS Shortcuts.**
- **Sidebar items with no link,** which VoiceLauncher clicks through Accessibility.
- **Open Chrome tabs** (no entry needed; see above).

See [`destinations.example.json`](destinations.example.json) for an example of each.

## Requirements
- macOS 13 or newer (tested on macOS 26; Apple Silicon recommended)
- [Hammerspoon](https://www.hammerspoon.org) (`brew install --cask hammerspoon`); the installer offers to install it
- An [xAI API key](https://console.x.ai), stored in your macOS Keychain. Exact names work without it. Prefer another model? Any OpenAI-compatible API (OpenAI, OpenRouter, Groq, a local Ollama) works: see [PROVIDERS.md](PROVIDERS.md).
- Optional: a dictation app for hands-free mode: [Spokenly](https://spokenly.app), [VoiceInk](https://tryvoiceink.com), [Wispr Flow](https://wisprflow.ai) or the built-in macOS Dictation (see "Settings" below). Any dictation or typing also works.

## Quick install
```bash
git clone https://github.com/evwire/grok-voice-launcher.git voicelauncher
cd voicelauncher
./install.sh
```
The installer:
- checks your Mac and backs up anything it touches;
- installs the Hammerspoon module;
- builds a starter list from your installed apps;
- sets Hammerspoon to start at login and loads the launcher;
- then asks you to add your xAI key at a hidden `security` prompt. The script never sees the key.

Next, do the few one-time steps in [SETUP-NOTES.md](SETUP-NOTES.md): Accessibility permission, API key, Wispr Flow, the Siri Shortcut, and (for tab switching) allowing Hammerspoon to control Google Chrome.

Options: `--languages "English, Spanish"`, `--rebuild-destinations`, `--no-autostart`, `--no-reload`, `--no-key`, `--yes`, `--uninstall`.

## Settings (optional, in `destinations.json`)
Next to `destinations`, two optional top-level settings change how VoiceLauncher works. They apply on the next command, and `status.txt` reports any mistake.

```json
{
  "provider": { "preset": "openai", "models": ["gpt-4.1-mini"] },
  "dictation": "spokenly",
  "destinations": [ … ]
}
```

- **`provider`**: which API handles loose requests. Leave it out for xAI. Details and safety rules: [PROVIDERS.md](PROVIDERS.md).
- **`dictation`**: what hands-free mode (`hammerspoon://voicelaunch`, "Hey Siri, Voice Launcher") starts:
  - `"spokenly"`: Spokenly's documented `spokenly://start` and `stop` links (optional `{"backend":"spokenly","modeId":"…"}`).
  - `{"backend":"voiceink","hotkey":{"mods":["ctrl","alt"],"key":"d"}}`: presses the toggle shortcut you set in VoiceInk.
  - `{"backend":"macos","hotkey":{"mods":["alt"],"key":"z"}}`: presses your custom macOS Dictation shortcut (Keyboard settings).
  - `"wispr"`: Wispr Flow's hands-free link. Wispr doesn't document it, so it could change. This is the default when Wispr Flow is installed.
  - `"none"`: opens the box and waits for you to dictate or type.

**Already installed under the old name?** Nothing changes for you. The rename is branding only: the config folder (`~/.voice-launcher`), the Hammerspoon module (`voice-launcher.lua`), the Keychain item (`xai-voice-launcher`) and the `hammerspoon://voicelaunch` URLs all keep their names, so `git pull && ./install.sh` keeps working.

## How it compares

Prices are from each vendor's own page, read 21 Oct 2026, and may change. Most of these are great dictation apps. VoiceLauncher is not a dictation app: it turns what you say into a *destination*, and it can sit on top of any of them.

| Product | What it is | Price | Difference from VoiceLauncher |
|---|---|---|---|
| **VoiceLauncher** | Voice → open apps, deep links, settings panes, Chrome tabs from your own allow-list | Free (MIT). You pay xAI (or your chosen provider) directly for fuzzy commands. | — |
| Raycast | Typed launcher with AI; dictation is in Pro since v2.0 | Free; Pro $96/yr | Launching is typed. It doesn't map a loose sentence to a Claude project, a settings pane or a tab. |
| Spokenly | Dictation with "Agentic Actions" (apps, sites, Shortcuts, shell commands) | Free local; Pro $9.99/mo or $99.99/yr | Actions are set up per mode and can run shell commands. VoiceLauncher only opens entries on your list, never a command. |
| Superwhisper | Dictation with AI modes | Free; Pro $8.49/mo, $84.99/yr, $249.99 lifetime | Dictation only. Can be your dictation app for VoiceLauncher. |
| VoiceInk | Local, open-source dictation | One-time licence from $25 | Dictation only. Can be your dictation app for VoiceLauncher. |
| Wispr Flow | Dictation; experimental Command Mode for editing and search | Free (2,000 words/week); Pro $15/user/mo | Command Mode edits text and searches; it isn't a personal launcher. |
| macOS Voice Control | Built-in command-based control | Free | Fixed commands, no fuzzy intent, no deep links into AI apps. |
| Talon | Scripted voice grammars for hands-free coding | Free; extras via Patreon | Very powerful, but you write the grammar and it takes hours to learn. |

## What it costs to run
- **Exact names and aliases:** free. They match on your Mac, offline, in about 3 ms.
- **Fuzzy commands** ("my pricing project and Slack"): one small request to the xAI API on your own key. The prompt is your destination names plus short descriptions (and up to 50 tab titles when tabs are involved), and the answer is a few ids, capped at 200 tokens.
- **Estimate:** with about 50 destinations that is roughly 1,000–3,000 input tokens and ~20 output tokens. At xAI's list price for `grok-4.20-0309-non-reasoning` ($1.25 per million input tokens, $2.50 per million output, docs.x.ai, read 21 Oct 2026) that's about **$0.001–0.004 per fuzzy command, or roughly $1–4 per 1,000**. Your actual bill depends on your list size and on xAI's current prices; check console.x.ai.

## FAQ
**Do I need Wispr Flow?** No. Any dictation works (macOS Dictation, Superwhisper, VoiceInk, Spokenly…), and so does typing. For hands-free mode, VoiceLauncher can start Spokenly (documented links), VoiceInk or macOS Dictation (your shortcut), or Wispr Flow (an undocumented link that could change).

**Do I need an xAI key?** Only for fuzzy requests. Without a key, exact names and aliases still work. You can also use OpenAI, OpenRouter, Groq or a local Ollama model instead ([PROVIDERS.md](PROVIDERS.md)).

**Can the AI open something I didn't approve?** No. The model may only return ids from your `destinations.json`; unknown ids are dropped, and it never produces URLs or shell commands. The worst case is opening the wrong item from your own list.

**What gets sent to xAI (or my provider)?** Only commands that don't match exactly, plus your destination names and descriptions (and truncated tab titles for tab requests). See [PRIVACY.md](PRIVACY.md).

**Is there a paid version?** The launcher is complete and free here. The optional **Pro Kit** adds a double-click guided installer, 126 ready-made destinations in 5 packs, setup guides for each dictation app, Raycast and Stream Deck hooks, a `vl` helper command and a quick-start guide. It contains no extra launcher features: all features are in this repo.

**Does it work on Intel Macs?** It targets macOS 13+. It has been tested on Apple Silicon with macOS 26; other setups are untested so far, so please open an issue if something breaks.

**Safari or Arc tabs?** Not yet. Tab switching is Chrome-only today.

**How do I add or rename destinations?** Edit `~/.voice-launcher/destinations.json` (changes apply on the next command), or ask a bot to do it (see below).

**Why does the folder still say `voice-launcher` / why is the repo called `grok-voice-launcher`?** Those are internal names kept so existing installs don't break. The repo may be renamed later; GitHub redirects old links.

**Is it affiliated with xAI or Wispr?** No. VoiceLauncher is independent. It works with their products through your own accounts.

**How do I uninstall?** `./install.sh --uninstall`. It backs up what it removes.

## Use with Grok Bot (optional)
This kit was built and battle-tested with Grok Bot, which can set it up and maintain it for you:
- **Install:** ask your bot to install VoiceLauncher on your Mac. It runs `install.sh`, then walks you through the steps only you can do (Accessibility, API key, Siri Shortcut).
- **Maintain by talking:** "add Figma", "rename my dashboard to just Dashboard", "add my Claude project X", "make 'bluetooth' open the Bluetooth page". The bot backs up, edits and validates `~/.voice-launcher/destinations.json`. Changes apply on your next command.
- **Find links for you:** the bot can look up Claude project ids and Grok Bot chat links on your Mac (read-only, ids and titles only) and suggest a short list for you to pick from.
- **Test without opening anything:** it puts phrases in `~/.voice-launcher/selftest.txt`, reloads, and reads `selftest-results.txt`.

Bots and humans should read [LESSONS.md](LESSONS.md) before changing anything. It lists every gotcha from the original build.

## Files
| File | Purpose |
|---|---|
| `install.sh` | Idempotent installer and uninstaller |
| `voice-launcher.lua` | Hammerspoon module (settings at the top) |
| `init.lua.snippet` | Block added to `~/.hammerspoon/init.lua` |
| `destinations.example.json` | One example of every entry type |
| `gen-destinations.js` | Builds a starter list from installed apps (read-only) |
| `com.USER.hammerspoon-autostart.plist` | Start-at-login template |
| `SETUP-NOTES.md` | Steps only you can do |
| `LESSONS.md` | Gotchas and fixes |
| `PROVIDERS.md` | Using OpenAI, OpenRouter, Groq, Ollama or a custom endpoint instead of xAI |
| `PRIVACY.md` / `TERMS.md` | Privacy notice and terms of use |
| `docs/index.html` | Landing page (static, no trackers) |
| `tests/tab-match-test.lua` | Offline test of the tab matching (`lua tests/tab-match-test.lua`) |
| `tests/settings-test.lua` | Offline test of the provider and dictation settings (`lua tests/settings-test.lua`) |

## Privacy
Full notice: [PRIVACY.md](PRIVACY.md). In short:
- We (EVwire) collect nothing. There is no server, account, analytics or telemetry.
- Your API key stays in the Keychain and is read at call time. It is never logged or written to a file. Requests go straight from your Mac to xAI (or the provider you set). Your xAI key is only ever sent to api.x.ai.
- The log records text lengths and ids, not what you said.
- Only exact-match misses are sent to the model, along with your destination names and descriptions.
- Chrome tabs are read only when Chrome is already running. Only titles and URLs are read: never page content, and no JavaScript is ever run in a page. The model gets at most 50 tabs, each with a title cut to 60 characters and the host plus first path segment (no full URLs, no query strings). The log records tab counts and ids such as `tab:2:5`, never titles.

## License
MIT © 2026 EVwire. See [LICENSE](LICENSE) and [TERMS.md](TERMS.md). Provided as is, without warranty.

"xAI" and "Grok" are trademarks of xAI; "Wispr Flow" is a trademark of its owner. Other product names are trademarks of their respective owners and are used only to describe compatibility.
