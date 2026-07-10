# WeChat Export Toolkit (macOS / Apple Silicon)

Export your **iPhone** WeChat history to browsable HTML, then convert any chat to
**clean, LLM-ready text** — with the rough edges of running
[BlueMatthew/WechatExporter](https://github.com/BlueMatthew/WechatExporter) on
**modern macOS (Sonoma/Sequoia + Apple Silicon)** already solved.

It reads an **iOS backup** (made with iMazing or Finder) — your own data, no
circumvention of live encryption. Nothing is uploaded; everything runs locally.

---

## Why this exists

The underlying exporter works great, but on a current Apple-Silicon Mac you hit a
stack of undocumented, silent failures. This toolkit packages the fixes plus a
selective-export helper and an HTML→text converter for feeding conversations to LLMs.

---

## ⚠️ Gotchas on modern macOS (the part worth reading)

These cost hours to figure out. Each is handled automatically by the scripts, but
here's what's actually going on:

| Symptom | Cause | Fix |
|---|---|---|
| **"App is damaged and can't be opened"**, or the CLI binary **silently disappears** after you run it | The prebuilt binary is unsigned x86_64; Gatekeeper/XProtect quarantines and **deletes** it on execution | **Ad-hoc code-sign it**: `codesign --force --sign - WechatExporterCmd` (and each `Frameworks/*.dylib`), then `xattr -cr` |
| **"Failed to load resources"** → HTML comes out with no templates | `std::locale("").name()` returns **empty** on macOS, so the tool looks for a resource file literally named `.txt` and silently skips template loading | Create it: `cp res/en.txt res/.txt` |
| **`bad CPU type in executable`** when running the CLI from Terminal | x86_64 binary, no Rosetta (Terminal won't auto-prompt like double-click does) | `softwareupdate --install-rosetta --agree-to-license` |
| `--format=text` in `--help` does nothing | The CLI **parses no `--format` flag** — output is always HTML | Use the included `wechat-to-text.py` for text |
| CLI exits with **"Please input account name"** | `--account` must equal your **exact WeChat display name** (nickname), not your WeChat ID | See "Finding your account name" below |
| Backup unreadable / corrupt on the external drive | iOS backups need a **Mac-native** filesystem | Format the drive **APFS** or **Mac OS Extended** — *not* exFAT/FAT32 |
| Tool (or these scripts) can't read `~/Downloads` or the external volume | macOS **TCC** privacy protection | Grant **Full Disk Access** to Terminal (System Settings → Privacy & Security) |

### Finding your account name (`--account`)
The CLI filters by your account's **display name**. Two easy ways:
1. Run an export once and read the line `Handling account: <NAME>, WeChat Id: <id>`.
2. Or read it from the backup's `Documents/MMappedKV/mmsetting.archive.<uin>`
   (MMKV **key `88`** = display name).

---

## Requirements

- macOS on Apple Silicon (Intel works too), **Rosetta 2**
- An **iOS backup** of your iPhone — via **iMazing** (recommended) or Finder,
  **unencrypted**, on an **APFS / Mac OS Extended** drive
- Python 3 (bundled with macOS)

> **Android users:** migrate WeChat history to an iPhone/iPad first, then back that up.

---

## Setup

```bash
# 1. Download the command-line build from the upstream Releases page:
#    https://github.com/BlueMatthew/WechatExporter/releases
#    -> vX.Y.Z-x64-macos-cmd.zip   (the -cmd zip, not the GUI one)
#    Unzip it into ~/wxexport/ so ~/wxexport/WechatExporterCmd exists.

# 2. Put a copy of that zip at ~/wxexport/WechatExporterCmd.zip
#    (the scripts use it to self-heal if macOS deletes the binary).

# 3. Edit the CONFIG block at the top of scripts/export-all.sh:
#    - YOUR_WECHAT_NICKNAME  -> your WeChat display name
#    - /Volumes/YOUR_DRIVE   -> your external drive
```

The binary is **not** included here (it's GPL and belongs to the upstream project) —
you download it yourself. See [NOTICE.md](NOTICE.md).

---

## Usage

**Full export** (all chats → HTML; incremental on re-runs):
```bash
scripts/export-all.sh
```

**Export only specific chats** (fast) and convert them to text in one step:
```bash
scripts/export-chats.sh "大模型讨论群" "Jean" "some keyword"
```
Arguments are matched (case-insensitive substring, even by WeChat ID) against your
existing export's chat list, so you don't need exact names.

**Convert exported HTML → LLM-ready text:**
```bash
python3 scripts/wechat-to-text.py list [keyword]     # find chats
python3 scripts/wechat-to-text.py "Chat Name" ...    # -> ~/wechat_txt/<chat>.txt
```

### Output format
```
# WeChat conversation: 大模型讨论群3
# 2612 messages, 2023-06-20 — 2026-05-04

[2023-11-13 07:05:17] Alice: 如果想要一个能理解投资策略的大模型，需要多大的文本量
[2024-01-01 08:57:56] Bob: spin-transformer is all we need to explain LLMs.
```
`[timestamp] Sender: message`, chronological, one line per message. Media/links
become `[image]` / `[voice]` / `[video]` / `[Link]` placeholders. Unparseable
binary/system messages are filtered out.

**Known limits:** link URLs aren't preserved by the export (bare `[Link]`); some
older paginated messages have blank senders; text-only (media are placeholders).

---

## How it works

1. iMazing/Finder makes a standard iOS backup (`Manifest.db` + hashed files).
2. `WechatExporterCmd` decrypts & renders WeChat's SQLite DBs to per-chat HTML.
3. `wechat-to-text.py` merges the main HTML page + `_files/Data/msg-*.js`
   pagination, drops binary noise, and emits a clean transcript.

## Credits & license

Wraps [BlueMatthew/WechatExporter](https://github.com/BlueMatthew/WechatExporter)
(GPL v2 — downloaded separately, not bundled). Wrapper scripts and the converter
in this repo are MIT. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
