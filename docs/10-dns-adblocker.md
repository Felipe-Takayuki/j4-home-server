# 10 — DNS ad blocker

Blocks ads and trackers for your Android phones **at home and away**, with a small Python resolver (one file, standard library only) running on the server phone.
Nothing to install on the clients: you point Android's built-in **Private DNS** at the server.

## Design (and why it looks odd)

```
 Android phone (Tailscale on, Private DNS = j4.<tailnet>.ts.net)
        │  DNS-over-TLS, port 853, over the tailnet
        ▼
 tailscaled ── serve --tls-terminated-tcp=853 ──► 127.0.0.1:5353  dnsblock.py (UDP+TCP)
                                                     ├─ blocked?  → 0.0.0.0 / ::      (A / AAAA; empty NOERROR for other types)
                                                     ├─ tailnet name? → answered locally from `tailscale status --json`
                                                     └─ else → 1.1.1.1 / 9.9.9.9 / 8.8.8.8 over UDP (TCP when truncated)
```

- **Why not `dnsmasq`, Pi-hole or AdGuard Home?** `dnsmasq` was not installable from the device's stale Termux index; Pi-hole needs root/containers;
  AdGuard Home is a Go binary (SIGSYS risk, see [11](11-android10-pitfalls.md)). A small Python script with the standard library is
  enough and uses tens of MB.
- **Why DNS-over-TLS on 853?** A non-root Termux process **cannot bind port 53** (`Permission denied`), and routers/Tailscale's DNS settings only accept an
  IP on port 53. Android's *Private DNS* accepts a **hostname** and speaks DoT, and `tailscale serve --tls-terminated-tcp` gives the node's real certificate
  for `j4.<tailnet>.ts.net`. So the phone-to-phone path is encrypted and authenticated by Tailscale.
- **Consequence:** it protects the devices that run Tailscale and have Private DNS set. Not the whole house through the router (impossible here
  without root), and not a PC unless you configure DoT/DoH on it.

## Install

```sh
tools/adb-run.sh install/dnsblock.sh
```

This copies `dnsblock.py` + `run.sh` to `~/.dnsblock/`, installs `~/.termux/boot/60-dnsblock`, downloads the blocklist
(StevenBlack/hosts, ~76k domains), and runs `ts serve --bg --tls-terminated-tcp=853 tcp://localhost:5353`. Check it from the PC:

```sh
python3 tools/dot-query.py j4.<your-tailnet>.ts.net doubleclick.net      # rcode=0 ['0.0.0.0']
python3 tools/dot-query.py j4.<your-tailnet>.ts.net example.com          # real addresses
```

## Use it on Android

On each phone that runs the Tailscale app: **Settings → Network → Private DNS → "Private DNS provider hostname"** →
`j4.<your-tailnet>.ts.net`.

⚠️ **Read this first:**

- With a hostname set (strict mode), if **Tailscale is off or the server phone is down, that phone cannot resolve any name** (it looks like "no
  internet"). Enable "Always-on VPN" for Tailscale, and know the escape hatch: set Private DNS back to **Automatic**.
- Android may show *"couldn't access the private DNS server"* on the Wi-Fi network screen while blocking works. It validates the hostname on the
  underlying network, where the `ts.net` name does not exist. Ignore it as long as pages load.
- **Android bypasses Tailscale's MagicDNS when Private DNS is set.** That is why the resolver answers **tailnet names itself** (below); without it,
  `https://j4.<tailnet>.ts.net/` stops opening on that phone.

## Features

- **Blocklist:** any "hosts"-format or plain domain list; matching covers the domain and all its subdomains (never a bare TLD). Refreshed
  automatically after 7 days (a sanity check refuses a list under 10,000 domains); `kill -HUP <pid>` reloads the files.
- **`~/.dnsblock/allow.txt`** (never block these) and **`custom.txt`** (block these too): one domain per line, `#` comments. Reload with `pkill -HUP -f dnsblock.py`.
- **Tailnet names:** every node of your tailnet (from `tailscale status --json`, refreshed every 60 s) resolves to its Tailscale IPs, so the cloud URL works
  with Private DNS on. New devices take up to a minute to appear.
- **No query log.** Only counters (`stats.json`: queries and blocks today, top blocked domains). Delete the file any time.
- **Health probe:** the always-blocked name `saude.dnsblock.invalid` lets the bot test the resolver without depending on the internet.

## From Telegram

- `/dns` — state, today's queries/blocks (percentage), list size and age, top blocked domains.
- **Watchdog:** every 30 s the bot probes the resolver and checks that `tailscaled` runs. After **two** consecutive failures it sends
  "⚠️ Bloqueador de DNS com problema…" and, on recovery, "✅ … voltou ao normal". It also restarts the supervisor if it vanished.
  `touch ~/.dnsblock/disabled` silences it (and stops the supervisor loop) during maintenance.

## Files on the phone

`~/.dnsblock/`: `dnsblock.py`, `run.sh`, `blocklist.txt`, `allow.txt`, `custom.txt`, `stats.json`, `dnsblock.log`.

## Limits

- All queries arrive from the local Tailscale proxy, so there are **no per-device statistics**.
- Apps with their own DNS-over-HTTPS or fixed IPs, and ads served from the same domain as the content (e.g. YouTube), are not blocked.
- Upstream traffic to 1.1.1.1/9.9.9.9/8.8.8.8 is plain UDP from the phone's network. Change `UPSTREAMS` in the script if you prefer another resolver.
- Anyone on the tailnet can use it as a resolver ([SECURITY.md](../SECURITY.md)).
- Not verified: behaviour after a reboot of the phone.

## Tests

`tests/test_dnsblock.py` covers list parsing, subdomain/allowlist logic, packet building for A/AAAA/HTTPS, tailnet answers (including the
`tailscale status --json` parsing with a fake command), and real UDP/TCP servers on loopback.
