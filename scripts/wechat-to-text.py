#!/usr/bin/env python3
"""
Convert exported WeChat HTML chats -> clean plain-text transcripts for LLMs.

Usage:
  python3 ~/wxexport/wechat-to-text.py list [keyword]     # list chats (optionally filter)
  python3 ~/wxexport/wechat-to-text.py "Chat Name" ...    # convert chat(s) matching name substrings
  python3 ~/wxexport/wechat-to-text.py --all              # convert every chat (large!)

Output: ~/wechat_txt/<chat>.txt   (one line per message: [time] Sender: text)
Media (images/voice/video/links/cards) become simple [placeholders].
"""
import sys, os, re, json, html

EXPORT_DIR = os.environ.get("WECHAT_EXPORT_DIR", "/Volumes/YOUR_DRIVE/wechat_export/YOUR_WECHAT_NICKNAME")
OUT_DIR    = os.path.expanduser("~/wechat_txt")
OWNER      = os.path.basename(EXPORT_DIR)   # your own account (used for 'right' msgs missing a name)

DT   = re.compile(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})')
NAME = re.compile(r'<span class="dspname[^"]*"[^>]*>(.*?)</span>', re.S)
PRE  = re.compile(r'<pre>(.*?)</pre>', re.S)
TAG  = re.compile(r'<[^>]+>')
AVATAR_IMG = re.compile(r'<img[^>]*class="avatar"[^>]*>')

def clean(t):
    t = re.sub(r'<br\s*/?>', '\n', t)
    t = TAG.sub('', t)
    return html.unescape(t).strip()

def parse_block(block):
    cls = (re.match(r'<div class="msg ([^"]*)"', block) or [None, ""])[1] if re.match(r'<div class="msg ([^"]*)"', block) else ""
    m = re.match(r'<div class="msg ([^"]*)"', block); cls = m.group(1) if m else ""
    mid = int((re.search(r'msgid="(\d+)"', block) or re.compile("x").search("")) .group(1)) if re.search(r'msgid="(\d+)"', block) else None
    dt = DT.search(block); ts = dt.group(1) if dt else ""
    nm = re.search(r'<span class="dspname ([^"]*)"[^>]*wxId="([^"]*)"[^>]*>(.*?)</span>', block, re.S)
    if nm:
        side, wxid, name = nm.group(1), nm.group(2), clean(nm.group(3))
        sender = name or wxid or (OWNER if 'right' in side else '(unknown)')
    else:
        sender = ""
    body = AVATAR_IMG.sub('', block)          # drop avatar imgs so they don't count as content
    pre = PRE.search(body)
    if pre and clean(pre.group(1)):
        content = clean(pre.group(1))
    elif re.search(r'<img\b', body):
        content = "[image]"
    elif re.search(r'<audio\b', body):
        content = "[voice]"
    elif re.search(r'<video\b', body):
        content = "[video]"
    else:
        content = clean(re.search(r'content-box">(.*)$', body, re.S).group(1)) if 'content-box' in body else ""
        content = content or "[unsupported]"
    if 'chat-notice' in cls and not sender:
        sender = "[system]"
    return mid, ts, sender, content

def iter_sources(chat_html):
    txt = open(chat_html, encoding='utf-8', errors='replace').read()
    m = re.search(r'id="msgs-div">(.*?)<div id="footer"', txt, re.S)
    if m: yield m.group(1)
    data = chat_html[:-5] + "_files/Data"
    if os.path.isdir(data):
        for jf in sorted(os.listdir(data)):
            if jf.startswith("msg-") and jf.endswith(".js"):
                c = open(os.path.join(data, jf), encoding='utf-8', errors='replace').read()
                i = c.find('var msgArray = ')
                if i >= 0:
                    try:
                        arr, _ = json.JSONDecoder().raw_decode(c, i + len('var msgArray = '))
                        yield ''.join(arr)
                    except Exception:
                        pass

def collect(chat_html):
    msgs = {}
    for src in iter_sources(chat_html):
        for part in src.split('<div class="msg ')[1:]:
            mid, ts, sender, content = parse_block('<div class="msg ' + part)
            if mid is None:
                continue          # split artifact, not a real message
            if '�' in content or sum(c < ' ' and c not in '\n\t' for c in content) > 2:
                continue          # unparseable/binary content (system/encrypted msgs) -> noise for LLMs
            msgs[mid] = (ts, sender, content)
    return [msgs[k] for k in sorted(msgs, key=lambda k: (msgs[k][0] or "0", k))]

def convert(chat_html):
    name = os.path.basename(chat_html)[:-5]
    rows = collect(chat_html)
    os.makedirs(OUT_DIR, exist_ok=True)
    safe = re.sub(r'[/:]', '_', name)
    out = os.path.join(OUT_DIR, safe + ".txt")
    dates = [r[0] for r in rows if r[0]]
    with open(out, 'w', encoding='utf-8') as f:
        f.write(f"# WeChat conversation: {name}\n")
        f.write(f"# {len(rows)} messages" + (f", {dates[0]} — {dates[-1]}" if dates else "") + "\n\n")
        for ts, sender, content in rows:
            head = f"[{ts}] {sender}" if ts else f"{sender}"
            f.write(f"{head}: {content}\n" if '\n' not in content
                    else f"{head}:\n{content}\n")
    return out, len(rows)

def all_html():
    return [os.path.join(EXPORT_DIR, f) for f in os.listdir(EXPORT_DIR)
            if f.endswith('.html') and f != 'index.html']

def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__); return
    if args[0] == 'list':
        kw = args[1].lower() if len(args) > 1 else ''
        items = []
        for h in all_html():
            n = os.path.basename(h)[:-5]
            if kw in n.lower():
                items.append((os.path.getsize(h), n))
        for sz, n in sorted(items, reverse=True):
            print(f"{sz//1024:6d} KB  {n}")
        print(f"\n{len(items)} chat(s).")
        return
    targets = all_html() if args[0] == '--all' else \
        [h for h in all_html() if any(a.lower() in os.path.basename(h)[:-5].lower() for a in args)]
    if not targets:
        print("No chat matched:", args); return
    for h in targets:
        out, n = convert(h)
        print(f"  {n:6d} msgs -> {out}")

if __name__ == '__main__':
    main()
