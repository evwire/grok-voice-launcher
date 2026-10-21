-- VoiceLauncher for Mac (Hammerspoon + any dictation app + your own xAI API key)
-- Internal names (voice-launcher.lua, ~/.voice-launcher, Keychain "xai-voice-launcher",
-- hammerspoon://voicelaunch) are kept on purpose so existing installs keep working.
--
-- Flow: hotkey (or "Hey Siri, Voice Launcher" -> hammerspoon://voicelaunch) opens a
-- one-line text box -> you dictate (Wispr Flow by default) -> after a short pause the
-- text is matched against ~/.voice-launcher/destinations.json. An exact name/alias match
-- opens locally (no network); otherwise Grok picks ids FROM THAT LIST ONLY. Nothing that
-- is not listed in destinations.json can ever be opened. The one addition: "YouTube tab",
-- "switch to my Gmail tab" switch to an ALREADY-OPEN Google Chrome tab (see "Chrome tabs").
--
-- Privacy: the xAI key is read from the macOS Keychain on each call, never logged or
-- stored. The log records lengths, ids and timings, never what you said (unless you set
-- LOG_TEXT = true while debugging).
--
-- Install: copy to ~/.hammerspoon/voice-launcher.lua and add to ~/.hammerspoon/init.lua:
--   require("hs.ipc")
--   require("voice-launcher")

---------------------------------------------------------------------------------------
-- CONFIG (edit here; models/routerNotes can also be set in destinations.json)
---------------------------------------------------------------------------------------
local HOME             = os.getenv("HOME")
local DATA_DIR         = HOME .. "/.voice-launcher"
local DEST_FILE        = DATA_DIR .. "/destinations.json"
local LOG_FILE         = DATA_DIR .. "/voice-log.txt"
local STATUS_FILE      = DATA_DIR .. "/status.txt"
local SELFTEST_FILE    = DATA_DIR .. "/selftest.txt"         -- phrases to dry-run on load
local SELFTEST_RESULTS = DATA_DIR .. "/selftest-results.txt"

local KEYCHAIN_SERVICE = "xai-voice-launcher"               -- account = $USER
local API_URL          = "https://api.x.ai/v1/chat/completions"
-- Tried in order; on HTTP 400/404 (model renamed/retired) the next one is used.
-- A fast non-reasoning model keeps the round trip well under a second.
local DEFAULT_MODELS   = { "grok-4.20-0309-non-reasoning", "grok-4.3" }
local REQUEST_TIMEOUT  = 12        -- seconds before the alert says the API is not answering

-- Languages the router should expect (dictation may mix them). Plain text for the prompt.
local LANGUAGES        = "English (or any other language the user speaks)"

-- First free hotkey wins. Cmd+Option+Space is skipped: macOS uses it for Finder search.
local HOTKEYS = {
  { { "cmd", "shift" }, "space" },
  { { "ctrl", "alt", "cmd" }, "space" },
}

local AUTO_SUBMIT_SECONDS = 1.2    -- run this long after the text stops changing (Enter = now)
local MAX_DESTINATIONS    = 4      -- never open more than this many things per command
local OPEN_STAGGER        = 0.8    -- seconds between opening several destinations

-- Hands-free (hammerspoon://voicelaunch). Set DICTATION_SCHEME = nil if you don't use
-- Wispr Flow; the box then just opens and waits for any dictation/typing.
local DICTATION_SCHEME          = "wispr-flow"   -- wispr-flow://start-hands-free / stop-hands-free
local HANDSFREE_START_DELAY     = 0.3   -- raise to ~1.0 if Siri's panel steals focus from the box
local HANDSFREE_MAX_SECONDS     = 6     -- stop listening after this long (tap fn to end early)
local HANDSFREE_TEXT_WAIT       = 6     -- then give transcription this long before closing
local DONE_WORDS                = { "done" }  -- trailing "done" (said to finish) is removed

-- Words stripped from the START of a command before exact matching ("open slack" == "slack").
local LEADING_FILLERS = { "please", "open", "launch", "go to", "show me", "show", "the" }

local LOG_TEXT = false   -- true = also log what was said (debug only; off by default)

---------------------------------------------------------------------------------------
require("hs.ipc")
local M = {}
local log = hs.logger.new("voicelaunch", "info")

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function appendFile(path, line)
  local f = io.open(path, "a")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. line .. "\n"); f:close() end
end
local function writeFile(path, s)
  local f = io.open(path, "w"); if f then f:write(s); f:close() end
end
local function vlog(msg) appendFile(LOG_FILE, msg) end
local function said(text) -- what goes into the log for a piece of user speech
  return LOG_TEXT and ("\"" .. text .. "\"") or ("(" .. #text .. " chars)")
end

local function normalize(s)
  s = (s or ""):lower():gsub("[%p]", " "):gsub("%s+", " ")
  s = trim(s)
  local changed = true
  while changed do
    changed = false
    for _, w in ipairs(LEADING_FILLERS) do
      local rest = s:match("^" .. w:gsub("%p", "%%%0") .. "%s+(.+)$")
      if rest then s = trim(rest); changed = true end
    end
  end
  return s
end

---------------------------------------------------------------------------------------
-- Destinations (re-read on every command, so edits apply without a reload)
---------------------------------------------------------------------------------------
local VALID_TYPES = { url = true, app = true }

local function loadConfig()
  local ok, data = pcall(hs.json.read, DEST_FILE)
  if not ok or type(data) ~= "table" or type(data.destinations) ~= "table" then
    return nil, "can't read " .. DEST_FILE .. " (missing or invalid JSON)"
  end
  local byId, list, names, collisions = {}, {}, {}, {}
  for _, d in ipairs(data.destinations) do
    if type(d) == "table" and type(d.id) == "string" and VALID_TYPES[d.type]
       and type(d.value) == "string" and d.value ~= "" and not d.disabled and not byId[d.id] then
      byId[d.id] = d
      table.insert(list, d)
      local all = { d.name or d.id }
      if type(d.aliases) == "table" then for _, a in ipairs(d.aliases) do all[#all + 1] = a end end
      for _, n in ipairs(all) do
        local k = type(n) == "string" and normalize(n) or ""
        if k ~= "" then
          if names[k] and names[k] ~= d then
            collisions[#collisions + 1] = k .. " (" .. names[k].id .. " vs " .. d.id .. ")"
          else
            names[k] = d -- first entry wins on a clash
          end
        end
      end
    end
  end
  local models = (type(data.models) == "table" and #data.models > 0) and data.models or DEFAULT_MODELS
  return { byId = byId, list = list, names = names, collisions = collisions, models = models,
           routerNotes = type(data.routerNotes) == "string" and data.routerNotes or nil }
end

---------------------------------------------------------------------------------------
-- xAI key from Keychain (never printed, logged or kept in a global)
---------------------------------------------------------------------------------------
local function getKey()
  local user = (os.getenv("USER") or ""):gsub("[^%w%._%-]", "")
  local cmd = "/usr/bin/security find-generic-password -s '" .. KEYCHAIN_SERVICE .. "'"
  local out, ok = hs.execute(cmd .. " -a '" .. user .. "' -w 2>/dev/null")
  if not ok or trim(out) == "" then out, ok = hs.execute(cmd .. " -w 2>/dev/null") end
  local k = ok and trim(out) or ""
  return k ~= "" and k or nil
end

---------------------------------------------------------------------------------------
-- Grok routing
---------------------------------------------------------------------------------------
local function buildMessages(cfg, text)
  local lines = {}
  for _, d in ipairs(cfg.list) do
    local extra = {}
    if type(d.description) == "string" and d.description ~= "" then extra[#extra + 1] = d.description end
    if type(d.aliases) == "table" and #d.aliases > 0 then
      extra[#extra + 1] = "also called: " .. table.concat(d.aliases, ", ")
    end
    lines[#lines + 1] = string.format("- id=%s | %s%s", d.id, d.name or d.id,
      #extra > 0 and (" | " .. table.concat(extra, " | ")) or "")
  end
  local system = "You are a launcher router. The user dictated a short spoken command via speech-to-text; " ..
    "it may contain mis-transcriptions and may be in " .. LANGUAGES .. ". Decide which destination(s) " ..
    "from the list they want opened.\nRules:\n" ..
    "- Reply with ONLY a JSON object like {\"ids\":[\"some-id\"]} and nothing else.\n" ..
    "- Use only ids from the list, spelled exactly as written.\n" ..
    "- If they ask for several things, list them in the order they should open (an app before a chat or project inside it).\n" ..
    "- A deep link to a chat or project inside an app opens that app by itself, so do not also add the plain app entry.\n" ..
    "- When the same name exists in several apps, prefer the app the user mentions; if none is mentioned, pick the entry whose name matches best.\n" ..
    "- If you are unsure or nothing matches, reply {\"ids\":[]}.\n" ..
    (cfg.routerNotes and ("- " .. cfg.routerNotes .. "\n") or "") ..
    "\nDestinations:\n" .. table.concat(lines, "\n")
  return { { role = "system", content = system }, { role = "user", content = text } }
end

local function parseIds(content, cfg)
  if type(content) ~= "string" then return {} end
  local js = content:match("%b{}")
  if not js then return {} end
  local ok, obj = pcall(hs.json.decode, js)
  if not ok or type(obj) ~= "table" or type(obj.ids) ~= "table" then return {} end
  local out, seen = {}, {}
  for _, id in ipairs(obj.ids) do
    if type(id) == "string" and cfg.byId[id] and not seen[id] then
      seen[id] = true
      out[#out + 1] = cfg.byId[id]
    end
    if #out >= MAX_DESTINATIONS then break end
  end
  for _, d in ipairs(out) do if d.type == "tab" then return { d } end end
  return out
end

local TAB_LOG = LOG_FILE
---------------------------------------------------------------------------------------
-- Chrome tabs: "YouTube tab", "go to my Gmail tab", "switch to the YT one".
-- Lists open Google Chrome tabs (all windows, all profiles) with AppleScript, ONLY when
-- Chrome is already running. Reads tab titles and URLs only: never page content, never
-- runs JavaScript in pages. Grok only ever sees truncated titles + host/first path segment.
-- First use: macOS asks "Hammerspoon wants to control Google Chrome" -> click Allow
-- (System Settings > Privacy & Security > Automation > Hammerspoon > Google Chrome).
---------------------------------------------------------------------------------------
local TABS_ENABLED       = true
local CHROME_BUNDLE      = "com.google.Chrome"
local TAB_LIMIT_FOR_GROK = 50     -- at most this many tabs are offered to Grok
local TAB_TITLE_MAX      = 60     -- titles are cut to this many characters for Grok

-- [tabs-pure-begin] (plain Lua, no hs.*: unit-testable outside Hammerspoon)
local TAB = {}
-- words that mean "an open tab" (any language you dictate in)
TAB.INTENT_WORDS   = { "tab", "tabs", "vaheleht", "vahelehte", "vahelehele", "vahekaart" }
TAB.INTENT_PHRASES = { "switch to", "switch back to", "go back to", "jump to" }
-- removed from the query before matching tab titles / hosts
TAB.FILLERS = { "please", "open", "go", "to", "back", "switch", "jump", "over", "my", "the", "a",
  "that", "this", "one", "tab", "tabs", "chrome", "in", "on", "page", "window", "show", "me",
  "vaheleht", "vahelehte", "vahelehele", "vahekaart", "mine", "ava", "minu" }
-- spoken nickname -> fragment of "host/path" (host without www.)
TAB.NICKNAMES = {
  yt = "youtube.com", youtube = "youtube.com", ["you tube"] = "youtube.com",
  gmail = "mail.google.com", ["g mail"] = "mail.google.com", ["google mail"] = "mail.google.com",
  drive = "drive.google.com", gdrive = "drive.google.com", ["google drive"] = "drive.google.com",
  docs = "docs.google.com/document", ["google docs"] = "docs.google.com/document",
  sheets = "docs.google.com/spreadsheets", ["google sheets"] = "docs.google.com/spreadsheets",
  slides = "docs.google.com/presentation", ["google slides"] = "docs.google.com/presentation",
  calendar = "calendar.google.com", gcal = "calendar.google.com", ["google calendar"] = "calendar.google.com",
  maps = "google.com/maps", ["google maps"] = "google.com/maps",
  analytics = "analytics.google.com", ["google analytics"] = "analytics.google.com", ga = "analytics.google.com",
  ["search console"] = "search.google.com/search-console", gsc = "search.google.com/search-console",
  x = "x.com", twitter = "x.com", gh = "github.com", github = "github.com",
  linkedin = "linkedin.com", ["linked in"] = "linkedin.com", fb = "facebook.com", facebook = "facebook.com",
  ig = "instagram.com", insta = "instagram.com", instagram = "instagram.com", reddit = "reddit.com",
  chatgpt = "chatgpt.com", ["chat gpt"] = "chatgpt.com", gpt = "chatgpt.com", claude = "claude.ai",
  grok = "grok.com", gemini = "gemini.google.com", notion = "notion.so", figma = "figma.com",
  wiki = "wikipedia.org", wikipedia = "wikipedia.org", netflix = "netflix.com",
}

local function tnorm(s)
  s = (s or ""):lower():gsub("[%p]", " "):gsub("%s+", " ")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function TAB.hostPath(url) -- "https://www.youtube.com/watch?v=x" -> "youtube.com", "/watch"
  local host, path = (url or ""):match("^%a[%w+.-]*://([^/?#]*)([^?#]*)")
  if not host then return "", "" end
  host = host:lower():gsub("^www%.", ""):gsub(":%d+$", "")
  return host, (path:match("^/[^/]*") or "")
end

function TAB.intent(text)
  local t = " " .. tnorm(text) .. " "
  for _, w in ipairs(TAB.INTENT_WORDS) do if t:find(" " .. w .. " ", 1, true) then return true end end
  for _, p in ipairs(TAB.INTENT_PHRASES) do if t:find(" " .. p .. " ", 1, true) then return true end end
  return false
end

function TAB.query(text) -- "go to my Gmail tab" -> "gmail"
  local fill = {}
  for _, w in ipairs(TAB.FILLERS) do fill[w] = true end
  local out = {}
  for w in tnorm(text):gmatch("%S+") do if not fill[w] then out[#out + 1] = w end end
  return table.concat(out, " ")
end

local function score(q, t)
  local host, path = TAB.hostPath(t.url)
  local hp = host .. path
  local nick = TAB.NICKNAMES[q]
  if nick then return hp:find(nick, 1, true) and 100 or 0 end
  local title = tnorm(t.title)
  local qs = q:gsub(" ", "")
  if title == q then return 95 end
  for label in host:gmatch("[^.]+") do
    if #qs >= 2 and label == qs and label ~= "com" and label ~= "www" then return 90 end
  end
  if (" " .. title .. " "):find(" " .. q .. " ", 1, true) then return 80 end
  if #qs >= 4 and host:find(qs, 1, true) then return 70 end
  local words, n, hits = {}, 0, 0
  for w in title:gmatch("%S+") do words[w] = true end
  for w in q:gmatch("%S+") do n = n + 1; if words[w] or host:find(w, 1, true) then hits = hits + 1 end end
  if n >= 2 and hits == n then return 60 end
  return 0
end

-- tabs: list in Chrome's window order (front window first) with fields
-- w, t (indexes), wid, tid (ids), title, url, active (bool).
-- Returns tab, "ok" | nil, "none" | nil, "ambiguous"
function TAB.match(query, tabs)
  local q = tnorm(query)
  if q == "" then return nil, "none" end
  local best, cands = 0, {}
  for _, t in ipairs(tabs or {}) do
    local s = score(q, t)
    if s > best then best, cands = s, { t } elseif s == best and s > 0 then cands[#cands + 1] = t end
  end
  if best < 60 then return nil, "none" end
  local host1 = TAB.hostPath(cands[1].url)
  for _, c in ipairs(cands) do -- tie across different sites: let Grok decide
    if TAB.hostPath(c.url) ~= host1 then return nil, "ambiguous" end
  end
  -- same site in several tabs: frontmost window that has one; in it, its active tab if it matches
  for _, c in ipairs(cands) do if c.w == cands[1].w and c.active then return c, "ok" end end
  return cands[1], "ok"
end

function TAB.grokLines(tabs, maxN, titleMax) -- "- id=tab:1:3 | <title> | youtube.com/watch"
  local lines = {}
  for i, t in ipairs(tabs or {}) do
    if i > maxN then break end
    local host, path = TAB.hostPath(t.url)
    local title = (t.title or ""):gsub("[%c|]", " ")
    if #title > titleMax then title = title:sub(1, titleMax):gsub("[\128-\191]*$", ""):gsub("[\192-\255]$", "") .. "…" end
    lines[#lines + 1] = string.format("- id=tab:%d:%d | %s | %s%s", t.w, t.t, title, host, path)
  end
  return lines
end
-- [tabs-pure-end]

local function tlog(msg)
  local f = io.open(TAB_LOG, "a")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. msg .. "\n"); f:close() end
end

local US, RS = string.char(31), string.char(30)
local LIST_TABS = [[
tell application id "com.google.Chrome"
  set wids to id of every window
  set acts to active tab index of every window
  set tids to id of every tab of every window
  set tts to title of every tab of every window
  set tus to URL of every tab of every window
end tell
set US to ASCII character 31
set recs to {}
repeat with wi from 1 to count of wids
  set tl to item wi of tids
  repeat with ti from 1 to count of tl
    try
      set end of recs to (wi as text) & US & ti & US & (item wi of wids) & US & (item ti of tl) & US & (item wi of acts) & US & (item ti of item wi of tts as text) & US & (item ti of item wi of tus as text)
    end try
  end repeat
end repeat
set AppleScript's text item delimiters to (ASCII character 30)
set out to recs as text
set AppleScript's text item delimiters to ""
return out]]

-- nil when Chrome isn't running / not allowed; otherwise a (possibly empty) list
function TAB.list()
  if not TABS_ENABLED or not hs.application.get(CHROME_BUNDLE) then return nil end
  local t0 = hs.timer.secondsSinceEpoch()
  local ok, out, desc = hs.osascript.applescript(LIST_TABS)
  if not ok or type(out) ~= "string" then
    local code = type(desc) == "table" and desc.NSAppleScriptErrorNumber
    tlog("tabs: listing failed" .. (code and (" (error " .. tostring(code) .. (code == -1743 and ", Automation not allowed" or "") .. ")") or ""))
    if code == -1743 then
      hs.alert.show("Allow Hammerspoon to control Google Chrome: System Settings › Privacy & Security › Automation", 4)
    end
    return nil
  end
  local tabs = {}
  for rec in out:gmatch("([^" .. RS .. "]+)") do
    local f = {}
    for v in (rec .. US):gmatch("(.-)" .. US) do f[#f + 1] = v end
    if #f >= 7 then
      tabs[#tabs + 1] = { w = tonumber(f[1]), t = tonumber(f[2]), wid = f[3], tid = f[4],
        active = (f[5] == f[2]), title = f[6], url = table.concat(f, US, 7) }
    end
  end
  tlog(string.format("tabs: listed %d in %dms", #tabs, math.floor((hs.timer.secondsSinceEpoch() - t0) * 1000)))
  return tabs
end

function TAB.dest(t)
  return { id = string.format("tab:%d:%d", t.w, t.t), type = "tab", tab = t,
    name = "tab: " .. ((#t.title > 40) and (t.title:sub(1, 40):gsub("[\128-\191]*$", ""):gsub("[\192-\255]$", "") .. "…") or t.title) }
end

function TAB.switch(t)
  -- Chrome may report ids as text or numbers: compare them as text
  local src = string.format([[
tell application id "com.google.Chrome"
  set wl to id of every window
  set w to missing value
  repeat with k from 1 to count of wl
    if (item k of wl as text) is "%s" then set w to window k
  end repeat
  if w is missing value then return "gone"
  set tl to id of every tab of w
  set found to 0
  repeat with i from 1 to count of tl
    if (item i of tl as text) is "%s" then set found to i
  end repeat
  if found is 0 then return "gone"
  if minimized of w then set minimized of w to false
  set active tab index of w to found
  set index of w to 1
  set AppleScript's text item delimiters to ","
  set b to (bounds of w) as text
  set AppleScript's text item delimiters to ""
  return "ok," & b
end tell]], tostring(t.wid):gsub("[^%w%.%-]", ""), (tostring(t.tid):gsub("[^%w%.%-]", "")))
  local ok, res = hs.osascript.applescript(src)
  local status = ok and type(res) == "string" and res:match("^(%a+)") or "error"
  tlog("tab switch tab:" .. t.w .. ":" .. t.t .. " -> " .. status)
  if status ~= "ok" then hs.alert.show("That Chrome tab is gone", 2); return end
  res = res:gsub("\226\136\146", "-") -- AppleScript may write negatives with U+2212
  local x1, y1, x2, y2 = res:match("^ok,(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)")
  hs.timer.doAfter(0.15, function()
    -- bring THAT window forward (other display / Space / profile): find it by its frame,
    -- which AppleScript and Hammerspoon both give in top-left-origin screen points
    local app = hs.application.get(CHROME_BUNDLE)
    if not app then return end
    if x1 then
      x1, y1, x2, y2 = tonumber(x1), tonumber(y1), tonumber(x2), tonumber(y2)
      for _, win in ipairs(app:allWindows()) do
        local fr = win:frame()
        if math.abs(fr.x - x1) <= 3 and math.abs(fr.y - y1) <= 3 and math.abs(fr.w - (x2 - x1)) <= 3
           and math.abs(fr.h - (y2 - y1)) <= 3 then
          win:focus(); return
        end
      end
    end
    local want = (t.title or ""):sub(1, 30) -- fallback: window title = its active tab's title
    for _, win in ipairs(app:allWindows()) do
      if want ~= "" and (win:title() or ""):sub(1, #want) == want then win:focus(); return end
    end
    app:activate()
  end)
end

local function addTabChoices(messages, tabs)
  if not tabs or #tabs == 0 then return end
  messages[1].content = messages[1].content .. "\n\nOpen Google Chrome tabs (extra choices). Pick ONE tab id, " ..
    "alone, when the user wants to switch to an already-open tab (they say tab, switch to, go back to, " ..
    "\"the X one\"), or when no destination fits but one tab clearly does. Otherwise prefer destinations.\n" ..
    table.concat(TAB.grokLines(tabs, TAB_LIMIT_FOR_GROK, TAB_TITLE_MAX), "\n")
end

-- callback(dests, err, via) ; via = "local" or the model name
function M.resolve(text, callback)
  local cfg, err = loadConfig()
  if not cfg then return callback(nil, err) end
  local function exact(s) return cfg.names[normalize(s)] end
  local hit = exact(text)
  if hit then return callback({ hit }, nil, "local") end -- exact name/alias: no API call
  -- Chrome tabs: listed only if Chrome is running; "YouTube tab" etc. switch locally
  local tabs = TAB.list()
  if TAB.intent(text) then
    local q = TAB.query(text)
    local why = "none"
    if tabs then
      local t; t, why = TAB.match(q, tabs)
      if t then return callback({ TAB.dest(t) }, nil, "local-tab") end
    end
    local h = (why == "none" and q ~= "") and exact(q) -- no such tab: "YouTube tab" -> YouTube destination
    if h then return callback({ h }, nil, "local") end
  end
  for _, t in ipairs(tabs or {}) do cfg.byId["tab:" .. t.w .. ":" .. t.t] = TAB.dest(t) end

  local key = getKey()
  if not key then
    return callback(nil, "no xAI key in Keychain (service " .. KEYCHAIN_SERVICE .. ")")
  end
  local headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. key }
  key = nil
  local messages = buildMessages(cfg, text)
  addTabChoices(messages, tabs)
  local done = false
  local watchdog = hs.timer.doAfter(REQUEST_TIMEOUT, function()
    if not done then done = true; callback(nil, "xAI API not answering") end
  end)
  local function try(i)
    local model = cfg.models[i]
    local body = hs.json.encode({ model = model, messages = messages, temperature = 0, max_tokens = 200 })
    hs.http.asyncPost(API_URL, body, headers, function(status, resp)
      if done then return end
      if status == 200 then
        done = true; watchdog:stop()
        local ok, obj = pcall(hs.json.decode, resp or "")
        local content = ok and type(obj) == "table" and obj.choices and obj.choices[1]
          and obj.choices[1].message and obj.choices[1].message.content
        callback(parseIds(content, cfg), nil, model)
      elseif (status == 400 or status == 404) and i < #cfg.models then
        log.w("model " .. tostring(model) .. " returned HTTP " .. tostring(status) .. ", trying next")
        vlog("model " .. tostring(model) .. " HTTP " .. tostring(status) .. ", falling back")
        try(i + 1)
      else
        done = true; watchdog:stop()
        local hint = (status == 401 or status == 403) and " – check the key in Keychain" or ""
        callback(nil, "xAI API error (HTTP " .. tostring(status) .. ")" .. hint)
      end
    end)
  end
  try(1)
end

---------------------------------------------------------------------------------------
-- Opening things
---------------------------------------------------------------------------------------
-- "press" (app entries): after launching/focusing the app, find a UI element with this exact
-- label (AXTitle / AXDescription / first child's AXValue) and AXPress it. Used for things that
-- have no deep link, e.g. a pinned item in an Electron app's sidebar.
-- spec = { title = "...", role = "AXButton" (optional), timeout = 15 }
local function pressWhenReady(appName, spec, coldStart)
  local want, role = spec.title, spec.role
  local t0 = hs.timer.secondsSinceEpoch()
  local function plog(msg)
    vlog(string.format("press '%s' in %s: %s (%.1fs)", tostring(want), appName, msg,
      hs.timer.secondsSinceEpoch() - t0))
  end
  local deadline = t0 + (tonumber(spec.timeout) or 15)
  local function label(e)
    for _, a in ipairs({ "AXTitle", "AXDescription" }) do
      local t = e:attributeValue(a); if type(t) == "string" and t ~= "" then return t end
    end
    for _, c in ipairs(e:attributeValue("AXChildren") or {}) do
      local v = c:attributeValue("AXValue"); if type(v) == "string" and v ~= "" then return v end
    end
  end
  local function find()
    local app = hs.application.get(appName)
    local found
    if app then
      local ax = hs.axuielement.applicationElement(app)
      -- Electron/Chromium apps only expose their UI tree when asked:
      pcall(function() ax:setAttributeValue("AXManualAccessibility", true) end)
      local n = 0
      local function walk(e)
        if found or n > 8000 then return end
        n = n + 1
        local r = e:attributeValue("AXRole")
        if r == "AXMenuBar" then return end
        if (not role or r == role) and label(e) == want then found = e; return end
        for _, c in ipairs(e:attributeValue("AXChildren") or {}) do walk(c) end
      end
      pcall(walk, ax)
    end
    return app, found
  end
  local function attempt()
    if not hs.accessibilityState() then
      hs.alert.show("VoiceLauncher needs Accessibility permission for Hammerspoon", 4)
      plog("no Accessibility permission"); return
    end
    local app, found = find()
    if found then
      pcall(function() found:performAction("AXPress") end)
      app:activate()
      plog("clicked" .. (coldStart and ", re-click in 3s (app was starting)" or ""))
      if coldStart then -- a just-launched app may restore its last screen over our click
        hs.timer.doAfter(3, function()
          local _, f2 = find()
          if f2 then pcall(function() f2:performAction("AXPress") end); plog("re-clicked") end
        end)
      end
      return
    end
    if hs.timer.secondsSinceEpoch() < deadline then
      hs.timer.doAfter(0.7, attempt)
    else
      hs.alert.show("Couldn't find “" .. tostring(want) .. "” in " .. appName, 3)
      plog("not found, gave up")
    end
  end
  hs.timer.doAfter(0.5, attempt)
end

local function openOne(d)
  if d.type == "app" then
    local wasRunning = hs.application.get(d.value) ~= nil
    if not hs.application.launchOrFocus(d.value) then
      hs.task.new("/usr/bin/open", nil, { "-a", d.value }):start()
    end
    if type(d.press) == "table" and type(d.press.title) == "string" then
      pressWhenReady(d.value, d.press, not wasRunning)
    end
  elseif d.type == "url" then
    -- "activate": bundle id (preferred) or app name that should open the link AND come to the
    -- front: `open -b <id> <url>` in one step. Do NOT open the URL and then launchOrFocus the
    -- app separately – System Settings, for example, resets to General when focused that way.
    if type(d.activate) == "string" and d.activate ~= "" then
      local flag = d.activate:find("^[%w%-]+%.[%w%.%-]+$") and "-b" or "-a"
      local function go() hs.task.new("/usr/bin/open", nil, { flag, d.activate, d.value }):start() end
      go()
      hs.timer.doAfter(1.5, function() -- one retry if it still isn't frontmost
        local f = hs.application.frontmostApplication()
        local ok = f and ((flag == "-b" and f:bundleID() == d.activate) or (flag == "-a" and f:name() == d.activate))
        if not ok then go() end
      end)
    else
      hs.urlevent.openURL(d.value)
    end
  elseif d.type == "tab" then
    TAB.switch(d.tab)
  end
end

local function openAll(dests)
  local names = {}
  for i, d in ipairs(dests) do
    names[#names + 1] = d.name or d.id
    hs.timer.doAfter((i - 1) * OPEN_STAGGER, function() openOne(d) end)
  end
  hs.alert.show("Opening " .. table.concat(names, " → "), 2)
end

local function stripDone(text)
  local lower = text:lower()
  for _, w in ipairs(DONE_WORDS) do
    local s = lower:find("[%s%p]+" .. w .. "[%s%p]*$")
    if s and s > 1 then text = text:sub(1, s - 1); lower = lower:sub(1, s - 1) end
  end
  return trim(text)
end

local function run(text)
  text = stripDone(trim(text))
  if text == "" then return end
  M.resolve(text, function(dests, err, via)
    local ids = {}
    for _, d in ipairs(dests or {}) do ids[#ids + 1] = d.id end
    vlog("run " .. said(text) .. " -> " ..
      (err and ("error: " .. err) or (tostring(via) .. " [" .. table.concat(ids, ",") .. "]")))
    if err then hs.alert.show("VoiceLauncher: " .. err, 3); return end
    if not dests or #dests == 0 then hs.alert.show("Didn't catch that: “" .. text .. "”", 2.5); return end
    openAll(dests)
  end)
end
M.run = run

---------------------------------------------------------------------------------------
-- UI: one-line chooser. Enter runs now; otherwise it runs AUTO_SUBMIT_SECONDS after the
-- text stops changing (dictation apps type/paste in bursts).
---------------------------------------------------------------------------------------
local PLACEHOLDER = "Where to? Dictate or type…"
local voice = { active = false }
local chooser, timer
local submitted = false

local function stopTimer() if timer then timer:stop(); timer = nil end end
function voice.cancel()
  if voice.stopTimer then voice.stopTimer:stop(); voice.stopTimer = nil end
  if voice.waitTimer then voice.waitTimer:stop(); voice.waitTimer = nil end
end
local function dictation(cmd)
  if DICTATION_SCHEME then
    -- -g keeps the dictation app in the background so the box keeps focus and receives the text
    hs.task.new("/usr/bin/open", nil, { "-g", DICTATION_SCHEME .. "://" .. cmd }):start()
  end
end

local function submit(text)
  if submitted then return end
  submitted = true
  stopTimer()
  chooser:hide()
  run(text)
end

chooser = hs.chooser.new(function(choice)
  stopTimer()
  if choice and not submitted then submit(choice.query or choice.text) end
end)
chooser:placeholderText(PLACEHOLDER)
chooser:rows(1)
chooser:queryChangedCallback(function(q)
  stopTimer()
  q = q or ""
  if voice.active and trim(q) ~= "" then -- dictation delivered text: listening is over
    voice.active = false
    voice.cancel()
    vlog("text received " .. said(q))
  end
  if trim(q) == "" then chooser:choices({}); return end
  chooser:choices({ { text = q, subText = "Enter to go now · runs automatically after a short pause", query = q } })
  timer = hs.timer.doAfter(AUTO_SUBMIT_SECONDS, function() submit(chooser:query()) end)
end)
chooser:hideCallback(function()
  if voice.active then
    vlog("box closed while listening")
    dictation("stop-hands-free")
  end
  voice.active = false
  voice.cancel()
  chooser:placeholderText(PLACEHOLDER)
end)

function M.show()
  submitted = false
  stopTimer()
  chooser:query("")
  chooser:choices({})
  chooser:show()
end

-- Hands-free: open the box, start dictation in the background, stop it after
-- HANDSFREE_MAX_SECONDS, close the box if nothing arrives. WARNING: whatever the mic hears
-- in that window (TV, people in the room) is executed as a command.
function M.voice()
  voice.cancel()
  M.show()
  chooser:placeholderText(DICTATION_SCHEME and "Listening… speak now (tap fn to finish early)"
    or "Listening… start your dictation now")
  voice.active = true
  vlog("hands-free start")
  if not DICTATION_SCHEME then return end
  hs.timer.doAfter(HANDSFREE_START_DELAY, function() if voice.active then dictation("start-hands-free") end end)
  voice.stopTimer = hs.timer.doAfter(HANDSFREE_START_DELAY + HANDSFREE_MAX_SECONDS, function()
    voice.stopTimer = nil
    if not voice.active then return end
    vlog("max window reached, stopping dictation")
    dictation("stop-hands-free")
    chooser:placeholderText("Transcribing…")
    voice.waitTimer = hs.timer.doAfter(HANDSFREE_TEXT_WAIT, function()
      voice.waitTimer = nil
      if voice.active then
        vlog("no text arrived, closing box")
        voice.active = false
        chooser:hide()
        hs.alert.show("VoiceLauncher: didn't catch anything", 2)
      end
    end)
  end)
end

---------------------------------------------------------------------------------------
-- Triggers
---------------------------------------------------------------------------------------
for _, hk in ipairs(HOTKEYS) do
  local h = hs.hotkey.new(hk[1], hk[2], M.show)
  if h and h:enable() then
    M.hotkeyObj = h
    M.hotkey = table.concat(hk[1], "+") .. "+" .. hk[2]
    break
  end
end

-- hammerspoon://voicelaunch            -> box + hands-free dictation (Siri Shortcut target)
-- hammerspoon://voicelaunch?q=<text>   -> run <text> directly (Shortcuts, scripts, Stream Deck…)
-- hammerspoon://voicelaunch-reload     -> reload Hammerspoon config (used by install.sh)
hs.urlevent.bind("voicelaunch", function(_, params)
  local q = params and params.q
  if type(q) == "string" and trim(q) ~= "" then
    vlog("url q " .. said(q))
    run(q)
  else
    M.voice()
  end
end)
hs.urlevent.bind("voicelaunch-reload", function() hs.timer.doAfter(0.2, hs.reload) end)

---------------------------------------------------------------------------------------
-- Testing without a GUI: dry runs resolve but never open anything.
---------------------------------------------------------------------------------------
M.results = {}
function M.dryRun(text)
  M.results[text] = "pending"
  local t0 = hs.timer.secondsSinceEpoch()
  M.resolve(text, function(dests, err, via)
    local ms = math.floor((hs.timer.secondsSinceEpoch() - t0) * 1000)
    if err then M.results[text] = "ERROR: " .. err; return end
    local ids = {}
    for _, d in ipairs(dests or {}) do ids[#ids + 1] = d.id end
    M.results[text] = tostring(via) .. " -> [" .. table.concat(ids, ",") .. "] in " .. ms .. "ms"
  end)
  return "started"
end

-- status.txt: proves the module loaded (the `hs` CLI often hangs from remote/ssh sessions)
do
  local cfg, err = loadConfig()
  local s = os.date("%Y-%m-%d %H:%M:%S") .. " loaded, hotkey=" .. tostring(M.hotkey) ..
    " accessibility=" .. tostring(hs.accessibilityState()) ..
    " url=hammerspoon://voicelaunch" ..
    " destinations=" .. (cfg and #cfg.list or ("ERROR " .. tostring(err))) ..
    " key=" .. (getKey() and "present" or "MISSING") .. "\n"
  if cfg and #cfg.collisions > 0 then
    s = s .. "alias collisions (first entry wins): " .. table.concat(cfg.collisions, "; ") .. "\n"
  end
  writeFile(STATUS_FILE, s)
end

-- selftest.txt: one phrase per line; on load each is dry-run and the file is deleted.
do
  local fh = io.open(SELFTEST_FILE, "r")
  if fh then
    local phrases = {}
    for l in fh:lines() do l = trim(l); if l ~= "" then phrases[#phrases + 1] = l end end
    fh:close(); os.remove(SELFTEST_FILE)
    for _, p in ipairs(phrases) do M.dryRun(p) end
    M.selftestTimer = hs.timer.waitUntil(function()
      for _, p in ipairs(phrases) do if M.results[p] == "pending" then return false end end
      return true
    end, function()
      local o = {}
      for _, p in ipairs(phrases) do o[#o + 1] = p .. " => " .. tostring(M.results[p]) end
      writeFile(SELFTEST_RESULTS, table.concat(o, "\n") .. "\n")
    end, 0.5)
  end
end

log.i("voice launcher ready, hotkey: " .. tostring(M.hotkey))
voiceLauncher = M
return M
