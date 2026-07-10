#!/bin/bash
# ============================================================
#  WeChat history export — reusable runner
#  Created with Claude. Just run:  ~/wxexport/run-wechat-export.sh
#
#  BEFORE running: open iMazing and back up your iPhone again
#  (unencrypted). iMazing updates the SAME backup folder in place,
#  so this script always finds the latest one automatically.
# ============================================================
set -uo pipefail

# ---------- settings you might change ----------
ACCOUNT="YOUR_WECHAT_NICKNAME"                                    # your WeChat DISPLAY NAME (nickname). Change only if you rename your WeChat.
OUTPUT="/Volumes/YOUR_DRIVE/wechat_export"           # SAME folder = incremental (adds only new messages, fast).
                                                    #   For a clean full re-export, point this at a NEW empty folder.
BACKUP_ROOT="/Volumes/YOUR_DRIVE/iMazing.Backups"    # your renamed iMazing backups folder
# -----------------------------------------------

TOOL_DIR="$HOME/wxexport"
ZIP="$TOOL_DIR/WechatExporterCmd.zip"               # self-contained restore copy (no dependency on Downloads)
BIN="$TOOL_DIR/WechatExporterCmd"

echo "==> [1/3] Locating the latest iMazing device backup..."
BACKUP_DIR=$(find "$BACKUP_ROOT" "/Volumes/YOUR_DRIVE/-iMazing.Backups" -maxdepth 2 -name Manifest.db 2>/dev/null -exec stat -f "%m %N" {} \; | sort -rn | head -1 | cut -d" " -f2- | xargs -I{} dirname {})
if [ -z "$BACKUP_DIR" ]; then
  echo "  ERROR: no backup found under $BACKUP_ROOT"
  echo "  -> Plug in the 'Expansion' drive and make a fresh backup in iMazing first."
  exit 1
fi
echo "    backup: $BACKUP_DIR"

echo "==> [2/3] Preparing the tool (self-heals macOS quarantine + locale fix)..."
[ -f "$BIN" ] || unzip -oq "$ZIP" WechatExporterCmd -d "$TOOL_DIR"
chmod +x "$BIN"
codesign --force --sign - "$BIN" 2>/dev/null
for d in "$TOOL_DIR"/Frameworks/*.dylib; do codesign --force --sign - "$d" 2>/dev/null; done
xattr -cr "$TOOL_DIR"
[ -f "$TOOL_DIR/res/.txt" ] || cp -f "$TOOL_DIR/res/en.txt" "$TOOL_DIR/res/.txt"

echo "==> [3/3] Exporting '$ACCOUNT'  ->  $OUTPUT"
echo "    (if this folder already has an export, only NEW messages are added)"
mkdir -p "$OUTPUT"
cd "$TOOL_DIR"
# stderr (libxml2 parse warnings for binary/system messages) -> log; hide verbose DBG lines
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 "$BIN" --backup="$BACKUP_DIR" --output="$OUTPUT" --account="$ACCOUNT" \
    2>"$TOOL_DIR/last-run-errors.log" | grep --line-buffered -v '^DBG::'
rc=${PIPESTATUS[0]}
echo
if [ $rc -eq 0 ]; then
  echo "==> DONE.  Open:  $OUTPUT/index.html"
  command -v open >/dev/null && open "$OUTPUT/index.html"
else
  echo "==> Finished with exit code $rc (check messages above)."
fi
