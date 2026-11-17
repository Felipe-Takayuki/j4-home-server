# Security

## Threat model

This project is meant for **one person's tailnet**, not for the public internet.

| Surface | How it is protected |
|---|---|
| Cloud (dufs) | Binds to `127.0.0.1`. Reachable only through `tailscale serve` (tailnet-only HTTPS). HTTP Basic auth with a random password generated at install time. |
| DNS resolver | Binds to `127.0.0.1:5353`. Exposed as DNS-over-TLS on port 853 **to the whole tailnet** (see below). Does not log queries. |
| SSH | Termux `sshd` on port 8022, `PasswordAuthentication no`, keys only. Reachable over the tailnet (and the LAN, if you do not firewall it). |
| Telegram bot | Outbound-only long polling. Every update is checked against `OWNER_ID` for both the sender and the chat; everything else is ignored (and logged by id only). The token is passed to `curl` through stdin (`-K -`) so it never appears in the process list. |
| Secrets on the phone | `~/.tgbot/config` (token), `~/.dufs/config.yaml` (password): both `chmod 600`, inside Termux's private storage. Nothing secret is stored in this repository. |

## Things you must know

- **Android 10 is end-of-life and the debloat list removes Google Play Services** (and with it Play Protect). The phone
  will not get security patches. Keep it behind Tailscale. **Never** use port forwarding, `tailscale funnel` or any public tunnel with it.
- **Anyone on your tailnet can use the DNS resolver** (and reach the cloud login page). If you share your tailnet or share
  this node, restrict it with Tailscale ACLs (`tag:` + `accept` rules).
- **Blocking by DNS is a convenience, not a security boundary**: apps that use their own DNS-over-HTTPS or hard-coded
  addresses bypass it.
- If a bot token is ever pasted somewhere public (chat, screenshot, issue), revoke it in BotFather (`/revoke`) and put the new
  one in `~/.tgbot/config`.
- The phone's battery is a physical risk when a device is kept on a charger 24/7 (swelling). Check it now and then.

## Reporting a vulnerability

Please use GitHub's **private vulnerability reporting** (Security tab → "Report a vulnerability") instead of a public
issue. Include what you found, how to reproduce it and, if you can, a suggested fix. This is a hobby project, so there is no
SLA, but reports are taken seriously.
