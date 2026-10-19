-- Offline test of the Chrome-tab matching in voice-launcher.lua (no Hammerspoon needed):
--   lua tests/tab-match-test.lua
local src = assert(io.open((arg[0]:match("^(.*)/tests/") or ".") .. "/voice-launcher.lua")):read("a")
local pure = src:match("%-%- %[tabs%-pure%-begin%][^\n]*\n(.-)%-%- %[tabs%-pure%-end%]")
local TAB = assert(load(pure .. "\nreturn TAB"))()

local tabs = { -- window 1 is the frontmost window
  { w = 1, t = 1, title = "Inbox (3) - someone@example.com - Gmail", url = "https://mail.google.com/mail/u/0/#inbox" },
  { w = 1, t = 2, title = "Project plan - Google Docs", url = "https://docs.google.com/document/d/abc/edit", active = true },
  { w = 1, t = 3, title = "Cooking video - YouTube", url = "https://www.youtube.com/watch?v=1" },
  { w = 2, t = 1, title = "Music video - YouTube", url = "https://www.youtube.com/watch?v=2", active = true },
  { w = 2, t = 2, title = "Budget - Google Sheets", url = "https://docs.google.com/spreadsheets/d/x/edit" },
  { w = 2, t = 3, title = "Home / X", url = "https://x.com/home" },
  { w = 3, t = 1, title = "Electric trucks are coming", url = "https://news.example.com/2026/trucks?utm=1", active = true },
}
local cases = { -- text, expected tab id or "none"/"ambiguous", expected intent
  { "YouTube tab", "tab:1:3", true }, { "go to my Gmail tab", "tab:1:1", true },
  { "switch to the YT one", "tab:1:3", true }, { "sheets tab", "tab:2:2", true },
  { "docs tab", "tab:1:2", true }, { "switch to X", "tab:2:3", true },
  { "switch to the electric trucks tab", "tab:3:1", true }, { "music video tab", "tab:2:1", true },
  { "Netflix tab", "none", true }, { "open Slack", "none", false }, { "tab", "none", true },
}
local fails = 0
for _, c in ipairs(cases) do
  local t, why = TAB.match(TAB.query(c[1]), tabs)
  local got = t and ("tab:" .. t.w .. ":" .. t.t) or why
  local ok = got == c[2] and TAB.intent(c[1]) == c[3]
  if not ok then fails = fails + 1 end
  print(string.format("%s %-38s -> %s", ok and "ok  " or "FAIL", '"' .. c[1] .. '"', got))
end
for _, l in ipairs(TAB.grokLines(tabs, 50, 30)) do assert(not l:find("?", 1, true), "query string leaked") end
print(fails == 0 and "all passed" or (fails .. " failed")); os.exit(fails == 0 and 0 or 1)
