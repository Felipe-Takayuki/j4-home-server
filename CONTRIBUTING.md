# Contributing

Thanks for looking! This project is small and personal, but contributions are welcome — especially:

- **Other devices / Android versions**: tell us what worked or broke (open an issue with the model, Android version, CPU
  architecture and Termux version), or send a PR that adds a note to [docs/11-android10-pitfalls.md](docs/11-android10-pitfalls.md).
- **Translations** of the bot's messages (they are Brazilian Portuguese strings inside `tgbot/bot.sh`; a `LANG`-style
  message table would be a welcome refactor) and of the docs.
- **Bug fixes and tests.**

## Ground rules

- **Never commit secrets or personal data**: bot tokens, passwords, Tailscale keys, your tailnet name (`*.ts.net`), IP addresses, device
  serial numbers, package lists of your own phone. Use placeholders like `<your-tailnet>.ts.net`.
- **Keep it light.** The target is a phone with ~1.8 GB of RAM and a slow 32-bit CPU. Prefer shell and Python's standard library; avoid
  new dependencies, and anything that needs `pkg upgrade` on an old Termux (see the docs for why).
- **Keep it rootless and local-only.** No feature may require root or expose a service outside the tailnet by default.
- **Test what you can without the phone.** `make test` (or `./tests/run.sh`) must pass. If you change the DNS server or the alarm
  logic, add a test in `tests/`.
- Shell scripts run under Termux's `bash`/`sh` on Android's bionic libc: no `getent`, no `nc`, `/proc/uptime` and `/proc/stat` are not
  readable, and `pgrep -f` can match its own command line. Check [docs/11](docs/11-android10-pitfalls.md) first.

## Workflow

1. Fork, create a branch, make a focused change.
2. `make test`.
3. If it touches the phone-side behaviour, say on which device you tried it (or that you could not).
4. Open a pull request describing what and why.

Code comments and the bot are mostly in Brazilian Portuguese; documentation is in English. Either language is fine in issues and PRs.
