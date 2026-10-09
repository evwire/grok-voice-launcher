#!/bin/bash
# Voice Launcher installer for macOS. Safe to run again (idempotent):
#  - backs up every file it touches to ~/.voice-launcher/backups/<timestamp>/
#  - never overwrites an existing destinations.json (use --rebuild-destinations to get a
#    fresh suggestion written next to it)
#  - never sees your xAI API key: it only checks that the Keychain item exists and, if you
#    agree, runs Apple's `security` tool which asks for the key at a hidden prompt.
#
# Usage: ./install.sh [--yes] [--no-autostart] [--no-reload] [--rebuild-destinations]
#                     [--languages "English, Spanish"] [--uninstall]
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HS_DIR="$HOME/.hammerspoon"
DATA_DIR="$HOME/.voice-launcher"
KEYCHAIN_SERVICE="xai-voice-launcher"
SAFE_USER="$(id -un | tr -cd 'A-Za-z0-9._-')"
LABEL="com.${SAFE_USER}.hammerspoon-autostart"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$DATA_DIR/backups/$STAMP"

ASSUME_YES=0; AUTOSTART=1; RELOAD=1; REBUILD=0; UNINSTALL=0; LANGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1 ;;
    --no-autostart) AUTOSTART=0 ;;
    --no-reload) RELOAD=0 ;;
    --rebuild-destinations) REBUILD=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --languages) shift; LANGS="${1:-}" ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }
ask() { # ask "question" -> 0 = yes. --yes answers yes; no terminal = no.
  if [ "$ASSUME_YES" = 1 ]; then return 0; fi
  if [ ! -t 0 ]; then return 1; fi
  local a; read -r -p "  ? $1 [y/N] " a; [[ "$a" =~ ^[Yy] ]]
}
backup() { # backup <file>: copy into this run's backup folder (once)
  [ -e "$1" ] || return 0
  mkdir -p "$BACKUP_DIR"
  local dest; dest="$BACKUP_DIR/$(basename "$1")"
  [ -e "$dest" ] || cp -p "$1" "$dest"
}
json_valid() { # json_valid <file>: uses JavaScriptCore via osascript (python may not exist)
  osascript -l JavaScript -e 'ObjC.import("Foundation");
    function run(a){var s=$.NSString.stringWithContentsOfFileEncodingError(a[0],4,null);
      if(s.isNil()) throw "unreadable"; var o=JSON.parse(s.js);
      if(!o.destinations||!o.destinations.length) throw "no destinations"; return "ok"}' "$1" >/dev/null 2>&1
}
find_app() { # find_app <bundle id> <name> -> path or empty
  local p
  for p in "/Applications/$2.app" "$HOME/Applications/$2.app"; do [ -d "$p" ] && { echo "$p"; return; }; done
  mdfind "kMDItemCFBundleIdentifier == '$1'" 2>/dev/null | head -n 1
}
hs_running() { pgrep -x Hammerspoon >/dev/null 2>&1; }
restart_hs() {
  if hs_running; then
    if grep -q 'voicelaunch-reload' "$HS_DIR/voice-launcher.lua.prev" 2>/dev/null; then
      open -g "hammerspoon://voicelaunch-reload"     # reload in place, no restart
    else
      pkill -x Hammerspoon || true; sleep 1.5; open -g -a Hammerspoon
    fi
  else
    open -g -a Hammerspoon
  fi
}

# ---------------------------------------------------------------- uninstall
if [ "$UNINSTALL" = 1 ]; then
  say "Uninstalling (backups go to $BACKUP_DIR)"
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  if [ -f "$PLIST" ]; then backup "$PLIST"; rm -f "$PLIST"; ok "removed LaunchAgent"; fi
  if [ -f "$HS_DIR/init.lua" ] && grep -q '>>> voice-launcher >>>' "$HS_DIR/init.lua"; then
    backup "$HS_DIR/init.lua"
    sed -i '' '/>>> voice-launcher >>>/,/<<< voice-launcher <<</d' "$HS_DIR/init.lua"
    ok "removed launcher block from init.lua"
  fi
  if [ -f "$HS_DIR/voice-launcher.lua" ]; then backup "$HS_DIR/voice-launcher.lua"; rm -f "$HS_DIR/voice-launcher.lua"; ok "removed voice-launcher.lua"; fi
  hs_running && { pkill -x Hammerspoon || true; sleep 1; open -g -a Hammerspoon; }
  ok "kept $DATA_DIR (your destinations). Delete it yourself if you want."
  ok "API key left in Keychain. Remove with: security delete-generic-password -s $KEYCHAIN_SERVICE -a \"\$USER\""
  exit 0
fi

# ---------------------------------------------------------------- checks
say "Checking this Mac"
[ "$(uname -s)" = "Darwin" ] || die "This installer is for macOS."
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MACOS_MAJOR" -ge 13 ]; then ok "macOS $(sw_vers -productVersion)"
else warn "macOS $(sw_vers -productVersion): System Settings pane links need macOS 13+; app/url launching still works."; fi
for f in voice-launcher.lua init.lua.snippet destinations.example.json com.USER.hammerspoon-autostart.plist gen-destinations.js; do
  [ -f "$KIT_DIR/$f" ] || die "Kit file missing: $f"
done

HS_APP="$(find_app org.hammerspoon.Hammerspoon Hammerspoon)"
if [ -z "$HS_APP" ]; then
  warn "Hammerspoon is not installed."
  if command -v brew >/dev/null 2>&1 && ask "Install it now with 'brew install --cask hammerspoon'?"; then
    brew install --cask hammerspoon
    HS_APP="$(find_app org.hammerspoon.Hammerspoon Hammerspoon)"
  fi
  [ -n "$HS_APP" ] || die "Install Hammerspoon (https://www.hammerspoon.org or 'brew install --cask hammerspoon') and run this again."
fi
ok "Hammerspoon: $HS_APP"

WISPR_APP="$(find_app com.electron.wispr-flow "Wispr Flow")"
[ -z "$WISPR_APP" ] && WISPR_APP="$(mdfind "kMDItemDisplayName == 'Wispr Flow*'c && kMDItemContentType == 'com.apple.application-bundle'" 2>/dev/null | head -n 1)"
if [ -n "$WISPR_APP" ]; then ok "Wispr Flow: $WISPR_APP"
else warn "Wispr Flow not found: hands-free mode will just open the box (use any dictation tool or type)."; fi

# ---------------------------------------------------------------- code
say "Installing launcher code"
mkdir -p "$HS_DIR" "$DATA_DIR"
TMP="$(mktemp -t voice-launcher)"; trap 'rm -f "$TMP" "$TMP.json"' EXIT
cp "$KIT_DIR/voice-launcher.lua" "$TMP"
if [ -z "$WISPR_APP" ]; then
  sed -i '' 's/^local DICTATION_SCHEME *= *"wispr-flow".*/local DICTATION_SCHEME          = nil  -- Wispr Flow not installed/' "$TMP"
fi
if [ -n "$LANGS" ]; then
  CLEAN_LANGS="$(printf '%s' "$LANGS" | tr -cd 'A-Za-z ,()-')"
  sed -i '' "s/^local LANGUAGES *= .*/local LANGUAGES        = \"${CLEAN_LANGS}\"/" "$TMP"
fi
rm -f "$HS_DIR/voice-launcher.lua.prev"
if [ -f "$HS_DIR/voice-launcher.lua" ]; then
  cp -p "$HS_DIR/voice-launcher.lua" "$HS_DIR/voice-launcher.lua.prev"  # used to choose reload method
fi
if [ -f "$HS_DIR/voice-launcher.lua" ] && cmp -s "$TMP" "$HS_DIR/voice-launcher.lua"; then
  ok "voice-launcher.lua already up to date"
else
  if [ -f "$HS_DIR/voice-launcher.lua" ]; then
    backup "$HS_DIR/voice-launcher.lua"
    warn "Replaced existing voice-launcher.lua (old copy in $BACKUP_DIR; re-apply any CONFIG edits you made)"
  fi
  cp "$TMP" "$HS_DIR/voice-launcher.lua"
  ok "installed $HS_DIR/voice-launcher.lua"
fi

if [ -f "$HS_DIR/init.lua" ] && grep -Eq "require ?\(? ?['\"]voice-launcher['\"]" "$HS_DIR/init.lua"; then
  ok "init.lua already loads the launcher"
else
  backup "$HS_DIR/init.lua"
  NEEDS_NL=0; [ -s "$HS_DIR/init.lua" ] && NEEDS_NL=1
  { [ "$NEEDS_NL" = 1 ] && echo; cat "$KIT_DIR/init.lua.snippet"; } >> "$HS_DIR/init.lua"
  ok "added launcher block to $HS_DIR/init.lua"
fi

# ---------------------------------------------------------------- destinations
say "Destinations"
DEST="$DATA_DIR/destinations.json"
if [ -f "$DEST" ] && [ "$REBUILD" = 0 ]; then
  if json_valid "$DEST"; then ok "kept your existing $DEST"
  else warn "$DEST exists but is not valid JSON or has no destinations. Fix it (backups are in $DATA_DIR/backups)."; fi
else
  osascript -l JavaScript "$KIT_DIR/gen-destinations.js" "$KIT_DIR/destinations.example.json" > "$TMP.json"
  json_valid "$TMP.json" || die "Generated destinations failed validation (nothing was changed)."
  N="$(grep -c '"id":' "$TMP.json" || true)"
  if [ -f "$DEST" ]; then
    cp "$TMP.json" "$DATA_DIR/destinations.generated.json"
    ok "wrote suggestion with $N entries to $DATA_DIR/destinations.generated.json (your file was not touched)"
  else
    cp "$TMP.json" "$DEST"
    ok "created $DEST with $N entries from your installed apps (edit names/aliases freely)"
  fi
fi
cp "$KIT_DIR/destinations.example.json" "$DATA_DIR/destinations.example.json"

# ---------------------------------------------------------------- API key (never echoed)
say "xAI API key (Keychain service '$KEYCHAIN_SERVICE')"
if security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$USER" >/dev/null 2>&1; then
  ok "key found in Keychain"
else
  warn "No key yet. Exact names/aliases still work offline; everything else needs the key."
  if [ -t 0 ] && ask "Add it now? You'll paste it at a hidden prompt (twice)."; then
    # -w as the LAST argument makes `security` prompt for the secret: it never appears in
    # the command line, shell history, process list or this script's output.
    if security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$USER" -l "Voice Launcher xAI key" -w; then
      ok "key saved"
    else
      warn "key not saved; see SETUP-NOTES.md"
    fi
  else
    echo "    Later, run:  security add-generic-password -U -s $KEYCHAIN_SERVICE -a \"\$USER\" -w"
  fi
fi

# ---------------------------------------------------------------- autostart
if [ "$AUTOSTART" = 1 ]; then
  say "Start Hammerspoon at login (LaunchAgent $LABEL)"
  mkdir -p "$HOME/Library/LaunchAgents"
  sed "s/__LABEL__/$LABEL/g" "$KIT_DIR/com.USER.hammerspoon-autostart.plist" > "$TMP"
  plutil -lint "$TMP" >/dev/null || die "LaunchAgent template is invalid"
  if [ -f "$PLIST" ] && cmp -s "$TMP" "$PLIST"; then
    ok "LaunchAgent already installed"
  else
    backup "$PLIST"
    cp "$TMP" "$PLIST"
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load -w "$PLIST" 2>/dev/null || true
    ok "installed $PLIST (macOS may show a 'background item added' notice; that's expected)"
  fi
fi

# ---------------------------------------------------------------- reload + verify
if [ "$RELOAD" = 1 ]; then
  say "Loading the launcher in Hammerspoon"
  BEFORE="$(stat -f %m "$DATA_DIR/status.txt" 2>/dev/null || echo 0)"
  restart_hs
  for _ in $(seq 1 20); do
    NOW="$(stat -f %m "$DATA_DIR/status.txt" 2>/dev/null || echo 0)"
    [ "$NOW" != "$BEFORE" ] && break
    sleep 0.5
  done
  if [ "${NOW:-0}" != "$BEFORE" ]; then
    ok "status: $(head -n 1 "$DATA_DIR/status.txt")"
    sed -n '2,$p' "$DATA_DIR/status.txt" | while read -r l; do warn "$l"; done
    grep -q 'accessibility=false' "$DATA_DIR/status.txt" && {
      warn "Hammerspoon has no Accessibility permission yet (needed for 'press' entries)."
      ask "Open the Accessibility settings page now?" && \
        open -b com.apple.systempreferences "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    }
  else
    warn "Hammerspoon didn't confirm loading. Open Hammerspoon, click its menu-bar icon → Console, and look for errors."
  fi
fi
rm -f "$HS_DIR/voice-launcher.lua.prev"

say "Done. Remaining one-time steps (Shortcut, Siri, Wispr) are in SETUP-NOTES.md"
[ -d "$BACKUP_DIR" ] && echo "    Backups of replaced files: $BACKUP_DIR"
exit 0
