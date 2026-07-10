# Building a native arm64 WechatExporterCmd with working incremental

The prebuilt CLI is unsigned x86_64 (Rosetta) and its incremental export is a
no-op (see UPSTREAM_REPORT.md #3). Building from source on Apple Silicon fixes
both — native arm64, and real incremental re-exports.

## Dependencies (Homebrew)
```bash
brew install libplist jsoncpp lame protobuf@21   # protobuf@21 still ships stubs/strutil.h
```
System libs (sqlite3, libxml2, curl, z, iconv) are used to avoid @rpath issues.

## Source changes
1. **Enable incremental (the fix):** in `WechatExporterCmd/WechatExporterCmd.h`,
   `exportSessions()`, before `exp.setOptions(options)`:
   ```cpp
   std::string _t,_v; uint64_t _o=0;
   if (Exporter::hasPreviousExporting(outputDir,_o,_t,_v)) options.setIncrementalExporting(true);
   ```
2. **Empty-locale fallback:** in `WechatExporterCmd/WechatExporter.cpp`, after
   `getCurrentLanguageCode()`: `if (languageCode.empty()) languageCode = "en";`
3. **libplist API:** newer `plist_from_memory(...)` takes a 4th `plist_format_t*`
   arg — append `, NULL` to the 8 calls in `ITunesParser.cpp` / `WechatParser.cpp`.
4. **Stub `OSDef.h`** (missing header): define `DIR_SEP '/'` and `DIR_SEP_R '\\'`.
5. **Stub voice codecs** (SKP SILK SDK + opencore-amr aren't vendored): replace
   `Utils_silk.cpp` with `silkToPcm`/`amrToPcm` returning `false`.
   ⚠️ Consequence: voice messages export as placeholders **without decoded audio**.
   All other content (text, images, video, links, etc.) is unaffected.
6. **Exclude `IDeviceBackup.cpp`** (live-device only; needs libimobiledevice —
   the CLI reads local backups via `ITunesDb`).

## Build
See `scripts/build-native-arm64.sh`. Runtime needs Homebrew + the formulae above
installed (the binary links their dylibs by absolute path).

## Verified
Two runs of the same `--session` export: run 1 full, run 2 logs
`Incremental Exporting` and processes 0 new messages. Confirmed the arm64 binary
also loads a context written by the original x86_64 build.
