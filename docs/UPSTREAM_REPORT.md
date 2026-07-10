# Upstream report — macOS (Apple Silicon) fixes for WechatExporter

Three issues hit when running **WechatExporterCmd v1.9.5.13** on macOS 14/15 +
Apple Silicon (x86_64 under Rosetta). Each has a small, contained fix. These can
be filed as one issue or split into three; patches are minimal.

Line numbers reference the `main` branch source.

---

## 1. Unsigned x86_64 binary is deleted by Gatekeeper/XProtect on first run

**Symptom.** The `.app` reports *"is damaged and can't be opened,"* and the CLI
binary **silently disappears from disk** right after you execute it.

**Cause.** Release artifacts are unsigned x86_64. On modern macOS, executing an
unsigned/quarantined binary triggers XProtect remediation, which removes it.

**User workaround** (after unzip):
```bash
codesign --force --sign - WechatExporterCmd
for d in Frameworks/*.dylib; do codesign --force --sign - "$d"; done
xattr -cr .
```

**Suggested fix.** Ship **signed** release artifacts — even ad-hoc
(`codesign -s -`) at packaging time prevents the deletion; Developer ID +
notarization is ideal.

---

## 2. Empty locale name → templates silently fail to load

**Symptom.** Log prints `Failed to load resources in <dir>.` and exported HTML
has **no templates** (blank/broken output). No error is raised — the export
otherwise "succeeds."

**Root cause.** `WechatExporterCmd/WechatExporter.cpp::getCurrentLanguageCode()`
returns `std::locale("").name()`, which is **`""` (empty) on macOS**.
`ResManager::loadLocaleStrings()` then looks for `res/ + "" + ".txt"` =
**`res/.txt`** (`ResManager.cpp:66-70`), which doesn't exist, so
`initResources()` returns false *before* `loadTemplates()` runs
(`Exporter.cpp:277`). Templates are never loaded.

**Minimal fix** (default the language when empty):
```cpp
std::string languageCode = getCurrentLanguageCode();
if (languageCode.empty()) languageCode = "en";
```

---

## 3. WechatExporterCmd never uses incremental export — every run is a full re-export

**Symptom.** Re-running the CLI against an existing output directory
re-processes **every chat and every message** (full message counts), even though
it writes the `.wxexp` context and logs `Save messages for incremental exporting.`

**Root cause.** Incremental is gated on `m_options.isIncrementalExporting()`,
which **defaults off** (`ExportOption`: `m_options = 0`). The GUI enables it
(`ViewController.mm` → `Exporter::hasPreviousExporting()` →
`setIncrementalExporting(true)`; also `AppConfiguration.mm:357`), but
**`WechatExporterCmd/WechatExporterCmd.h::exportSessions()` never calls
`setIncrementalExporting`.** So at `Exporter.cpp:336`:

```cpp
if ((m_options.isIncrementalExporting()) && loadExportContext(...))  // short-circuits to false
```

`loadExportContext()` is never called → `getMaxId()` always returns 0 →
`buildMsgEnumerator(session, 0)` enumerates **all** messages.

> Note: the `Save messages for incremental exporting.` log (`Exporter.cpp:977`)
> is **unconditional**, so it appears even when incremental is inactive — which
> makes it look like incremental is working when it isn't.

**Fix** — one block in `exportSessions()`, before `exp.setOptions(options)`:
```cpp
std::string exportTime, version; uint64_t prevOptions = 0;
if (Exporter::hasPreviousExporting(outputDir, prevOptions, exportTime, version))
    options.setIncrementalExporting(true);
```

**Impact.** With this, re-runs skip unchanged chats via the early-out at
`Exporter.cpp:959` (`if (numberOfMsgs == 0) return ...`), turning a multi-hour
full export into a short delta update. Verified externally: on the current CLI,
a second run reported full per-chat message counts (e.g. `Succeeded handling
94369 messages`) with no `Incremental Exporting` line logged.

---

## 4. GUI app (x86_64) crashes on current macOS under Rosetta

**Symptom.** `WechatExporter.app` (x86_64) crashes shortly after selecting a
backup, while the window redraws — even after ad-hoc signing + de-quarantine.

**Crash.** `EXC_BAD_INSTRUCTION` (SIGILL) on the main thread, inside
`AppKit … +[CATransaction(NSCATransaction) NS_setFlushesWithDisplayLink]_block_invoke`
(called from the CFRunLoop observer). No application frames on the crashed
thread — it faults in the Core Animation display-link path during a normal
redraw. Reproducible across runs.

**Cause.** The 3-year-old Intel build running under Rosetta on modern macOS hits
a Core Animation / display-link incompatibility. Not data-related.

**Suggested fix.** Ship a **native arm64 (or universal)** GUI build. Until then,
the CLI is the only viable path on Apple Silicon — which makes issue #3
(CLI incremental) the practical blocker for fast re-exports.

---

*Reported from a real end-to-end run on macOS + Apple Silicon, iOS backup made
with iMazing, WeChat iOS 8.0.75.*
