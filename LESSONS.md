# Voice Launcher – lessons learned (read before changing anything)

Built and debugged on a real Mac (macOS 26, Hammerspoon, Wispr Flow, xAI Grok), Oct 2026.
Each item is a mistake we hit or a decision that worked. The kit already follows all of them.

## Architecture and safety
- **One launcher plus a list, not one app per destination.** The first attempt built 12 small separate `.app` launchers, one per destination. That was a dead end: hard to maintain, cluttered, and no way to understand free-form speech. It was replaced by a single Hammerspoon launcher that reads one destinations list.
- **Users edit by talking, not by editing JSON.** In practice the user just tells their maintainer bot ("add X", "rename Y to Z", "remove W"), and the bot backs up, edits and validates destinations.json. Design the bot skill and docs around that; hand-editing is the fallback.
- **Allow-list only.** Grok returns ids from destinations.json and nothing else; unknown ids are dropped, max 4 per command, opened ~0.8 s apart in the order given. Never let the model produce URLs or shell commands.
- **Exact name/alias match runs first, locally** (no network, ~3 ms). Matching lowercases, removes punctuation and strips leading filler words ("open", "the", "please", "go to", "show me"), so "Open the BT." == "bt". Don't add "open X" aliases; they're redundant.
- **destinations.json is re-read on every command.** Edits apply immediately; only Lua changes need a Hammerspoon reload.
- **Bot chat vs project with the same name**: when a Grok Bot chat and a Claude project share a name, give them distinct spoken names, e.g. "Claude X" / "X project" for the project and "X bot" for the chat, and never give both the bare "X".
- **Alias collisions are silent bugs.** The same name often exists in two apps (e.g. a project with the same name in Claude and in a Grok Bot chat, or a new alias like "open analytics" clashing with an existing "analytics" project). Prefix names by app ("Claude project: X", "ChatGPT X"), use descriptions, and check `status.txt`, which lists collisions on every load.
- **Keep spoken names short.** Users rename long entries (e.g. "Company dashboard" → "Dashboard"); keep the long forms as aliases.
- **Always back up and validate before editing** destinations.json or the Lua (timestamped copies; JSON parse check). install.sh does this automatically.

## API key and models
- Key lives in the macOS Keychain (service `xai-voice-launcher`, account `$USER`) and is read at call time with `/usr/bin/security … -w`. It is never logged, printed, stored in a file, or kept in a global. Fallback lookup without the account name.
- Add it only through `security add-generic-password -U -s xai-voice-launcher -a "$USER" -w` with `-w` LAST, so `security` prompts for it (nothing lands in shell history, ps, or logs). Agents must never ask users to paste the key into chat.
- Use a fast non-reasoning model (`grok-4.20-0309-non-reasoning`, fallback `grok-4.3`). Model names change, so they live in destinations.json `models`, and HTTP 400/404 falls through to the next model. 401/403 = bad key.
- Temperature 0, max_tokens 200, reply parsed with a `{...}` match, so stray prose around the JSON doesn't break it.
- Router prompt rule: a deep link to a chat/project opens its app by itself, so don't also open the plain app entry (otherwise the app opens twice or on the wrong screen).
- Tell the router which languages to expect (`LANGUAGES`); dictation of mixed-language speech is common.

## Triggers and UI
- **Cmd+Option+Space is taken by macOS** (Finder search). The kit tries Cmd+Shift+Space, then Ctrl+Opt+Cmd+Space, and uses the first free one.
- The text box auto-runs 1.2 s after the text stops changing, because dictation apps type or paste in bursts. Enter runs immediately.
- An agent working remotely can't press the hotkey or speak, so the user's own test is the real check. Say so.

## Hands-free ("Hey Siri, Voice Launcher")
- Siri's wake phrase can only be "Hey Siri" or "Siri" (System Settings → Apple Intelligence & Siri → Listen for). Custom wake words need an always-listening app, which keeps the orange mic dot on all the time.
- Name the Shortcut **"Voice Launcher"**, not "Launcher". Siri hears a lone "Launcher" as the verb "launch".
- The Shortcut only opens `hammerspoon://voicelaunch`. The first run asks to allow opening Hammerspoon: choose **Always Allow**.
- `hammerspoon://voicelaunch?q=<text>` runs a command directly (Shortcuts, Stream Deck, scripts).
- Wispr Flow has undocumented deep links `wispr-flow://start-hands-free` and `wispr-flow://stop-hands-free`. Open them with `open -g` so Wispr stays in the background and the launcher box keeps focus (the text has to land in the box).
- Listening window is 6 s (tap fn to finish early), then 6 s for transcription before the box closes. A trailing "done" is stripped.
- **Whatever the mic hears in that window gets executed**, including people talking or a TV in the room. In testing, nearby speech in another language was picked up and run. Tell users to speak right away.
- If Siri's panel steals focus from the box, raise `HANDSFREE_START_DELAY` (0.3 → 1.0 s).
- Closing the box while listening now also stops Wispr. Earlier, Wispr kept listening after the box closed.

## Opening things
- **System Settings panes**: `x-apple.systempreferences:<pane id>`. Opening the URL normally can leave the window *behind* other apps. Opening the URL and then focusing the app separately **resets it to General**. The fix: `open -b com.apple.systempreferences <url>` in one step (the `activate` field), plus one retry if it isn't frontmost after 1.5 s. Verified pane ids: Bluetooth `com.apple.BluetoothSettings`, Wi-Fi `com.apple.wifi-settings-extension`, Siri `com.apple.Siri-Settings.extension`, Sound `com.apple.Sound-Settings.extension`, Displays `com.apple.Displays-Settings.extension`, Network `com.apple.Network-Settings.extension`. Find more in `/System/Library/ExtensionKit/Extensions/*.appex` (CFBundleIdentifier).
- **Claude desktop**: `claude://claude.ai/project/<uuid>` and `claude://claude.ai/chat/<uuid>` open inside the app. `https://claude.ai/...` opens the browser instead.
- **Claude Cowork/live artifacts (pinned sidebar items) have no deep link.** Every URL form was ignored. Use a `press` entry: launch or focus Claude, find the element with that exact label through Accessibility, and AXPress it. Needed:
  - `AXManualAccessibility = true` on the app element (Electron apps hide their UI tree otherwise);
  - retry every 0.7 s up to a timeout (15 s), because a cold start takes time;
  - **a second click about 3 s after a cold start**, because Claude restores its last screen over the first click;
  - Hammerspoon Accessibility permission;
  - the label must match exactly (case-sensitive), e.g. "Acme Dashboard" will not match "ACME Dashboard". Renaming or unpinning the item breaks the entry.
- **ChatGPT projects**: the current (Codex-based) ChatGPT desktop app has no link that opens a project. `chatgpt://` variants were ignored, so use the `https://chatgpt.com/g/g-p-<id>/project` URL, which opens in the default browser.
- **Grok Bot chats**: `grokbot://app/v1/agent?id=<agent id>`. It opens the Grok Bot app by itself.
- Folders: `file:///full/path/`. Shortcuts: `shortcuts://run-shortcut?name=<url-encoded name>`.
- App entries use the app's name as shown in /Applications. `launchOrFocus` is used, with `open -a` as the fallback.

## Discovering links in local app data (privacy)
- Claude project ids and names can be found in the Claude desktop app's HTTP cache (`~/Library/Application Support/Claude/Cache/Cache_Data`). Read it **read-only** and extract only project names and ids (from `claude.ai/project/<uuid>` responses).
- Scan app caches **read-only** and extract only ids, titles and project ids. Never read chat content, cookies or tokens. If incidental text shows up in search output, don't keep or repeat it. Prefer targeted key lookups over broad greps.
- Claude's local cache (`~/Library/Application Support/Claude/`) only holds chats the app loaded recently, and it doesn't record which chats are starred. Different chats can share a title, so give them distinct names.
- **Don't bulk-add chats.** Show a short list (recent or important per project) and let the user pick. In practice they wanted almost none, just projects plus one dashboard.
- Testing deep links or clicks moves the user's real windows (switches the open chat, opens browser tabs). Warn them and list what changed.

## Running it
- **Hammerspoon needs Accessibility permission.** The user has to switch it on in System Settings → Privacy & Security → Accessibility (no script can grant it), then reload. Without it, hotkeys can be unreliable and `press` entries fail. `status.txt` shows `accessibility=true/false`.
- **Autostart**: a user LaunchAgent running `open -g -a Hammerspoon` at load. Adding a Login Item through System Events was blocked, because it needs an Apple Events (Automation) permission. macOS shows a "background item added" notice, which is expected.
- The `hs` CLI (from `require("hs.ipc")`) often **hangs when run from a remote or agent shell**, so don't depend on it. Use the file-based checks plus a reload or restart of Hammerspoon instead:
  - `~/.voice-launcher/status.txt` is written on every load and shows the hotkey, Accessibility state, number of destinations, whether the key is present (never its value), and alias collisions;
  - put phrases in `~/.voice-launcher/selftest.txt` and reload. Each one is resolved **without opening anything**, and the results go to `selftest-results.txt`.
- Reload: `open -g hammerspoon://voicelaunch-reload` (kit ≥ this version), or quit and relaunch Hammerspoon. Heavy testing once left Hammerspoon unresponsive, and a restart fixed it.
- The log (`voice-log.txt`) records lengths, ids, models and timings, **not what was said**. Set `LOG_TEXT = true` only for debugging.
