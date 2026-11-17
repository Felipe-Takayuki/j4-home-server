# 06 — The cloud (dufs)

Goal: a private file server for videos, photos and documents, reachable from every device on your tailnet and usable as a WebDAV share.

## Why dufs

[dufs](https://github.com/sigoden/dufs) is a single Rust binary packaged by Termux (`pkg install dufs`, version 0.47.0 here): static file server,
uploads, search, zip download, **WebDAV**, auth, and a replaceable web UI. It is a *native* Termux (bionic) binary, so it does not hit the
Android 10 SIGSYS traps that killed the alternatives the author tried (FileBrowser Quantum v1 and v2 crash on `statx`; the original File Browser
is archived and gets no security fixes).

## Install

```sh
tools/adb-run.sh install/cloud.sh
```

It: copies the UI to `~/.dufs/assets/index.html`, the status scripts, and the boot scripts; creates `~/cloud` (the served folder); generates
`~/.dufs/config.yaml` from [`cloud/config.example.yaml`](../cloud/config.example.yaml) with a **random 20-character password printed once on
the phone's screen**; and (re)starts dufs. It never overwrites an existing config. Then expose it:

```sh
ts serve --bg --https=443 http://127.0.0.1:8080
```

Open `https://j4.<your-tailnet>.ts.net/` from any device on the tailnet. Login user: `cloud`.

## The configuration, explained

```yaml
bind: 127.0.0.1               # never the LAN: only tailscale serve reaches it
port: 8080
serve-path: /data/data/com.termux/files/home/cloud
auth:
  - 'cloud:<password>@/:rw'   # user:password@path:permissions
allow-upload: true
allow-delete: true
allow-search: true
allow-archive: true           # "?zip" downloads
allow-symlink: false
render-index: false
assets: /data/data/com.termux/files/home/.dufs/assets   # the custom UI
hidden:
  - '.nuvem-status.json'      # the file the UI reads for the storage panel
```

## Using it as WebDAV

dufs speaks WebDAV on the same URL, so Android apps (FolderSync, Material Files, KOReader, KeePassDX…) and desktop file managers can mount
`https://j4.<your-tailnet>.ts.net/` with user `cloud`. `MOVE`, `MKCOL` and `DELETE` work with accents and spaces.

## Quirks worth knowing

- **dufs keeps the custom UI in memory.** After replacing `~/.dufs/assets/index.html`, restart dufs (`pkill dufs; sh ~/.termux/boot/30-cloud`)
  or the old page keeps being served.
- **Plain `curl` gets a text listing, not the UI.** The HTML UI is returned only to browser-like requests. To test it:
  `curl -H 'Accept: text/html' -H 'Sec-Fetch-Mode: navigate' -A 'Mozilla/5.0' -u cloud:<pw> https://j4.<tailnet>.ts.net/`.
- **`HEAD /no-such-dir/` (trailing slash) returns 200** because dufs answers with the UI for any path ending in `/`, while `HEAD /no-such-dir` returns 404.
  Existence checks must drop the trailing slash (this once broke folder rename).
- **Large unauthenticated `PUT`s through `tailscale serve` give 502**, not 401 — see [05](05-tailscale.md). The UI sends `Authorization` itself.
- Without a browser on the phone itself, test from the PC.

## The status panel

[`cloud/status.sh`](../cloud/status.sh) (run every 30 s by [`status-loop.sh`](../cloud/status-loop.sh), started by `40-status`) writes
`~/cloud/.nuvem-status.json` (`total`, `used`, `avail`, `cloud` in bytes). The UI fetches it for the storage bar. It is hidden from listings.

Next: [07 — The web UI](07-web-ui.md).
