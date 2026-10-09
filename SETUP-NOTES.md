# Voice Launcher – steps only you can do

Run `./install.sh` first. It installs the code, builds your destination list from installed apps, sets up start-at-login and loads the launcher. These steps need you, because macOS asks a person to approve them or because they involve your own accounts.

## 1. Hammerspoon Accessibility permission
Needed for hotkeys to work reliably and for "click a sidebar item" (`press`) entries.
System Settings → Privacy & Security → Accessibility → turn on **Hammerspoon** (click + and add /Applications/Hammerspoon.app if it isn't listed). Then click the Hammerspoon menu-bar icon → Reload Config.
Optional: in Hammerspoon → Preferences, untick "Show dock icon".

## 2. xAI API key (stored in your Keychain, never in a file)
1. Create a key at https://console.x.ai (API Keys). A small prepaid credit is plenty, since each command uses a few hundred tokens.
2. In Terminal run (paste the key when asked; it's hidden and asked twice):
   ```
   security add-generic-password -U -s xai-voice-launcher -a "$USER" -w
   ```
   Don't put the key on the command line itself, and never paste it into a chat with an assistant.
3. To replace it later, run the same command. To remove it: `security delete-generic-password -s xai-voice-launcher -a "$USER"`.

Without a key, exact names and aliases still work. Only free-form requests ("open my work chat and the bluetooth thing") need Grok.

## 3. Wispr Flow (or another dictation app)
1. Install Wispr Flow (https://wisprflow.ai), sign in, and give it Microphone + Accessibility permissions when asked.
2. Learn its dictation key (default: hold **fn**). Press **Cmd+Shift+Space**, hold the key, say "Slack", release. The box runs on its own after a short pause.
3. Without Wispr, any dictation works (macOS Dictation, typing). Hands-free mode then just opens the box.

## 4. Hands-free with Siri (optional)
1. Open **Shortcuts** → **+** → name it **Voice Launcher** (not just "Launcher", because Siri hears that as "launch").
2. Add the action **Open URLs** with `hammerspoon://voicelaunch`.
3. Click ▶︎ once. When asked whether the Shortcut may open Hammerspoon, choose **Always Allow**.
4. Say **"Hey Siri, Voice Launcher"**, wait for the box ("Listening…"), then say where to go, e.g. "Bluetooth". It listens for about 6 seconds; tap fn to finish sooner.
5. Heads-up: anything the mic hears in those seconds is treated as the command, so speak right away.

## 5. Siri wake phrase (optional)
Apple only offers **"Hey Siri"** or just **"Siri"**: System Settings → Apple Intelligence & Siri → **Listen for**. (The launcher has a "Siri settings" entry that opens that page.) A fully custom wake word would need an always-listening app with the mic indicator permanently on. It isn't included.

## 6. Make it yours
Edit `~/.voice-launcher/destinations.json` (it applies on the next command). See `destinations.example.json` for every entry type: apps, websites, System Settings panes (`activate`), Claude projects/chats (`claude://claude.ai/project|chat/<uuid>`), ChatGPT projects (https link, opens the browser), Grok Bot chats, folders, Shortcuts, and `press` entries that click a sidebar item. Keep names short and unique, and check `~/.voice-launcher/status.txt` for collisions.

## Check / troubleshoot
- `cat ~/.voice-launcher/status.txt` shows whether it loaded, the hotkey, Accessibility, whether the key is present, and the destination count.
- Dry run without opening anything: put phrases (one per line) in `~/.voice-launcher/selftest.txt`, run `open -g hammerspoon://voicelaunch-reload`, then read `selftest-results.txt`.
- Something opened behind other windows: add `"activate": "<bundle id>"` to that url entry.
- Uninstall: `./install.sh --uninstall` (keeps your destinations and the Keychain key).
