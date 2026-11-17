# 05 — Tailscale (userspace networking, no root)

Goal: the phone is a node on your private network with a stable name (`j4.<your-tailnet>.ts.net`) and a real HTTPS certificate, without
opening any port to the internet and without occupying Android's single VPN slot.

## Why the official static binary and "userspace networking"

- Android allows one VPN at a time, and a server does not need a TUN device at all: `tailscaled --tun=userspace-networking` implements
  the network stack in-process and exposes services through `tailscale serve`.
- The author used the **official static `arm` (32-bit) tarball** from <https://pkgs.tailscale.com/stable/#static> (pick `arm64` instead on a
  64-bit phone) and copied `tailscale` and `tailscaled` to `$PREFIX/bin`. Version used: **1.104.7**. (Check what your Termux repository offers
  before doing the same; the official static build is the one this repo is tested with.)

## The crash you will hit: SIGSYS

On Android 10 the process is killed by `seccomp` (`SIGSYS`) as soon as it calls `statx` or `faccessat2`. Go's `os/exec.LookPath`
calls `faccessat2` for every directory in `$PATH`, so any Go program that looks up an executable dies. The fix used everywhere
here is to run Go programs with an **empty directory as `PATH`**. That is why this repo ships two tiny wrappers:

- [`termux/bin/ts-start`](../termux/bin/ts-start) — starts `tailscaled` with `PATH=~/.tailscale/emptybin`.
- [`termux/bin/ts`](../termux/bin/ts) — runs the `tailscale` CLI with the same empty `PATH` and the right `--socket`.

Details and other affected programs are in [11](11-android10-pitfalls.md).

## Install

```sh
# on the phone, after copying the two binaries to $PREFIX/bin
# (copy ts and ts-start from this repo into $PREFIX/bin too, chmod 755)
mkdir -p ~/.tailscale/emptybin
ts-start                                 # starts tailscaled in the background
cp termux/boot/20-tailscale ~/.termux/boot/ && chmod 755 ~/.termux/boot/20-tailscale

ts up --hostname=j4                      # prints a login URL
```

The phone has no browser, so **open the printed URL on another device** (your PC) and approve the node. Then:

```sh
ts status                                # you should see the phone and your other devices
```

In the Tailscale admin console ([login.tailscale.com](https://login.tailscale.com)): enable **MagicDNS** and **HTTPS certificates**
(DNS page). You need both for `https://j4.<your-tailnet>.ts.net`.

## Expose a service: `tailscale serve`

`tailscale serve` terminates TLS with the node's real certificate and forwards to a local port. Only devices on your tailnet can connect.

```sh
ts serve --bg --https=443 http://127.0.0.1:8080                       # the cloud (dufs), see 06
ts serve --bg --tls-terminated-tcp=853 tcp://localhost:5353           # DNS-over-TLS for the ad blocker, see 10
ts serve status
```

Notes:

- `tailscale serve` merges new ports into the existing configuration; `ts serve reset` clears everything.
- **Large unauthenticated uploads** through the serve proxy return `502` instead of a `401` challenge (verified with a 60 MB `PUT`
  without credentials → 502, with `Authorization` → 201). The web UI therefore sends the `Authorization` header itself on uploads.
- The author runs the node with `--accept-dns=false` (Tailscale DNS is *not* applied on the phone itself); that does not affect serving.
- Do **not** use `tailscale funnel`: it publishes the service on the public internet.

## Sharing a tailnet

If other accounts' nodes are visible in `ts status` (shared nodes, old invitations), check your ACLs: they could reach the phone's services.
See [SECURITY.md](../SECURITY.md).

Next: [06 — The cloud (dufs)](06-dufs-cloud.md).
