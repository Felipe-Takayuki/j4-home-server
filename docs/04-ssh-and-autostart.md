# 04 — SSH and the first boot script

Goal: a key-only shell on the phone, started at boot. Once Tailscale is up ([05](05-tailscale.md)) you can reach it from anywhere on your tailnet.

## sshd

Termux's OpenSSH listens on **port 8022** (non-root cannot bind port 22) and the user is whatever `whoami` prints in Termux (`u0_aNNN`);
there is no password to set.

1. On the phone, in Termux, put your **public** key in `~/.ssh/authorized_keys` (type it, or push it over `adb`):
   ```sh
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   # paste the line from your PC's ~/.ssh/id_ed25519.pub:
   cat >> ~/.ssh/authorized_keys     # then Ctrl+D
   chmod 600 ~/.ssh/authorized_keys
   ```
2. Disable passwords. The author's effective `sshd_config` (`$PREFIX/etc/ssh/sshd_config`) is just:
   ```
   AuthorizedKeysFile  .ssh/authorized_keys
   Subsystem  sftp  /data/data/com.termux/files/usr/libexec/sftp-server
   Port 8022
   PasswordAuthentication no
   PubkeyAuthentication yes
   ```
3. Install the boot script and start it now:
   ```sh
   cp termux/boot/10-sshd ~/.termux/boot/10-sshd && chmod 755 ~/.termux/boot/10-sshd   # or push it with tools/adb-run.sh
   sh ~/.termux/boot/10-sshd
   ```
4. From the PC (using the phone's LAN IP now, its tailnet name later):
   ```sh
   ssh -p 8022 u0_aNNN@<phone-ip>
   ```

## No SSH yet? Use adb

You do not need SSH to continue: [`tools/adb-run.sh`](13-deploying-from-a-pc.md) runs repo scripts in Termux over `adb`. SSH is nicer for
interactive work and for scripts that need your secrets typed on the phone, not through `adb`.

## Security notes

- Keep `PasswordAuthentication no`. The phone is reachable on your LAN as soon as sshd starts.
- If your tailnet has other people or nodes, restrict who can reach port 8022 with Tailscale ACLs.

Next: [05 — Tailscale](05-tailscale.md).
