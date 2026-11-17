# 07 — The web UI

[`ui/index.html`](../ui/index.html) replaces dufs's default page. It is **one self-contained file** (HTML + CSS + JS, no build step, no external requests),
~50 KB, written for phones first. The page title and strings are in Brazilian Portuguese (`lang="pt-BR"`).

## Features

- Responsive **grid and list** views, dark and light themes (follows the system), safe-area aware.
- Built-in **viewer** for video, images and audio; search; breadcrumbs.
- Video cards show a frame from the file itself (`<video preload="metadata">`); images are lazy-loaded with an `IntersectionObserver`.
  Nothing is generated on the phone (there is no working `ffmpeg` there).
- **Upload** with drag and drop (including whole folders) and a progress panel.
- **Rename, move, create folder, delete** (with confirmation dialogs), using WebDAV `MOVE`, `MKCOL` and `DELETE`.
- **Download as zip** for folders (`?zip`) when dufs allows archives.
- **Storage panel** fed by `.nuvem-status.json` ([06](06-dufs-cloud.md)).

## How it talks to dufs

dufs renders its index page with an embedded JSON blob (`<template id="index-data">`: paths, permissions, the `allow_*` flags, the user). The UI decodes
that blob to draw the page, and to *refresh* the listing it simply fetches the same URL again and parses the blob out of the HTML. Everything
that changes data uses plain `fetch`: `PUT` for uploads, `MOVE` (rename/move), `MKCOL` (new folder), `DELETE`.

Details that matter:

- **Credentials are sent by the page**, not left to the browser. Browsers send Basic credentials only after a `401` challenge, but a large `PUT`
  through `tailscale serve` is answered with `502` first. So when you first write something, the UI asks for the password, checks it with a `HEAD`
  request, keeps it in the tab's `sessionStorage` (gone when the tab closes; never written to the repo or to the server) and adds
  `Authorization: Basic …` to every request after that.
- **Existence checks drop the trailing slash** (`HEAD /name`, not `/name/`), because dufs answers 200 for `…/` on missing folders.
- A folder rename is a single `MOVE`, not copy + delete.
- Display preferences (view mode, etc.) are kept in `localStorage`, guarded with `try/catch` so private mode does not break the page.

## Develop on the PC

You can open the file's logic against a throwaway dufs on your PC:

```sh
mkdir -p /tmp/cloud && dufs -a 'cloud:test@/:rw' -A --assets "$(pwd)/ui" /tmp/cloud   # then browse http://localhost:5000
```

(`--assets` takes the directory that contains `index.html`.) Deploy the result with `tools/adb-run.sh install/cloud.sh` and **restart dufs** (the installer does).

## Safety when testing

Test deletions and moves only in folders you created for the test (for example `zz-test`), and remove them afterwards. Never point a test at real data.
