// Builds a starter destinations.json from installed apps and prints it to stdout.
// Usage: osascript -l JavaScript gen-destinations.js /path/to/destinations.example.json
// Read-only: lists app folders, reads the example file, writes nothing.
ObjC.import('Foundation');

function readText(p) {
  var s = $.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null);
  return s.isNil() ? null : s.js;
}
function listApps(dir) {
  var fm = $.NSFileManager.defaultManager;
  var items = fm.contentsOfDirectoryAtPathError($(dir).stringByExpandingTildeInPath, null);
  if (items.isNil()) return [];
  return ObjC.deepUnwrap(items).filter(function (n) { return /\.app$/.test(n); })
    .map(function (n) { return n.replace(/\.app$/, ''); }).sort();
}

// helpers, updaters, installers and other things nobody says "open ..." to
var SKIP = /(helper|url handler|uninstall|updater|update service|installer|agent|crash|reporter|daemon|diagnostic|migration assistant|boot camp|setup assistant|feedback assistant|^hammerspoon$|^safari technology preview$|^tips$)/i;
// Utilities worth keeping (the rest of /System/Applications/Utilities is skipped)
var UTILS = ['Terminal', 'Activity Monitor', 'Screenshot', 'Disk Utility', 'Console', 'Script Editor'];
// spoken short forms: "Microsoft Teams" -> "Teams", "Grammarly Desktop" -> "Grammarly"
function shortForms(name) {
  var out = [];
  var m = name.match(/^(Microsoft|Google|Adobe|Apple|Affinity|Logic|Final Cut)\s+(.+)$/);
  if (m && m[1] !== 'Logic' && m[1] !== 'Final Cut') out.push(m[2]);
  var d = name.match(/^(.+?)\s+(Desktop|for Mac|App)$/i);
  if (d) out.push(d[1]);
  var spaced = name.replace(/([a-z]{2})([A-Z])/g, '$1 $2'); // "VoiceMemos" -> "Voice Memos"
  if (spaced !== name) out.push(spaced);
  return out;
}
function slug(s) {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'app';
}

function run(argv) {
  var examplePath = argv[0];
  var example = JSON.parse(readText(examplePath) || '{}');
  var out = {
    _help: example._help,
    models: example.models,
    destinations: []
  };
  var ids = {}, names = {};
  function claimName(n) { var k = n.toLowerCase(); if (names[k]) return false; names[k] = true; return true; }
  function add(d) {
    var base = d.id, i = 2;
    while (ids[d.id]) d.id = base + '-' + (i++);
    ids[d.id] = true;
    out.destinations.push(d);
  }

  // 1) installed apps (user apps first, then Apple apps), one entry per app name
  var seen = {};
  var sources = [
    ['/Applications', 'App'], ['~/Applications', 'App'],
    ['/System/Applications', 'macOS app'], ['/System/Applications/Utilities', 'macOS utility']
  ];
  sources.forEach(function (src) {
    listApps(src[0]).forEach(function (name) {
      if (SKIP.test(name) || seen[name.toLowerCase()]) return;
      if (src[1] === 'macOS utility' && UTILS.indexOf(name) < 0) return;
      seen[name.toLowerCase()] = true;
      if (!claimName(name)) return;
      var aliases = shortForms(name).filter(claimName);
      add({ id: slug(name), name: name, aliases: aliases, description: src[1] + ' ' + name,
            type: 'app', value: name });
    });
  });

  // 2) generic extras from the example: System Settings panes ('activate') and disabled
  //    templates for deep links (Claude project/chat, ChatGPT project, Grok Bot chat, ...)
  (example.destinations || []).forEach(function (d) {
    if (!(d.activate || d.disabled)) return;
    if (!claimName(d.name)) return;
    d.aliases = (d.aliases || []).filter(claimName);
    add(JSON.parse(JSON.stringify(d)));
  });

  return JSON.stringify(out, null, 2);
}
