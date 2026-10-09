# Grok Voice Launcher

Open any app, chat, project or settings page on your Mac by voice.
**Hammerspoon + Wispr Flow + xAI Grok.**

Say "Slack", "bluetooth", "my Claude project about pricing", or "Teams and calendar". The launcher understands loose, mis-transcribed or mixed-language speech and opens the right things, but **only things on your own list**. The model picks ids from your list and can't open anything else.

## How it works

```
Cmd+Shift+Space  ─┐
"Hey Siri,        ├─▶ small text box ─▶ you speak (Wispr Flow types into the box)
 Voice Launcher" ─┘                       │ ~1 s pause
                                          ▼
                     exact name/alias? ── yes ─▶ open it (offline, ~3 ms)
                                          │ no
                                          ▼
                     xAI Grok picks ids from ~/.voice-launcher/destinations.json
                                          ▼
                     open up to 4 destinations in order
```

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
- **Sidebar items with no link,** which the launcher clicks through Accessibility.

See [`destinations.example.json`](destinations.example.json) for an example of each.

## Requirements
- macOS 13 or newer
- [Hammerspoon](https://www.hammerspoon.org) (`brew install --cask hammerspoon`); the installer offers to install it
- An [xAI API key](https://console.x.ai), stored in your macOS Keychain. Exact names work without it.
- Optional: [Wispr Flow](https://wisprflow.ai) for dictation and hands-free mode. Any dictation or typing also works.

## Quick install
```bash
git clone https://github.com/evwire/grok-voice-launcher.git
cd grok-voice-launcher
./install.sh
```
The installer:
- checks your Mac and backs up anything it touches;
- installs the Hammerspoon module;
- builds a starter list from your installed apps;
- sets Hammerspoon to start at login and loads the launcher;
- then asks you to add your xAI key at a hidden `security` prompt. The script never sees the key.

Next, do the few one-time steps in [SETUP-NOTES.md](SETUP-NOTES.md): Accessibility permission, API key, Wispr Flow, and the Siri Shortcut.

Options: `--languages "English, Spanish"`, `--rebuild-destinations`, `--no-autostart`, `--no-reload`, `--yes`, `--uninstall`.

## Use with Grok Bot
This kit was built and battle-tested with Grok Bot, which can set it up and maintain it for you:
- **Install:** ask your bot to install the voice launcher on your Mac. It runs `install.sh`, then walks you through the steps only you can do (Accessibility, API key, Siri Shortcut).
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

## Privacy
- Your API key stays in the Keychain and is read at call time. It is never logged or written to a file.
- The log records text lengths and ids, not what you said.
- Only exact-match misses are sent to xAI, along with your destination names and descriptions.

## License
MIT © 2026 EVwire
