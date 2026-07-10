#!/bin/bash
# ============================================================
#  Export only SPECIFIC WeChat chats (fast) and turn them into
#  LLM-ready text in one step.
#
#  Usage:
#     ~/wxexport/export-chats.sh "大模型" "Jean" "Jiahui"
#
#  Each argument is a name OR keyword; it's matched (case-insensitive,
#  substring) against your existing export's chat list, so you don't
#  need the exact name. Back up in iMazing first if you want the latest
#  messages; otherwise it reads your most recent backup.
#
#  Output: ~/wechat_txt/<chat>.txt   (HTML kept in the side folder below)
# ============================================================
set -uo pipefail
[ $# -ge 1 ] || { echo 'Usage: export-chats.sh "chat name or keyword" [more...]'; exit 1; }

TOOL_DIR="$HOME/wxexport"
BIN="$TOOL_DIR/WechatExporterCmd"
ZIP="$TOOL_DIR/WechatExporterCmd.zip"
ACCOUNT="YOUR_WECHAT_NICKNAME"
FULL_EXPORT="/Volumes/YOUR_DRIVE/wechat_export/$ACCOUNT"
SIDE_OUT="/Volumes/YOUR_DRIVE/wechat_selected"

# 1) resolve keywords -> EXACT chat display names, using the existing export's index
NAMES=()
while IFS= read -r line; do [ -n "$line" ] && NAMES+=("$line"); done < <(
python3 - "$FULL_EXPORT" "$@" <<'PY'
import sys, os, re, html, urllib.parse
full = sys.argv[1]; args = [a.lower() for a in sys.argv[2:]]
found = set()
idx = os.path.join(full, "index.html")
if os.path.isfile(idx):
    txt = open(idx, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r'<a href="([^"]+\.html)">([^<]*)</a>', txt):
        base = urllib.parse.unquote(m.group(1))[:-5]        # decoded filename = the --session value
        text = html.unescape(m.group(2)).strip()            # display text (may include WeChat ID)
        if any(a in (base + " " + text).lower() for a in args):
            found.add(base)
if not found and os.path.isdir(full):                       # fallback: match filenames directly
    for f in os.listdir(full):
        if f.endswith(".html") and f != "index.html":
            b = f[:-5]
            if any(a in b.lower() for a in args):
                found.add(b)
for n in sorted(found):
    print(n)
PY
)
if [ ${#NAMES[@]} -eq 0 ]; then
    echo "No chats matched in the existing export; passing your terms to WeChat as-is."
    NAMES=("$@")
fi
echo "Chats to export (${#NAMES[@]}):"; printf '  • %s\n' "${NAMES[@]}"; echo

# 2) locate newest backup (handles both iMazing folder names)
BACKUP_DIR=$(find "/Volumes/YOUR_DRIVE/iMazing.Backups" "/Volumes/YOUR_DRIVE/-iMazing.Backups" \
    -maxdepth 2 -name Manifest.db 2>/dev/null -exec stat -f "%m %N" {} \; \
    | sort -rn | head -1 | cut -d" " -f2- | xargs -I{} dirname {})
[ -n "$BACKUP_DIR" ] || { echo "No backup found — plug in the drive / back up in iMazing first."; exit 1; }

# 3) prepare tool (self-heal + locale fix)
[ -f "$BIN" ] || unzip -oq "$ZIP" WechatExporterCmd -d "$TOOL_DIR"
chmod +x "$BIN"; codesign --force --sign - "$BIN" 2>/dev/null
for d in "$TOOL_DIR"/Frameworks/*.dylib; do codesign --force --sign - "$d" 2>/dev/null; done
xattr -cr "$TOOL_DIR"
[ -f "$TOOL_DIR/res/.txt" ] || cp -f "$TOOL_DIR/res/en.txt" "$TOOL_DIR/res/.txt"

# 4) export ONLY those chats (startup loads contacts ~1-2 min, then just these chats)
SESS=(); for n in "${NAMES[@]}"; do SESS+=(--session="$n"); done
rm -rf "$SIDE_OUT"; mkdir -p "$SIDE_OUT"
echo "==> Exporting selected chat(s)..."
cd "$TOOL_DIR"
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 "$BIN" --backup="$BACKUP_DIR" --output="$SIDE_OUT" \
    --account="$ACCOUNT" "${SESS[@]}" \
    2>"$TOOL_DIR/last-run-errors.log" | grep --line-buffered -v '^DBG::'

# 5) convert the selected chats to LLM-ready text
echo "==> Converting to text..."
WECHAT_EXPORT_DIR="$SIDE_OUT/$ACCOUNT" python3 "$TOOL_DIR/wechat-to-text.py" --all

echo "==> Done. Text files: ~/wechat_txt/   (HTML: $SIDE_OUT/$ACCOUNT)"
open ~/wechat_txt 2>/dev/null || true
